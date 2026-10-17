package app

import (
	"database/sql"
	"fmt"
	"net/http"
	"strconv"
)

func (s *Server) adminStats(w http.ResponseWriter, r *http.Request) {
	byStage, _ := s.many(r.Context(), `SELECT registration_stage AS stage, count(*) AS count FROM applicants GROUP BY 1 ORDER BY 1`)
	var pendingVal, pendingPay, pendingAgr, pendingBank, today int
	s.db.QueryRowContext(r.Context(), `SELECT
		(SELECT count(*) FROM applicants WHERE registration_stage='stage_1_registered' AND stage_2_status='pending'),
		(SELECT count(*) FROM payments WHERE payment_status='pending' AND payment_method='offline'),
		(SELECT count(*) FROM applicants WHERE registration_stage='stage_6_agreement_receipt'),
		(SELECT count(*) FROM loan_details l JOIN applicants a ON a.id=l.applicant_id WHERE a.registration_stage='stage_7_bank_document' AND l.loan_status='pending'
		   AND l.upi_statement_path IS NOT NULL AND l.itr_year1_path IS NOT NULL AND l.itr_year2_path IS NOT NULL AND l.itr_year3_path IS NOT NULL AND l.bank_statement_path IS NOT NULL),
		COALESCE((SELECT count FROM stage_2_daily_counter WHERE date=current_date),0)`).Scan(&pendingVal, &pendingPay, &pendingAgr, &pendingBank, &today)
	writeJSON(w, 200, M{"success": true, "byStage": byStage, "pendingValidation": pendingVal, "pendingOfflinePayments": pendingPay,
		"pendingAgreementReceipts": pendingAgr, "pendingBankReviews": pendingBank, "acceptedToday": today, "dailyLimit": 1000})
}

// GET /api/admin/applicants?stage=&status=&q=&limit=&offset=
func (s *Server) adminApplicants(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	limit, _ := strconv.Atoi(q.Get("limit"))
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	off, _ := strconv.Atoi(q.Get("offset"))
	rows, err := s.many(r.Context(), `SELECT id,unique_id,first_name,last_name,email,phone,email_verified,phone_verified,registration_stage,
		stage_2_status,stage_4_status,handling_admin_id,created_at FROM applicants
		WHERE ($1='' OR registration_stage=$1) AND ($2='' OR stage_2_status=$2)
		AND ($3='' OR first_name||' '||last_name ILIKE '%'||$3||'%' OR unique_id ILIKE '%'||$3||'%' OR phone LIKE '%'||$3||'%' OR pan_number ILIKE $3)
		ORDER BY created_at DESC LIMIT $4 OFFSET $5`, q.Get("stage"), q.Get("status"), q.Get("q"), limit, off)
	if err != nil {
		fail(w, 500, "DB error")
		return
	}
	writeJSON(w, 200, M{"success": true, "applicants": rows})
}

func (s *Server) adminApplicant(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	app, err := s.one(r.Context(), `SELECT * FROM applicants WHERE id=$1`, id)
	if err != nil || app == nil {
		fail(w, 404, "Applicant not found")
		return
	}
	uploads, _ := s.many(r.Context(), `SELECT id,upload_type,file_name,file_path,uploaded_at FROM uploads WHERE applicant_id=$1 ORDER BY uploaded_at`, id)
	payments, _ := s.many(r.Context(), `SELECT * FROM payments WHERE applicant_id=$1 ORDER BY created_at DESC`, id)
	loan, _ := s.one(r.Context(), `SELECT * FROM loan_details WHERE applicant_id=$1`, id)
	unit, _ := s.one(r.Context(), `SELECT * FROM units WHERE allocated_to=$1`, id)
	project, _ := s.one(r.Context(), `SELECT bank_name, bank_branch, project_name FROM project_settings LIMIT 1`)
	writeJSON(w, 200, M{"success": true, "applicant": app, "uploads": uploads, "payments": payments, "loan": loan, "unit": unit, "project": project})
}

type reviewIn struct {
	Action string `json:"action"` // accept|reject
	Reason string `json:"reason"`
}

// lockApplicant loads applicant row FOR UPDATE inside tx.
func lockApplicant(r *http.Request, tx *sql.Tx, id string) (stage, st2 string, emailV, phoneV bool, err error) {
	err = tx.QueryRowContext(r.Context(), `SELECT registration_stage, stage_2_status, email_verified, phone_verified FROM applicants WHERE id=$1 FOR UPDATE`, id).Scan(&stage, &st2, &emailV, &phoneV)
	return
}

