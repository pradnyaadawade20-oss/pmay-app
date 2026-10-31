package app

// Endpoints used by the PMAY admin panel (Flutter web). They reuse the same
// database and business rules as the applicant API in admin.go.

import (
	"bytes"
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// rewriteBody replaces the request JSON body (used to adapt panel payloads to existing handlers).
func rewriteBody(r *http.Request, v any) {
	b, _ := json.Marshal(v)
	r.Body = io.NopCloser(bytes.NewReader(b))
}

// POST /api/admin/applicants/{id}/review {decision: approve|reject, reason}
func (s *Server) adminReview(w http.ResponseWriter, r *http.Request) {
	var in struct{ Decision, Reason string }
	if !decode(r, &in) {
		fail(w, 400, "Invalid body")
		return
	}
	action := map[string]string{"approve": "accept", "accept": "accept", "reject": "reject"}[in.Decision]
	if action == "" {
		fail(w, 400, "decision must be approve or reject")
		return
	}
	rewriteBody(r, M{"action": action, "reason": in.Reason})
	s.adminValidation(w, r)
}

// GET /api/admin/stats shape expected by the panel: {stats:{...}}
func (s *Server) panelStats(w http.ResponseWriter, r *http.Request) {
	var total, pending, payments, completed, units int
	_ = s.db.QueryRowContext(r.Context(), `SELECT
		(SELECT count(*) FROM applicants),
		(SELECT count(*) FROM applicants WHERE registration_stage='stage_1_registered' AND stage_2_status='pending'),
		(SELECT count(*) FROM payments WHERE payment_status='pending' AND payment_method='offline'),
		(SELECT count(*) FROM applicants WHERE registration_stage='stage_10_completed'),
		(SELECT count(*) FROM units WHERE status='available')`).Scan(&total, &pending, &payments, &completed, &units)
	rows, _ := s.many(r.Context(), `SELECT registration_stage AS stage, count(*)::int AS n FROM applicants GROUP BY 1`)
	by := M{}
	for _, x := range rows {
		by[x["stage"].(string)] = x["n"]
	}
	var pendAgr, pendBank, today int
	_ = s.db.QueryRowContext(r.Context(), `SELECT
		(SELECT count(*) FROM applicants WHERE registration_stage='stage_6_agreement_receipt'),
		(SELECT count(*) FROM loan_details l JOIN applicants a ON a.id=l.applicant_id WHERE a.registration_stage='stage_7_bank_document' AND l.loan_status='pending'
		   AND l.upi_statement_path IS NOT NULL AND l.itr_year1_path IS NOT NULL AND l.itr_year2_path IS NOT NULL AND l.itr_year3_path IS NOT NULL AND l.bank_statement_path IS NOT NULL),
		COALESCE((SELECT count FROM stage_2_daily_counter WHERE date=current_date),0)`).Scan(&pendAgr, &pendBank, &today)
	writeJSON(w, 200, M{"success": true, "stats": M{"total": total, "pending_review": pending, "pending_payments": payments,
		"completed": completed, "available_units": units, "by_stage": by,
		"pending_agreement_receipts": pendAgr, "pending_bank_reviews": pendBank, "accepted_today": today, "daily_limit": 1000}})
}

// GET /api/admin/applicants?search=&stage=  (adds handled_by_name)
func (s *Server) panelApplicants(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	search := q.Get("search")
	if search == "" {
		search = q.Get("q")
	}
	rows, err := s.many(r.Context(), `SELECT a.id,a.unique_id,a.first_name,a.last_name,a.email,a.phone,a.email_verified,a.phone_verified,
		a.registration_stage,a.stage_2_status,a.stage_2_reason,a.stage_4_status,a.stage_4_reason,a.handling_admin_id,a.created_at,a.updated_at,
		a.pan_number,a.aadhar_number,l.loan_status,
		(CASE WHEN l.upi_statement_path IS NOT NULL THEN 1 ELSE 0 END + CASE WHEN l.itr_year1_path IS NOT NULL THEN 1 ELSE 0 END +
		 CASE WHEN l.itr_year2_path IS NOT NULL THEN 1 ELSE 0 END + CASE WHEN l.itr_year3_path IS NOT NULL THEN 1 ELSE 0 END +
		 CASE WHEN l.bank_statement_path IS NOT NULL THEN 1 ELSE 0 END) AS bank_documents_count,
		COALESCE(ur.display_name,'') AS handled_by_name
		FROM applicants a LEFT JOIN loan_details l ON l.applicant_id=a.id LEFT JOIN LATERAL (SELECT display_name FROM user_roles WHERE user_id=a.handling_admin_id LIMIT 1) ur ON true
		WHERE ($1='' OR a.registration_stage=$1)
		AND ($2='' OR a.first_name||' '||a.last_name ILIKE '%'||$2||'%' OR a.unique_id ILIKE '%'||$2||'%'
		     OR a.phone LIKE '%'||$2||'%' OR a.email ILIKE '%'||$2||'%' OR a.pan_number ILIKE $2)
		ORDER BY a.created_at DESC LIMIT 500`, q.Get("stage"), search)
	if err != nil {
		fail(w, 500, "DB error")
		return
	}
	writeJSON(w, 200, M{"success": true, "applicants": rows})
}

// docColumns maps a document kind to the column holding its file path (besides the uploads table).
var docColumns = map[string]string{
	"upi_statement":     `SELECT upi_statement_path AS p FROM loan_details WHERE applicant_id::text=$1`,
	"itr_year1":         `SELECT itr_year1_path AS p FROM loan_details WHERE applicant_id::text=$1`,
	"itr_year2":         `SELECT itr_year2_path AS p FROM loan_details WHERE applicant_id::text=$1`,
	"itr_year3":         `SELECT itr_year3_path AS p FROM loan_details WHERE applicant_id::text=$1`,
	"bank_statement":    `SELECT bank_statement_path AS p FROM loan_details WHERE applicant_id::text=$1`,
	"agreement_signed":  `SELECT agreement_receipt_path AS p FROM applicants WHERE id::text=$1`,
	"bank_loan_receipt": `SELECT bank_loan_receipt_path AS p FROM applicants WHERE id::text=$1`,
	"mortgage_receipt":  `SELECT mortgage_receipt_path AS p FROM applicants WHERE id::text=$1`,
	"payment_receipt":   `SELECT offline_receipt_path AS p FROM payments WHERE applicant_id::text=$1 AND offline_receipt_path IS NOT NULL ORDER BY created_at DESC`,
}

// GET /api/admin/applicants/{id}/documents/{kind}: raw bytes of the applicant's file of that kind
// (registration documents, signed agreement, bank documents, receipts).
func (s *Server) adminApplicantDoc(w http.ResponseWriter, r *http.Request) {
	id, kind := r.PathValue("id"), r.PathValue("kind")
	q, ok := docColumns[kind]
	args := []any{id}
	if !ok {
		q, args = `SELECT file_path AS p FROM uploads WHERE applicant_id::text=$1 AND upload_type=$2 ORDER BY uploaded_at DESC`, []any{id, kind}
	}
	m, _ := s.one(r.Context(), q, args...)
	p, _ := m["p"].(string)
	if p == "" {
		fail(w, 404, "Document not found")
		return
	}
	rel := filepath.Clean(p)
	if strings.Contains(rel, "..") {
		fail(w, 400, "Bad path")
		return
	}
	s.serveStored(w, r, rel)
}

// ---- units ----

func (s *Server) panelUnits(w http.ResponseWriter, r *http.Request) {
	rows, err := s.many(r.Context(), `SELECT u.id,u.unit_number,u.tower,u.wing,u.floor,u.carpet_area_sqm AS carpet_area,
		u.consideration_amount AS amount,u.status,
		CASE WHEN a.id IS NULL THEN NULL ELSE a.unique_id||' - '||a.first_name||' '||a.last_name END AS allotted_to
		FROM units u LEFT JOIN applicants a ON a.id=u.allocated_to ORDER BY u.floor,u.unit_number`)
	if err != nil {
		fail(w, 500, "DB error")
		return
	}
	writeJSON(w, 200, M{"success": true, "units": rows})
}

func (s *Server) eligibleApplicants(w http.ResponseWriter, r *http.Request) {
	rows, err := s.many(r.Context(), `SELECT id,unique_id,first_name,last_name FROM applicants
		WHERE registration_stage='stage_4_allotment' ORDER BY created_at`)
	if err != nil {
		fail(w, 500, "DB error")
		return
	}
	writeJSON(w, 200, M{"success": true, "applicants": rows})
}

// POST /api/admin/units/{id}/allot {applicant_id}
func (s *Server) panelAllot(w http.ResponseWriter, r *http.Request) {
	var in struct {
		ApplicantID string `json:"applicant_id"`
	}
	if !decode(r, &in) || in.ApplicantID == "" {
		fail(w, 400, "applicant_id required")
		return
	}
	unit := r.PathValue("id")
	r.SetPathValue("id", in.ApplicantID)
	rewriteBody(r, M{"unitId": unit})
	s.adminAllot(w, r)
}

// ---- payments ----

// GET /api/admin/payments?status=pending
func (s *Server) panelPayments(w http.ResponseWriter, r *http.Request) {
	rows, err := s.many(r.Context(), `SELECT p.id,a.unique_id,a.first_name||' '||a.last_name AS applicant_name,p.amount,
		COALESCE(NULLIF(p.payment_mode,''),p.payment_method) AS mode,p.payment_method,p.payment_status,p.payment_stage,p.payment_stage AS stage,
		p.offline_receipt_path,p.receipt_number,COALESCE(p.gateway_payment_id,p.razorpay_payment_id) AS transaction_id,p.payment_date,p.created_at,
		a.email AS applicant_email,a.phone AS applicant_phone,p.payment_mode,p.cheque_number,p.cheque_bank,p.note
		FROM payments p JOIN applicants a ON a.id=p.applicant_id
		WHERE ($1='' OR $1='all' OR p.payment_status=$1)
		AND NOT ($1='pending' AND p.payment_method='online') ORDER BY p.created_at DESC LIMIT 500`, r.URL.Query().Get("status"))
	if err != nil {
		fail(w, 500, "DB error")
		return
	}
	writeJSON(w, 200, M{"success": true, "payments": rows})
}

// POST /api/admin/payments/{id}/confirm|reject
func (s *Server) panelPayAct(w http.ResponseWriter, r *http.Request) {
	act := "accept"
	switch r.PathValue("act") {
	case "reject":
		act = "reject"
	case "confirm":
	default:
		fail(w, 404, "Unknown action")
		return
	}
	rewriteBody(r, M{"action": act})
	s.adminPaymentReview(w, r)
}

// ---- document settings ----

func (s *Server) docSettings(w http.ResponseWriter, r *http.Request) {
	rows, err := s.many(r.Context(), `SELECT document_type AS kind, COALESCE(label,document_type) AS label, max_size_mb::float8 AS max_size_mb,
		allowed_extensions, ai_validation FROM document_settings ORDER BY document_type`)
	if err != nil {
		fail(w, 500, "DB error")
		return
	}
	writeJSON(w, 200, M{"success": true, "settings": rows})
}

func (s *Server) docSettingSave(w http.ResponseWriter, r *http.Request) {
	var in struct {
		MaxSizeMB    float64 `json:"max_size_mb"`
		AIValidation bool    `json:"ai_validation"`
	}
	if !decode(r, &in) || in.MaxSizeMB <= 0 || in.MaxSizeMB > 25 {
		fail(w, 400, "max_size_mb must be between 0 and 25")
		return
	}
	res, err := s.db.ExecContext(r.Context(), `UPDATE document_settings SET max_size_mb=$2, ai_validation=$3 WHERE document_type=$1`,
		r.PathValue("kind"), in.MaxSizeMB, in.AIValidation)
	if err != nil {
		fail(w, 500, "DB error")
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		fail(w, 404, "Unknown document type")
		return
	}
	s.audit(r.Context(), claimsOf(r).Sub, "document_setting", "document_settings", "", M{"kind": r.PathValue("kind"), "max": in.MaxSizeMB})
	writeJSON(w, 200, M{"success": true})
}

// ---- user management ----

var validRoles = map[string]bool{"super_admin": true, "admin": true, "finance": true, "allotment_manager": true, "auditor": true}

func (s *Server) panelUsers(w http.ResponseWriter, r *http.Request) {
	rows, err := s.many(r.Context(), `SELECT ur.user_id, COALESCE(ur.display_name,u.email) AS display_name, u.email, ur.role, ur.assigned_at
		FROM user_roles ur JOIN users u ON u.id=ur.user_id ORDER BY ur.assigned_at, u.email`)
	if err != nil {
		fail(w, 500, "DB error")
		return
	}
	writeJSON(w, 200, M{"success": true, "users": rows})
}

type roleIn struct {
	Email       string `json:"email"`
	Password    string `json:"password"`
	Role        string `json:"role"`
	DisplayName string `json:"display_name"`
}

func readRoleIn(w http.ResponseWriter, r *http.Request) (roleIn, bool) {
	var in roleIn
	if !decode(r, &in) || !reEmail.MatchString(normEmail(in.Email)) {
		fail(w, 400, "Valid email required")
		return in, false
	}
	if !validRoles[in.Role] {
		fail(w, 400, "Invalid role")
		return in, false
	}
	in.Email = normEmail(in.Email)
	return in, true
}

// POST /api/admin/users/assign: give a role to an existing user
func (s *Server) userAssign(w http.ResponseWriter, r *http.Request) {
	in, ok := readRoleIn(w, r)
	if !ok {
		return
	}
	var id string
	if s.db.QueryRowContext(r.Context(), `SELECT id FROM users WHERE email=$1`, in.Email).Scan(&id) != nil {
		fail(w, 404, "No user with this email")
		return
	}
	_, err := s.db.ExecContext(r.Context(), `INSERT INTO user_roles(user_id,role,display_name) VALUES ($1,$2,NULLIF($3,''))
		ON CONFLICT (user_id,role) DO UPDATE SET display_name=COALESCE(NULLIF($3,''),user_roles.display_name)`, id, in.Role, in.DisplayName)
	if err != nil {
		fail(w, 500, "Could not assign role")
		return
	}
	s.audit(r.Context(), claimsOf(r).Sub, "assign_role", "user", id, M{"role": in.Role})
	writeJSON(w, 200, M{"success": true, "userId": id})
}

// POST /api/admin/users/create {email,password,role,display_name}
func (s *Server) userCreate(w http.ResponseWriter, r *http.Request) {
	in, ok := readRoleIn(w, r)
	if !ok {
		return
	}
	if len(in.Password) < 8 {
		fail(w, 400, "Password must be at least 8 characters")
		return
	}
	s.createUserWithRole(w, r, in, in.Password, nil)
}

// POST /api/admin/users/invite: no mail service is wired up, so a temporary password is generated and returned.
func (s *Server) userInvite(w http.ResponseWriter, r *http.Request) {
	in, ok := readRoleIn(w, r)
	if !ok {
		return
	}
	b := make([]byte, 8)
	_, _ = rand.Read(b)
	tmp := hex.EncodeToString(b)
	s.createUserWithRole(w, r, in, tmp, M{"temp_password": tmp})
}

func (s *Server) createUserWithRole(w http.ResponseWriter, r *http.Request, in roleIn, pw string, extra M) {
	var id string
	if err := s.db.QueryRowContext(r.Context(), `INSERT INTO users(email,password_hash) VALUES ($1,$2) RETURNING id`, in.Email, hashPassword(pw)).Scan(&id); err != nil {
		fail(w, 409, "User already exists - use Assign instead")
		return
	}
	_, _ = s.db.ExecContext(r.Context(), `INSERT INTO user_roles(user_id,role,display_name) VALUES ($1,$2,NULLIF($3,''))`, id, in.Role, in.DisplayName)
	s.audit(r.Context(), claimsOf(r).Sub, "create_user", "user", id, M{"role": in.Role})
	out := M{"success": true, "userId": id}
	for k, v := range extra {
		out[k] = v
	}
	writeJSON(w, 201, out)
}

func (s *Server) userName(w http.ResponseWriter, r *http.Request) {
	var in struct {
		DisplayName string `json:"display_name"`
	}
	if !decode(r, &in) || strings.TrimSpace(in.DisplayName) == "" {
		fail(w, 400, "display_name required")
		return
	}
	if _, err := s.db.ExecContext(r.Context(), `UPDATE user_roles SET display_name=$2 WHERE user_id::text=$1`, r.PathValue("id"), strings.TrimSpace(in.DisplayName)); err != nil {
		fail(w, 500, "DB error")
		return
	}
	writeJSON(w, 200, M{"success": true})
}

// POST /api/admin/users/{id}/delete: removes the user's admin roles (the login account stays).
func (s *Server) userDelete(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if id == claimsOf(r).Sub {
		fail(w, 409, "You cannot remove your own role")
		return
	}
	var supers int
	_ = s.db.QueryRowContext(r.Context(), `SELECT count(*) FROM user_roles WHERE role='super_admin' AND user_id::text<>$1`, id).Scan(&supers)
	if supers == 0 {
		fail(w, 409, "At least one super admin must remain")
		return
	}
	if _, err := s.db.ExecContext(r.Context(), `DELETE FROM user_roles WHERE user_id::text=$1`, id); err != nil {
		fail(w, 500, "DB error")
		return
	}
	s.audit(r.Context(), claimsOf(r).Sub, "remove_roles", "user", id, nil)
	writeJSON(w, 200, M{"success": true})
}

// ---- database browser (super_admin only; whitelisted tables) ----

type dbTable struct {
	sqlName  string
	label    string
	pk       string
	hidden   []string // never returned / never writable
	readOnly bool
}

var dbTables = map[string]dbTable{
	"auth_users":        {"users", "Auth Users", "id", []string{"password_hash"}, true},
	"applicants":        {"applicants", "Applicants", "id", nil, false},
	"payments":          {"payments", "Payments", "id", []string{"razorpay_signature"}, false},
	"units":             {"units", "Units", "id", nil, false},
	"user_roles":        {"user_roles", "User Roles", "id", nil, false}, // rows are identified by their own id (a user can hold several roles)
	"loan_details":      {"loan_details", "Loan Details", "id", nil, false},
	"uploads":           {"uploads", "Uploads", "id", nil, false},
	"audit_logs":        {"audit_logs", "Audit Logs", "id", nil, true},
	"document_settings": {"document_settings", "Document Settings", "document_type", nil, false},
	"project_settings":  {"project_settings", "Project Settings", "id", nil, false},
	"otp_verifications": {"otp_verifications", "OTP Verifications", "id", []string{"otp_code"}, true},
}

func (t dbTable) columns(s *Server, r *http.Request) []string {
	rows, _ := s.many(r.Context(), `SELECT column_name AS c FROM information_schema.columns WHERE table_schema='public' AND table_name=$1 ORDER BY ordinal_position`, t.sqlName)
	var out []string
next:
	for _, x := range rows {
		c := x["c"].(string)
		for _, h := range t.hidden {
			if h == c {
				continue next
			}
		}
		out = append(out, c)
	}
	return out
}

func (s *Server) dbList(w http.ResponseWriter, r *http.Request) {
	out := []M{}
	for name, t := range dbTables {
		var n int
		_ = s.db.QueryRowContext(r.Context(), `SELECT count(*) FROM `+t.sqlName).Scan(&n)
		out = append(out, M{"name": name, "label": t.label, "count": n})
	}
	writeJSON(w, 200, M{"success": true, "tables": out})
}

func (s *Server) dbRows(w http.ResponseWriter, r *http.Request) {
	t, ok := dbTables[r.PathValue("table")]
	if !ok {
		fail(w, 404, "Unknown table")
		return
	}
	cols := t.columns(s, r)
	quoted := make([]string, len(cols))
	for i, c := range cols {
		quoted[i] = `"` + c + `"`
	}
	rows, err := s.many(r.Context(), `SELECT `+strings.Join(quoted, ",")+` FROM `+t.sqlName+` t WHERE ($1='' OR t::text ILIKE '%'||$1||'%') LIMIT 500`, r.URL.Query().Get("search"))
	if err != nil {
		fail(w, 500, "DB error")
		return
	}
	writeJSON(w, 200, M{"success": true, "columns": cols, "rows": rows, "readOnly": t.readOnly})
}

func (s *Server) dbUpdate(w http.ResponseWriter, r *http.Request) {
	t, ok := dbTables[r.PathValue("table")]
	if !ok || t.readOnly {
		fail(w, 403, "Table is read-only")
		return
	}
	var in struct {
		Data map[string]any `json:"data"`
	}
	if !decode(r, &in) || len(in.Data) == 0 {
		fail(w, 400, "data required")
		return
	}
	allowed := map[string]bool{}
	for _, c := range t.columns(s, r) {
		if c != t.pk && c != "id" && c != "created_at" {
			allowed[c] = true
		}
	}
	if r.PathValue("table") == "user_roles" {
		delete(allowed, "user_id") // a role row cannot be moved to another user
		if role, ok := in.Data["role"].(string); ok && role != "super_admin" && !validRoles[role] {
			fail(w, 400, "Invalid role")
			return
		}
		if role, ok := in.Data["role"].(string); ok && role != "super_admin" {
			var cur, owner string
			if s.db.QueryRowContext(r.Context(), `SELECT role, user_id::text FROM user_roles WHERE id::text=$1`, r.PathValue("id")).Scan(&cur, &owner) == nil && cur == "super_admin" {
				if owner == claimsOf(r).Sub {
					fail(w, 409, "You cannot change your own super admin role")
					return
				}
				if s.superAdminCount(r.Context()) <= 1 {
					fail(w, 409, "At least one super admin must remain")
					return
				}
			}
		}
	}
	patch := map[string]any{}
	var cols []string
	for k, v := range in.Data {
		if allowed[k] {
			patch[k] = v
			cols = append(cols, `"`+k+`"`)
		}
	}
	if len(patch) == 0 {
		fail(w, 400, "No editable columns supplied")
		return
	}
	cl := strings.Join(cols, ",")
	pj, _ := json.Marshal(patch)
	q := `UPDATE ` + t.sqlName + ` SET (` + cl + `) = (SELECT ` + cl + ` FROM jsonb_populate_record(NULL::` + t.sqlName + `, $1::jsonb)) WHERE ` + t.pk + `::text=$2`
	res, err := s.db.ExecContext(r.Context(), q, string(pj), r.PathValue("id"))
	if err != nil {
		fail(w, 400, "Update failed: invalid value")
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		fail(w, 404, "Row not found")
		return
	}
	s.audit(r.Context(), claimsOf(r).Sub, "db_update", t.sqlName, "", M{"id": r.PathValue("id")})
	writeJSON(w, 200, M{"success": true})
}

func (s *Server) dbDelete(w http.ResponseWriter, r *http.Request) {
	t, ok := dbTables[r.PathValue("table")]
	// auth_users cannot be edited here, but a login (and its applicant data) can be deleted, with the safeguards below
	if !ok || (t.readOnly && r.PathValue("table") != "auth_users") {
		fail(w, 403, "Table is read-only")
		return
	}
	id := r.PathValue("id")
	ctx := r.Context()
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		fail(w, 500, "DB error")
		return
	}
	defer tx.Rollback()
	var removeDirs []string // upload folders to delete from disk after the commit
	switch r.PathValue("table") {
	case "auth_users":
		if id == claimsOf(r).Sub {
			fail(w, 409, "You cannot delete your own account")
			return
		}
		var admin int
		_ = tx.QueryRowContext(ctx, `SELECT count(*) FROM user_roles WHERE user_id::text=$1`, id).Scan(&admin)
		if admin > 0 {
			fail(w, 409, "This user has an admin role. Remove it in User Management first.")
			return
		}
		rows, qerr := tx.QueryContext(ctx, `SELECT id::text FROM applicants WHERE user_id::text=$1`, id)
		if qerr != nil {
			fail(w, 500, "DB error")
			return
		}
		var appIDs []string
		for rows.Next() {
			var a string
			if rows.Scan(&a) == nil {
				appIDs = append(appIDs, a)
			}
		}
		rows.Close()
		for _, a := range appIDs { // free the unit, drop stored files, then the application and finally the login
			_, _ = tx.ExecContext(ctx, `UPDATE units SET status='available', allocated_to=NULL, allocated_at=NULL WHERE allocated_to::text=$1`, a)
			_, _ = tx.ExecContext(ctx, `DELETE FROM file_blobs WHERE path LIKE $1`, a+"/%")
			removeDirs = append(removeDirs, filepath.Join(s.cfg.UploadDir, a))
		}
		if _, err = tx.ExecContext(ctx, `DELETE FROM applicants WHERE user_id::text=$1`, id); err == nil {
			var res sql.Result
			if res, err = tx.ExecContext(ctx, `DELETE FROM users WHERE id::text=$1`, id); err == nil {
				if n, _ := res.RowsAffected(); n == 0 {
					fail(w, 404, "User not found")
					return
				}
			}
		}
	case "applicants":
		// free any unit, then drop the login too so the person can re-register
		_, _ = tx.ExecContext(ctx, `UPDATE units SET status='available', allocated_to=NULL, allocated_at=NULL WHERE allocated_to::text=$1`, id)
		_, _ = tx.ExecContext(ctx, `DELETE FROM file_blobs WHERE path LIKE $1`, id+"/%")
		var userID string
		if err = tx.QueryRowContext(ctx, `DELETE FROM applicants WHERE id::text=$1 RETURNING user_id`, id).Scan(&userID); err == nil {
			_, err = tx.ExecContext(ctx, `DELETE FROM users WHERE id=$1`, userID)
		}
	case "units":
		_, err = tx.ExecContext(ctx, `DELETE FROM units WHERE id::text=$1 AND allocated_to IS NULL`, id)
	case "user_roles":
		var owner, role string
		if err := tx.QueryRowContext(ctx, `SELECT user_id::text, role FROM user_roles WHERE id::text=$1`, id).Scan(&owner, &role); err != nil {
			fail(w, 404, "Row not found")
			return
		}
		if owner == claimsOf(r).Sub {
			fail(w, 409, "You cannot remove your own role")
			return
		}
		if role == "super_admin" && s.superAdminCount(ctx) <= 1 {
			fail(w, 409, "At least one super admin must remain")
			return
		}
		_, err = tx.ExecContext(ctx, `DELETE FROM user_roles WHERE id::text=$1`, id)
	default:
		_, err = tx.ExecContext(ctx, `DELETE FROM `+t.sqlName+` WHERE `+t.pk+`::text=$1`, id)
	}
	if err != nil || tx.Commit() != nil {
		fail(w, 409, "Row cannot be deleted (it is referenced elsewhere)")
		return
	}
	for _, d := range removeDirs {
		_ = os.RemoveAll(d)
	}
	s.audit(ctx, claimsOf(r).Sub, "db_delete", t.sqlName, "", M{"id": id})
	writeJSON(w, 200, M{"success": true})
}

