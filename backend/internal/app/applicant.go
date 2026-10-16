package app

import (
	"net/http"
	"os"
	"path/filepath"
)

// GET /api/me
func (s *Server) me(w http.ResponseWriter, r *http.Request) {
	ctx, c := r.Context(), claimsOf(r)
	app, err := s.one(ctx, `SELECT * FROM applicants WHERE user_id=$1`, c.Sub)
	if err != nil {
		fail(w, 500, "DB error")
		return
	}
	if app == nil {
		writeJSON(w, 200, M{"success": true, "applicant": nil, "roles": c.Roles})
		return
	}
	id := app["id"].(string)
	var unit M
	if uid, ok := app["stage_5_allotment_id"].(string); ok {
		unit, _ = s.one(ctx, `SELECT * FROM units WHERE id=$1`, uid)
	}
	project, _ := s.one(ctx, `SELECT project_name,rera_registration_no,developer_name,developer_address,possession_date,bank_name,bank_branch,bank_account_no,bank_ifsc,booking_amount,total_cost FROM project_settings LIMIT 1`)
	uploads, _ := s.many(ctx, `SELECT id,upload_type,file_name,file_path,uploaded_at FROM uploads WHERE applicant_id=$1 ORDER BY uploaded_at DESC`, id)
	payments, _ := s.many(ctx, `SELECT id,amount,payment_method,payment_status,payment_stage,receipt_number,payment_date,created_at FROM payments WHERE applicant_id=$1 ORDER BY created_at DESC`, id)
	loan, _ := s.one(ctx, `SELECT * FROM loan_details WHERE applicant_id=$1`, id)
	stage := app["registration_stage"].(string)
	writeJSON(w, 200, M{"success": true, "applicant": app, "unit": unit, "project": project, "uploads": uploads,
		"payments": payments, "loan": loan, "stageNumber": stageNum(stage), "stageLabel": stageNames[stage], "roles": c.Roles})
}

func (s *Server) myApplicant(r *http.Request) (M, bool) {
	app, err := s.one(r.Context(), `SELECT id, registration_stage FROM applicants WHERE user_id=$1`, claimsOf(r).Sub)
	return app, err == nil && app != nil
}

// POST /api/me/upload  multipart {type, file}
// agreement_signed (stage 5->6), bank_loan_receipt (8->9), mortgage_receipt (9->10)
func (s *Server) meUpload(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseMultipartForm(32 << 20); err != nil {
		fail(w, 400, "Invalid form")
		return
	}
	app, ok := s.myApplicant(r)
	if !ok {
		fail(w, 404, "Application not found")
		return
	}
	utype := r.FormValue("type")
	if len(r.MultipartForm.File["file"]) == 0 {
		fail(w, 400, "File is required")
		return
	}
	hdr := r.MultipartForm.File["file"][0]
	id, stage := app["id"].(string), app["registration_stage"].(string)

	var from, set string
	switch utype {
	case "agreement_signed":
		from = "stage_5_agreement"
		set = `registration_stage='stage_6_agreement_receipt', agreement_receipt_path=$2, agreement_signed_at=now(), stage_4_status='pending', stage_4_reason=NULL`
	case "bank_loan_receipt":
		from = "stage_8_bank_loan"
		set = `registration_stage='stage_9_mortgage', bank_loan_receipt_path=$2, bank_loan_form_uploaded_at=now()`
	case "mortgage_receipt":
		from = "stage_9_mortgage"
		set = `registration_stage='stage_10_completed', mortgage_receipt_path=$2, mortgage_deed_signed_at=now(), registration_completed_at=now()`
	default:
		fail(w, 400, "Unsupported upload type")
		return
	}
	if stage != from {
		fail(w, 409, "This upload is not allowed at your current stage")
		return
	}
	rel, err := s.saveFile(r.Context(), id, utype, hdr)
	if err != nil {
		fail(w, 400, err.Error())
		return
	}
	tx, _ := s.db.BeginTx(r.Context(), nil)
	defer tx.Rollback()
	_, e1 := tx.ExecContext(r.Context(), `INSERT INTO uploads(applicant_id,upload_type,file_name,file_path,file_size,uploaded_by) VALUES ($1,$2,$3,$4,$5,$6)`,
		id, utype, hdr.Filename, rel, hdr.Size, claimsOf(r).Sub)
	_, e2 := tx.ExecContext(r.Context(), `UPDATE applicants SET `+set+`, updated_at=now() WHERE id=$1`, id, rel)
	if e1 != nil || e2 != nil || tx.Commit() != nil {
		_ = os.Remove(filepath.Join(s.cfg.UploadDir, rel))
		fail(w, 500, "Failed to save upload")
		return
	}
	switch utype {
	case "agreement_signed":
		s.notify(r.Context(), id, "agreement_submitted", "Agreement received", "Your signed agreement is under review.")
	case "bank_loan_receipt":
		s.notify(r.Context(), id, "loan_receipt_submitted", "Loan receipt received", "Download the mortgage deed, sign it and upload the receipt.")
	case "mortgage_receipt":
		s.notify(r.Context(), id, "completed", "Registration complete", "Congratulations! Your registration is complete.")
	}
	writeJSON(w, 200, M{"success": true})
}

