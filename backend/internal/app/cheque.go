package app

import (
	"fmt"
	"net/http"
	"strconv"
	"strings"
)

// POST /api/admin/applicants/{id}/cheque  multipart: file (photo/PDF of the cheque), amount,
// optional cheque_number, bank, note.
// Records the booking payment an admin received by cheque: the photo is stored as the payment proof
// (kept for future reference, shown in Payment Management), the payment is marked completed and the
// applicant moves on to allotment.
func (s *Server) adminRecordCheque(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseMultipartForm(16 << 20); err != nil {
		fail(w, 400, "Invalid form")
		return
	}
	id, uid := r.PathValue("id"), claimsOf(r).Sub
	files := r.MultipartForm.File["file"]
	if len(files) == 0 {
		fail(w, 400, "A photo of the cheque is required")
		return
	}
	amount, _ := strconv.ParseFloat(strings.TrimSpace(r.FormValue("amount")), 64)
	min, max := s.amountLimits(r.Context())
	if amount < min || amount > max {
		fail(w, 400, fmt.Sprintf("Amount must be between %.0f and %.0f", min, max))
		return
	}
	chequeNo := clip(r.FormValue("cheque_number"), 40)
	bank := clip(r.FormValue("bank"), 80)
	note := clip(r.FormValue("note"), 300)

	var stage string
	if err := s.db.QueryRowContext(r.Context(), `SELECT registration_stage FROM applicants WHERE id::text=$1`, id).Scan(&stage); err != nil {
		fail(w, 404, "Applicant not found")
		return
	}
	if stage != "stage_3_payment" {
		fail(w, 409, "A payment can only be recorded while the applicant is at the payment stage")
		return
	}
	rel, err := s.saveFile(r.Context(), id, "cheque_photo", files[0])
	if err != nil {
		fail(w, 400, err.Error())
		return
	}
	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		s.dropBlobs(r.Context(), rel)
		fail(w, 500, "DB error")
		return
	}
	defer tx.Rollback()
	var pid string
	if err := tx.QueryRowContext(r.Context(), `INSERT INTO payments(applicant_id,amount,payment_method,payment_status,payment_stage,offline_receipt_path,
		payment_date,payment_mode,cheque_number,cheque_bank,note,recorded_by)
		VALUES ($1::uuid,$2,'offline','pending','booking',$3,current_date,'cheque',NULLIF($4,''),NULLIF($5,''),NULLIF($6,''),$7::uuid) RETURNING id`,
		id, amount, rel, chequeNo, bank, note, uid).Scan(&pid); err != nil {
		s.dropBlobs(r.Context(), rel)
		fail(w, 500, "Could not record the payment")
		return
	}
	if err := completePayment(r.Context(), tx, pid, uid); err != nil || tx.Commit() != nil {
		s.dropBlobs(r.Context(), rel)
		fail(w, 500, "Could not record the payment")
		return
	}
	s.audit(r.Context(), uid, "cheque_payment", "payment", pid, M{"amount": amount, "cheque_number": chequeNo})
	s.notify(r.Context(), id, "payment_accepted", "Payment received", "Your payment is confirmed. A unit will be allotted to you soon.")
	writeJSON(w, 201, M{"success": true, "paymentId": pid})
}

func clip(s string, n int) string {
	s = strings.TrimSpace(s)
	if len(s) > n {
		s = s[:n]
	}
	return s
}