// GET /api/admin/system-status: live health for the dashboard (all values come from real checks).
func (s *Server) systemStatus(w http.ResponseWriter, r *http.Request) {
	status := M{}
	start := time.Now()
	if err := s.db.PingContext(r.Context()); err != nil {
		status["database"] = M{"ok": false, "detail": "unreachable"}
	} else {
		status["database"] = M{"ok": true, "detail": fmt.Sprintf("connected (%d ms)", time.Since(start).Milliseconds())}
	}
	probe := filepath.Join(s.cfg.UploadDir, ".healthcheck")
	if err := os.WriteFile(probe, []byte("ok"), 0o644); err != nil {
		status["storage"] = M{"ok": false, "detail": "not writable"}
	} else {
		_ = os.Remove(probe)
		status["storage"] = M{"ok": true, "detail": "writable"}
	}
	status["email"] = M{"ok": s.cfg.SMTPHost != "" && s.cfg.SMTPUser != "" && s.cfg.SMTPPass != "" || s.cfg.ResendKey != "", "detail": "OTP email"}
	status["push"] = M{"ok": s.fcm != nil, "detail": "Firebase push"}
	status["ocr"] = M{"ok": len(s.cfg.GeminiAPIKeys) > 0, "detail": fmt.Sprintf("%d Gemini key(s)", len(s.cfg.GeminiAPIKeys))}
	writeJSON(w, 200, M{"success": true, "status": status})
}