// POST /api/admin/applicants/{id}/validation  (stage 1 -> 3)  daily cap 1000 accepted/day
func (s *Server) adminValidation(w http.ResponseWriter, r *http.Request) {
	var in reviewIn
	if !decode(r, &in) || (in.Action != "accept" && in.Action != "reject") {
		fail(w, 400, "action must be accept or reject")
		return
	}
	id, uid := r.PathValue("id"), claimsOf(r).Sub
	tx, _ := s.db.BeginTx(r.Context(), nil)
	defer tx.Rollback()
	stage, _, ev, pv, err := lockApplicant(r, tx, id)
	if err != nil {
		fail(w, 404, "Applicant not found")
		return
	}
	if stage != "stage_1_registered" {
		fail(w, 409, "Applicant is not awaiting validation")
		return
	}
	if in.Action == "reject" {
		_, _ = tx.ExecContext(r.Context(), `UPDATE applicants SET stage_2_status='rejected', stage_2_reason=$2, stage_2_verified_by=$3, stage_2_verified_at=now() WHERE id=$1`, id, in.Reason, uid)
	} else {
		if s.cfg.RequireContactVerified && !ev && !pv {
			fail(w, 409, "Applicant has not verified email or phone yet")
			return
		}
		_, _ = tx.ExecContext(r.Context(), `INSERT INTO stage_2_daily_counter(date,count) VALUES (current_date,0) ON CONFLICT DO NOTHING`)
		res, _ := tx.ExecContext(r.Context(), `UPDATE stage_2_daily_counter SET count=count+1 WHERE date=current_date AND count<1000`)
		if n, _ := res.RowsAffected(); n == 0 {
			fail(w, 429, "Daily limit of 1000 validations reached")
			return
		}
		_, _ = tx.ExecContext(r.Context(), `UPDATE applicants SET stage_2_status='accepted', stage_2_reason=NULL, registration_stage='stage_3_payment',
			stage_3_payment_status='pending', stage_2_verified_by=$2, stage_2_verified_at=now(), updated_at=now() WHERE id=$1`, id, uid)
	}
	if tx.Commit() != nil {
		fail(w, 500, "Commit failed")
		return
	}
	s.audit(r.Context(), uid, "validation_"+in.Action, "applicant", id, M{"reason": in.Reason})
	if in.Action == "accept" {
		s.notify(r.Context(), id, "validation_accepted", "Documents verified", "Your documents are verified. Pay the booking amount to proceed.")
	} else {
		s.notify(r.Context(), id, "validation_rejected", "Application rejected", orDefault(in.Reason, "Please contact support for details."))
	}
	writeJSON(w, 200, M{"success": true})
}

// POST /api/admin/payments/{id}/review {action: accept|reject}  (offline payments)
func (s *Server) adminPaymentReview(w http.ResponseWriter, r *http.Request) {
	var in reviewIn
	if !decode(r, &in) || (in.Action != "accept" && in.Action != "reject") {
		fail(w, 400, "action must be accept or reject")
		return
	}
	id, uid := r.PathValue("id"), claimsOf(r).Sub
	tx, _ := s.db.BeginTx(r.Context(), nil)
	defer tx.Rollback()
	var st string
	if err := tx.QueryRowContext(r.Context(), `SELECT payment_status FROM payments WHERE id=$1 AND payment_method='offline' FOR UPDATE`, id).Scan(&st); err != nil {
		fail(w, 404, "Offline payment not found")
		return
	}
	if st != "pending" {
		fail(w, 409, "Payment already reviewed")
		return
	}
	var err error
	if in.Action == "accept" {
		err = completePayment(r.Context(), tx, id, uid)
	} else {
		_, err = tx.ExecContext(r.Context(), `UPDATE payments SET payment_status='failed', verified_by=$2, updated_at=now() WHERE id=$1`, id, uid)
	}
	if err != nil || tx.Commit() != nil {
		fail(w, 500, "Failed to update payment")
		return
	}
	s.audit(r.Context(), uid, "payment_"+in.Action, "payment", id, nil)
	if in.Action == "accept" {
		s.notifyPayment(r.Context(), id, "payment_accepted", "Payment received", "Your payment is confirmed. A unit will be allotted to you soon.")
	} else {
		s.notifyPayment(r.Context(), id, "payment_rejected", "Payment not verified", "We could not verify your payment receipt. Please submit it again or contact support.")
	}
	writeJSON(w, 200, M{"success": true})
}

