package app

import (
	"context"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

func nz(s string) any {
	if s == "" {
		return nil
	}
	return s
}

var registerFiles = []string{"aadhar_front", "aadhar_back", "pan_front", "passport_photo", "membership_proof"}

// POST /api/auth/register  (multipart/form-data)
func (s *Server) register(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseMultipartForm(32 << 20); err != nil {
		fail(w, 400, "Invalid form data")
		return
	}
	f := func(k string) string { return strings.TrimSpace(r.FormValue(k)) }
	email, phone := normEmail(f("email")), normPhone(f("phone"))
	aadhar, pan := reDigits.ReplaceAllString(f("aadharNumber"), ""), strings.ToUpper(f("panNumber"))
	pw := r.FormValue("password")

	// Logged-in user (signed up with email+password earlier) completing their application: reuse that account.
	var existingUID string
	var existingRoles []string
	if tok := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer "); tok != "" {
		if c, ok := s.parseJWT(tok); ok {
			existingUID, existingRoles = c.Sub, c.Roles
			email = normEmail(c.Email)
		}
	}

	switch {
	case f("firstName") == "" || f("lastName") == "":
		fail(w, 400, "First and last name are required")
		return
	case !reEmail.MatchString(email):
		fail(w, 400, "Enter a valid email")
		return
	case len(phone) != 13:
		fail(w, 400, "Enter a valid 10-digit phone number")
		return
	case !reAadhar.MatchString(aadhar):
		fail(w, 400, "Aadhaar must be 12 digits")
		return
	case !rePAN.MatchString(pan):
		fail(w, 400, "Invalid PAN format (e.g. ABCDE1234F)")
		return
	case existingUID == "" && len(pw) < 8:
		fail(w, 400, "Password must be at least 8 characters")
		return
	case f("fullAddress") == "":
		fail(w, 400, "Address is required")
		return
	}
	dob, err := time.Parse("2006-01-02", f("dateOfBirth"))
	if err != nil {
		fail(w, 400, "Date of birth must be YYYY-MM-DD")
		return
	}
	age := time.Now().Year() - dob.Year()
	if time.Now().YearDay() < dob.YearDay() {
		age--
	}
	if age < 18 {
		fail(w, 400, "Applicant must be at least 18 years old")
		return
	}
	for _, k := range registerFiles {
		if r.MultipartForm == nil || len(r.MultipartForm.File[k]) == 0 {
			fail(w, 400, "Missing document: "+k)
			return
		}
	}
	co := f("hasCoApplicant") == "true"

	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		fail(w, 500, "DB error")
		return
	}
	defer tx.Rollback()

	var userID, appID, uniqueID string
	if existingUID != "" {
		userID = existingUID
	} else if err := tx.QueryRowContext(r.Context(), `INSERT INTO users(email,password_hash) VALUES ($1,$2) RETURNING id`, email, hashPassword(pw)).Scan(&userID); err != nil {
		if m := isUniqueErr(err); m != "" {
			fail(w, 409, m)
			return
		}
		fail(w, 500, "Failed to create user")
		return
	}
	var cn, cr, cd, ca, cp, cph any
	if co {
		cn, cr, cd, ca, cp, cph = nz(f("coApplicantName")), nz(f("coApplicantRelation")), nz(f("coApplicantDob")),
			nz(f("coApplicantAadhar")), nz(strings.ToUpper(f("coApplicantPan"))), nz(f("coApplicantPhone"))
	}
	err = tx.QueryRowContext(r.Context(), `INSERT INTO applicants(user_id,first_name,last_name,father_name,spouse_name,date_of_birth,age,occupation,
		blood_group,full_address,aadhar_number,pan_number,email,phone,has_co_applicant,co_applicant_name,co_applicant_relation,co_applicant_dob,
		co_applicant_aadhar,co_applicant_pan,co_applicant_phone,handling_admin_id,handling_admin_selected_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18::date,$19,$20,$21,$22::uuid,CASE WHEN $22::text IS NULL THEN NULL ELSE now() END)
		RETURNING id, unique_id`,
		userID, f("firstName"), f("lastName"), nz(f("fatherName")), nz(f("spouseName")), f("dateOfBirth"), age, nz(f("occupation")),
		nz(f("bloodGroup")), f("fullAddress"), aadhar, pan, email, phone, co, cn, cr, cd, ca, cp, cph, nz(f("handlingAdminId"))).Scan(&appID, &uniqueID)
	if err != nil {
		if m := isUniqueErr(err); m != "" {
			fail(w, 409, m)
			return
		}
		fail(w, 500, "Failed to create application: "+err.Error())
		return
	}
	for _, k := range registerFiles {
		fh := r.MultipartForm.File[k][0]
		rel, err := s.saveFile(r.Context(), appID, k, fh)
		if err != nil {
			_ = os.RemoveAll(filepath.Join(s.cfg.UploadDir, appID))
			s.dropBlobs(r.Context(), appID+"/")
			fail(w, 400, err.Error())
			return
		}
		if _, err := tx.ExecContext(r.Context(), `INSERT INTO uploads(applicant_id,upload_type,file_name,file_path,file_size,uploaded_by) VALUES ($1,$2,$3,$4,$5,$6)`,
			appID, k, fh.Filename, rel, fh.Size, userID); err != nil {
			_ = os.RemoveAll(filepath.Join(s.cfg.UploadDir, appID))
			s.dropBlobs(r.Context(), appID+"/")
			fail(w, 500, "Failed to save upload record")
			return
		}
	}
	if err := tx.Commit(); err != nil {
		fail(w, 500, "Commit failed")
		return
	}
	go func() { // small delay: the app registers its device token right after this response
		time.Sleep(6 * time.Second)
		s.notify(context.Background(), appID, "registered", "Registration received", "Your application is submitted. Verify your email or phone to continue.")
	}()
	if existingRoles == nil {
		existingRoles = []string{}
	}
	tok := s.signJWT(Claims{Sub: userID, Email: email, Roles: existingRoles})
	writeJSON(w, 201, M{"success": true, "token": tok, "applicantId": appID, "uniqueId": uniqueID})
}