func (s *Server) superAdminCount(ctx context.Context) int {
	var n int
	_ = s.db.QueryRowContext(ctx, `SELECT count(*) FROM user_roles WHERE role='super_admin'`).Scan(&n)
	return n
}

// GET /api/admin/payments/{id}/receipt: the receipt file the applicant uploaded for an offline payment
func (s *Server) paymentReceipt(w http.ResponseWriter, r *http.Request) {
	m, _ := s.one(r.Context(), `SELECT offline_receipt_path AS p FROM payments WHERE id::text=$1`, r.PathValue("id"))
	p, _ := m["p"].(string)
	if p == "" {
		fail(w, 404, "No receipt uploaded")
		return
	}
	rel := filepath.Clean(p)
	if strings.Contains(rel, "..") {
		fail(w, 400, "Bad path")
		return
	}
	s.serveStored(w, r, rel)
}

// POST /api/admin/applicants/{id}/send-otp {channel: email|phone}
// Sends an OTP to the applicant's own email/phone so an admin can verify the contact together with them.
func (s *Server) adminSendContactOTP(w http.ResponseWriter, r *http.Request) {
	typ, contact, ok := s.contactFor(w, r)
	if !ok {
		return
	}
	body := M{"type": typ}
	body[typ] = contact // {"type":"email","email":...} or {"type":"phone","phone":...}
	rewriteBody(r, body)
	s.sendOTP(w, r)
}