func (s *Server) adminUnits(w http.ResponseWriter, r *http.Request) {
	rows, err := s.many(r.Context(), `SELECT u.*, a.unique_id AS allotted_unique_id, a.first_name||' '||a.last_name AS allotted_name
		FROM units u LEFT JOIN applicants a ON a.id=u.allocated_to WHERE ($1='' OR u.status=$1) ORDER BY u.floor, u.unit_number`, r.URL.Query().Get("status"))
	if err != nil {
		fail(w, 500, "DB error")
		return
	}
	writeJSON(w, 200, M{"success": true, "units": rows})
}

// POST /api/admin/applicants/{id}/allot {unitId}  (stage 4 -> 5)
func (s *Server) adminAllot(w http.ResponseWriter, r *http.Request) {
	var in struct {
		UnitID string `json:"unitId"`
	}
	if !decode(r, &in) || in.UnitID == "" {
		fail(w, 400, "unitId required")
		return
	}
	id, uid := r.PathValue("id"), claimsOf(r).Sub
	tx, _ := s.db.BeginTx(r.Context(), nil)
	defer tx.Rollback()
	stage, _, _, _, err := lockApplicant(r, tx, id)
	if err != nil {
		fail(w, 404, "Applicant not found")
		return
	}
	if stage != "stage_4_allotment" {
		fail(w, 409, "Applicant is not awaiting allotment")
		return
	}
	res, _ := tx.ExecContext(r.Context(), `UPDATE units SET status='allotted', allocated_to=$2, allocated_at=now() WHERE id=$1 AND status='available'`, in.UnitID, id)
	if n, _ := res.RowsAffected(); n == 0 {
		fail(w, 409, "Unit is not available")
		return
	}
	_, _ = tx.ExecContext(r.Context(), `UPDATE applicants SET registration_stage='stage_5_agreement', stage_5_allotment_id=$2, allotment_date=now(), updated_at=now() WHERE id=$1`, id, in.UnitID)
	if tx.Commit() != nil {
		fail(w, 500, "Commit failed")
		return
	}
	s.audit(r.Context(), uid, "allot_unit", "applicant", id, M{"unitId": in.UnitID})
	s.notify(r.Context(), id, "unit_allotted", "Unit allotted", "A unit has been allotted to you. Download, sign and upload the agreement.")
	writeJSON(w, 200, M{"success": true})
}

// POST /api/admin/applicants/{id}/agreement-review  accept: 6 -> 7 ; reject: back to 5 so applicant can re-upload
func (s *Server) adminAgreementReview(w http.ResponseWriter, r *http.Request) {
	var in reviewIn
	if !decode(r, &in) || (in.Action != "accept" && in.Action != "reject") {
		fail(w, 400, "action must be accept or reject")
		return
	}
	q := `UPDATE applicants SET stage_4_status='accepted', registration_stage='stage_7_bank_document', updated_at=now() WHERE id=$1 AND registration_stage='stage_6_agreement_receipt'`
	args := []any{r.PathValue("id")}
	if in.Action == "reject" {
		q = `UPDATE applicants SET stage_4_status='rejected', stage_4_reason=$2, registration_stage='stage_5_agreement', updated_at=now() WHERE id=$1 AND registration_stage='stage_6_agreement_receipt'`
		args = append(args, in.Reason)
	}
	res, err := s.db.ExecContext(r.Context(), q, args...)
	if n, _ := res.RowsAffected(); err != nil || n == 0 {
		fail(w, 409, "Applicant is not awaiting agreement review")
		return
	}
	s.audit(r.Context(), claimsOf(r).Sub, "agreement_"+in.Action, "applicant", r.PathValue("id"), M{"reason": in.Reason})
	if in.Action == "accept" {
		s.notify(r.Context(), r.PathValue("id"), "agreement_accepted", "Agreement approved", "Your signed agreement is approved. Upload your bank documents next.")
	} else {
		s.notify(r.Context(), r.PathValue("id"), "agreement_rejected", "Agreement rejected", orDefault(in.Reason, "Please re-upload a clear signed copy."))
	}
	writeJSON(w, 200, M{"success": true})
}