// POST /api/auth/signup {email,password}  -> creates only the account (no application yet) and logs the user in.
func (s *Server) signup(w http.ResponseWriter, r *http.Request) {
	var in struct{ Email, Password string }
	if !decode(r, &in) {
		fail(w, 400, "Invalid body")
		return
	}
	email := normEmail(in.Email)
	if !reEmail.MatchString(email) {
		fail(w, 400, "Enter a valid email")
		return
	}
	if len(in.Password) < 8 {
		fail(w, 400, "Password must be at least 8 characters")
		return
	}
	var userID string
	if err := s.db.QueryRowContext(r.Context(), `INSERT INTO users(email,password_hash) VALUES ($1,$2) RETURNING id`, email, hashPassword(in.Password)).Scan(&userID); err != nil {
		if m := isUniqueErr(err); m != "" {
			fail(w, 409, m)
			return
		}
		fail(w, 500, "Failed to create account")
		return
	}
	tok := s.signJWT(Claims{Sub: userID, Email: email, Roles: []string{}})
	writeJSON(w, 201, M{"success": true, "message": "Account created successfully", "token": tok})
}

// POST /api/auth/login {email,password}
func (s *Server) login(w http.ResponseWriter, r *http.Request) {
	var in struct{ Email, Password string }
	if !decode(r, &in) {
		fail(w, 400, "Invalid body")
		return
	}
	var id, hash string
	err := s.db.QueryRowContext(r.Context(), `SELECT id, password_hash FROM users WHERE email=$1`, normEmail(in.Email)).Scan(&id, &hash)
	if err != nil || !checkPassword(in.Password, hash) {
		fail(w, 401, "Invalid email or password")
		return
	}
	roleRows, _ := s.many(r.Context(), `SELECT role FROM user_roles WHERE user_id=$1`, id)
	roles := []string{}
	for _, x := range roleRows {
		roles = append(roles, x["role"].(string))
	}
	tok := s.signJWT(Claims{Sub: id, Email: normEmail(in.Email), Roles: roles})
	writeJSON(w, 200, M{"success": true, "token": tok, "roles": roles, "isAdmin": len(roles) > 0})
}

// GET /api/public/admins : list of handling admins for the registration dropdown
func (s *Server) publicAdmins(w http.ResponseWriter, r *http.Request) {
	rows, err := s.many(r.Context(), `SELECT DISTINCT ur.user_id AS id,
		COALESCE(ur.display_name, a.first_name||' '||a.last_name, 'Admin '||LEFT(ur.user_id::text,8)) AS name
		FROM user_roles ur LEFT JOIN applicants a ON a.user_id=ur.user_id WHERE ur.role IN ('admin','super_admin')`)
	if err != nil {
		fail(w, 500, "DB error")
		return
	}
	writeJSON(w, 200, M{"success": true, "admins": rows})
}