// POST /api/admin/applicants/{id}/verify-otp {channel, otp}
func (s *Server) adminVerifyContactOTP(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Channel string `json:"channel"`
		Otp     string `json:"otp"`
	}
	if !decode(r, &in) {
		fail(w, 400, "Invalid body")
		return
	}
	rewriteBody(r, M{"channel": in.Channel})
	typ, contact, ok := s.contactFor(w, r)
	if !ok {
		return
	}
	body := M{"type": typ, "otp": in.Otp}
	body[typ] = contact
	rewriteBody(r, body)
	s.verifyOTP(w, r)
	s.audit(r.Context(), claimsOf(r).Sub, "verify_contact", "applicant", r.PathValue("id"), M{"channel": typ})
}

// contactFor reads {channel} from the body and returns ("email"|"phone", the applicant's value for it).
func (s *Server) contactFor(w http.ResponseWriter, r *http.Request) (string, string, bool) {
	var in struct {
		Channel string `json:"channel"`
	}
	if !decode(r, &in) || (in.Channel != "email" && in.Channel != "phone") {
		fail(w, 400, "channel must be email or phone")
		return "", "", false
	}
	m, _ := s.one(r.Context(), `SELECT email, phone FROM applicants WHERE id::text=$1`, r.PathValue("id"))
	if m == nil {
		fail(w, 404, "Applicant not found")
		return "", "", false
	}
	v, _ := m[in.Channel].(string)
	if v == "" {
		fail(w, 404, "Applicant has no "+in.Channel)
		return "", "", false
	}
	return in.Channel, v, true
}