var bankDocCols = map[string]string{
	"upi_statement": "upi_statement_path", "itr_year1": "itr_year1_path", "itr_year2": "itr_year2_path",
	"itr_year3": "itr_year3_path", "bank_statement": "bank_statement_path",
}

// POST /api/me/bank-documents multipart {upi_statement, itr_year1..3, bank_statement}
func (s *Server) meBankDocs(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseMultipartForm(32 << 20); err != nil {
		fail(w, 400, "Invalid form")
		return
	}
	app, ok := s.myApplicant(r)
	if !ok {
		fail(w, 404, "Application not found")
		return
	}
	if st := app["registration_stage"].(string); st != "stage_7_bank_document" {
		fail(w, 409, "Bank documents can only be uploaded at the Bank Documents stage")
		return
	}
	id := app["id"].(string)
	_, _ = s.db.ExecContext(r.Context(), `INSERT INTO loan_details(applicant_id) VALUES ($1) ON CONFLICT DO NOTHING`, id)
	n := 0
	for field, col := range bankDocCols {
		files := r.MultipartForm.File[field]
		if len(files) == 0 {
			continue
		}
		rel, err := s.saveFile(r.Context(), id, field, files[0])
		if err != nil {
			fail(w, 400, err.Error())
			return
		}
		_, _ = s.db.ExecContext(r.Context(), `INSERT INTO uploads(applicant_id,upload_type,file_name,file_path,file_size,uploaded_by) VALUES ($1,$2,$3,$4,$5,$6)`,
			id, field, files[0].Filename, rel, files[0].Size, claimsOf(r).Sub)
		_, _ = s.db.ExecContext(r.Context(), `UPDATE loan_details SET `+col+`=$1, loan_status='pending', verification_notes=NULL, updated_at=now() WHERE applicant_id=$2`, rel, id)
		n++
	}
	if n == 0 {
		fail(w, 400, "No files received")
		return
	}
	loan, _ := s.one(r.Context(), `SELECT * FROM loan_details WHERE applicant_id=$1`, id)
	if all, _ := loan["upi_statement_path"].(string); all != "" && loan["itr_year1_path"] != nil && loan["itr_year2_path"] != nil &&
		loan["itr_year3_path"] != nil && loan["bank_statement_path"] != nil {
		s.notify(r.Context(), id, "bank_docs_submitted", "Documents submitted", "All bank documents received. They are under review.")
	}
	writeJSON(w, 200, M{"success": true, "loan": loan})
}

var docMinStage = map[string]int{"allotment": 5, "agreement": 5, "bank-loan": 8, "mortgage": 9}

// GET /api/me/documents/{kind}: data for generating the PDF in the app (allotment|agreement|bank-loan|mortgage)
func (s *Server) meDocument(w http.ResponseWriter, r *http.Request) {
	kind := r.PathValue("kind")
	min, ok := docMinStage[kind]
	if !ok {
		fail(w, 404, "Unknown document")
		return
	}
	app, err := s.one(r.Context(), `SELECT * FROM applicants WHERE user_id=$1`, claimsOf(r).Sub)
	if err != nil || app == nil {
		fail(w, 404, "Application not found")
		return
	}
	if stageNum(app["registration_stage"].(string)) < min {
		fail(w, 409, "Document not available yet")
		return
	}
	unit, _ := s.one(r.Context(), `SELECT * FROM units WHERE id=$1`, app["stage_5_allotment_id"])
	project, _ := s.one(r.Context(), `SELECT * FROM project_settings LIMIT 1`)
	loan, _ := s.one(r.Context(), `SELECT * FROM loan_details WHERE applicant_id=$1`, app["id"])
	writeJSON(w, 200, M{"success": true, "kind": kind, "applicant": app, "unit": unit, "project": project, "loan": loan})
}