// POST /api/admin/applicants/{id}/bank-review  approve: 7 -> 8 (needs all 5 docs)
func (s *Server) adminBankReview(w http.ResponseWriter, r *http.Request) {
	var in reviewIn
	if !decode(r, &in) || (in.Action != "accept" && in.Action != "reject") {
		fail(w, 400, "action must be accept or reject")
		return
	}
	id, uid := r.PathValue("id"), claimsOf(r).Sub
	tx, _ := s.db.BeginTx(r.Context(), nil)
	defer tx.Rollback()
	var all bool
	err := tx.QueryRowContext(r.Context(), `SELECT (upi_statement_path IS NOT NULL AND itr_year1_path IS NOT NULL AND itr_year2_path IS NOT NULL
		AND itr_year3_path IS NOT NULL AND bank_statement_path IS NOT NULL) FROM loan_details WHERE applicant_id=$1 FOR UPDATE`, id).Scan(&all)
	if err != nil {
		fail(w, 404, "No bank documents submitted")
		return
	}
	if in.Action == "accept" {
		if !all {
			fail(w, 409, "All 5 documents are required before approval")
			return
		}
		_, _ = tx.ExecContext(r.Context(), `UPDATE loan_details SET loan_status='approved', verification_notes=$2, verified_by=$3, verified_at=now() WHERE applicant_id=$1`, id, in.Reason, uid)
		res, _ := tx.ExecContext(r.Context(), `UPDATE applicants SET registration_stage='stage_8_bank_loan', updated_at=now() WHERE id=$1 AND registration_stage='stage_7_bank_document'`, id)
		if n, _ := res.RowsAffected(); n == 0 {
			fail(w, 409, "Applicant is not at the bank document stage")
			return
		}
	} else {
		_, _ = tx.ExecContext(r.Context(), `UPDATE loan_details SET loan_status='rejected', verification_notes=$2, verified_by=$3, verified_at=now() WHERE applicant_id=$1`, id, in.Reason, uid)
	}
	if tx.Commit() != nil {
		fail(w, 500, "Commit failed")
		return
	}
	s.audit(r.Context(), uid, "bank_"+in.Action, "applicant", id, M{"notes": in.Reason})
	if in.Action == "accept" {
		s.notify(r.Context(), id, "bank_docs_accepted", "Bank documents approved", "Download the loan form, submit it at your bank and upload the receipt.")
	} else {
		s.notify(r.Context(), id, "bank_docs_rejected", "Bank documents rejected", orDefault(in.Reason, "Please re-upload the required documents."))
	}
	writeJSON(w, 200, M{"success": true})
}

// POST /api/admin/applicants/{id}/stage {stage}  (super_admin manual override)
func (s *Server) adminSetStage(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Stage string `json:"stage"`
	}
	if !decode(r, &in) || stageNames[in.Stage] == nil {
		fail(w, 400, "Invalid stage")
		return
	}
	res, err := s.db.ExecContext(r.Context(), `UPDATE applicants SET registration_stage=$2, updated_at=now() WHERE id=$1`, r.PathValue("id"), in.Stage)
	if n, _ := res.RowsAffected(); err != nil || n == 0 {
		fail(w, 404, "Applicant not found")
		return
	}
	s.audit(r.Context(), claimsOf(r).Sub, "set_stage", "applicant", r.PathValue("id"), M{"stage": in.Stage})
	s.notify(r.Context(), r.PathValue("id"), "stage_changed", "Application updated", fmt.Sprintf("Your application is now at: %v.", stageNames[in.Stage]))
	writeJSON(w, 200, M{"success": true})
}

// POST /api/admin/users {email,password,role,displayName}
func (s *Server) adminCreateUser(w http.ResponseWriter, r *http.Request) {
	var in struct{ Email, Password, Role, DisplayName string }
	if !decode(r, &in) || !reEmail.MatchString(normEmail(in.Email)) || len(in.Password) < 8 {
		fail(w, 400, "Valid email and 8+ char password required")
		return
	}
	valid := map[string]bool{"super_admin": true, "admin": true, "finance": true, "allotment_manager": true, "auditor": true}
	if !valid[in.Role] {
		fail(w, 400, "Invalid role")
		return
	}
	var id string
	if err := s.db.QueryRowContext(r.Context(), `INSERT INTO users(email,password_hash) VALUES ($1,$2) RETURNING id`, normEmail(in.Email), hashPassword(in.Password)).Scan(&id); err != nil {
		fail(w, 409, "User already exists")
		return
	}
	_, _ = s.db.ExecContext(r.Context(), `INSERT INTO user_roles(user_id,role,display_name) VALUES ($1,$2,$3)`, id, in.Role, in.DisplayName)
	writeJSON(w, 201, M{"success": true, "userId": id, "note": fmt.Sprintf("created %s", in.Role)})
}