// POST /api/admin/applicants/{id}/verify-contact {channel: email|phone, note}
// Manual verification for when OTP email/SMS cannot be delivered: an admin confirms the contact
// (for example by calling the applicant) and it is marked verified, so the application can move on to validation.
func (s *Server) adminVerifyContactManually(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Channel string `json:"channel"`
		Note    string `json:"note"`
	}
	if !decode(r, &in) || (in.Channel != "email" && in.Channel != "phone") {
		fail(w, 400, "channel must be email or phone")
		return
	}
	col := in.Channel + "_verified" // fixed set of two column names, never user input
	res, err := s.db.ExecContext(r.Context(), `UPDATE applicants SET `+col+`=true, updated_at=now() WHERE id::text=$1`, r.PathValue("id"))
	if err != nil {
		fail(w, 500, "DB error")
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		fail(w, 404, "Applicant not found")
		return
	}
	s.audit(r.Context(), claimsOf(r).Sub, "verify_contact_manual", "applicant", r.PathValue("id"),
		M{"channel": in.Channel, "note": strings.TrimSpace(in.Note)})
	what := "email"
	if in.Channel == "phone" {
		what = "phone number"
	}
	s.notify(r.Context(), r.PathValue("id"), "contact_verified", "Verified successfully",
		"Your "+what+" has been verified by the admin. Your documents are now under review.")
	writeJSON(w, 200, M{"success": true, "verified": true, "channel": in.Channel})
}