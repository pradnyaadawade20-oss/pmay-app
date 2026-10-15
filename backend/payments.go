package main

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"time"
)

func (s *Server) amountLimits(ctx context.Context) (min, max float64) {
	min, max = 25000, 2550000
	_ = s.db.QueryRowContext(ctx, `SELECT booking_amount,total_cost FROM project_settings LIMIT 1`).Scan(&min, &max)
	return
}

// completePayment marks a payment completed and moves the applicant 3 -> 4 (inside tx).
func completePayment(ctx context.Context, tx *sql.Tx, paymentID, verifier string) error {
	var appID, method string
	err := tx.QueryRowContext(ctx, `UPDATE payments SET payment_status='completed',
		receipt_number='RCP-'||to_char(current_date,'YYYYMMDD')||'-'||lpad(nextval('payment_receipt_seq')::text,5,'0'),
		payment_date=current_date, verified_by=NULLIF($2,'')::uuid, updated_at=now()
		WHERE id=$1 AND payment_status<>'completed' RETURNING applicant_id, payment_method`, paymentID, verifier).Scan(&appID, &method)
	if err == sql.ErrNoRows {
		return nil // already completed: idempotent
	}
	if err != nil {
		return err
	}
	_, err = tx.ExecContext(ctx, `UPDATE applicants SET registration_stage='stage_4_allotment', stage_3_payment_status='completed',
		stage_3_payment_method=$2, stage_3_completed_at=now(), updated_at=now()
		WHERE id=$1 AND registration_stage='stage_3_payment'`, appID, method)
	return err
}

// POST /api/payments/order {amount}
func (s *Server) payOrder(w http.ResponseWriter, r *http.Request) {
	var in struct{ Amount float64 }
	if !decode(r, &in) {
		fail(w, 400, "Invalid body")
		return
	}
	if s.cfg.RazorpayKeyID == "" || s.cfg.RazorpaySecret == "" {
		fail(w, 503, "Online payments are not configured")
		return
	}
	app, err := s.one(r.Context(), `SELECT id,unique_id,first_name,last_name,email,phone,registration_stage FROM applicants WHERE user_id=$1`, claimsOf(r).Sub)
	if err != nil || app == nil {
		fail(w, 404, "Application not found")
		return
	}
	if app["registration_stage"] != "stage_3_payment" {
		fail(w, 409, "Payment is not open for your application")
		return
	}
	min, max := s.amountLimits(r.Context())
	if in.Amount < min || in.Amount > max {
		fail(w, 400, fmt.Sprintf("Amount must be between %.0f and %.0f", min, max))
		return
	}
	body, _ := json.Marshal(M{"amount": int64(in.Amount * 100), "currency": "INR",
		"receipt": fmt.Sprintf("%s-booking-%d", app["unique_id"], time.Now().Unix()),
		"notes":   M{"applicant_id": app["id"], "unique_id": app["unique_id"]}})
	req, _ := http.NewRequest("POST", "https://api.razorpay.com/v1/orders", bytes.NewReader(body))
	req.SetBasicAuth(s.cfg.RazorpayKeyID, s.cfg.RazorpaySecret)
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil || resp.StatusCode >= 300 {
		fail(w, 502, "Failed to create Razorpay order")
		return
	}
	defer resp.Body.Close()
	var order struct{ ID string }
	_ = json.NewDecoder(resp.Body).Decode(&order)
	var payID string
	if err := s.db.QueryRowContext(r.Context(), `INSERT INTO payments(applicant_id,amount,payment_method,payment_stage,razorpay_order_id)
		VALUES ($1,$2,'online','booking',$3) RETURNING id`, app["id"], in.Amount, order.ID).Scan(&payID); err != nil {
		fail(w, 500, "Failed to record payment")
		return
	}
	writeJSON(w, 200, M{"success": true, "orderId": order.ID, "paymentId": payID, "amount": in.Amount, "currency": "INR",
		"keyId": s.cfg.RazorpayKeyID, "name": fmt.Sprintf("%v %v", app["first_name"], app["last_name"]),
		"email": app["email"], "phone": app["phone"]})
}

// POST /api/payments/verify {razorpay_order_id, razorpay_payment_id, razorpay_signature}
func (s *Server) payVerify(w http.ResponseWriter, r *http.Request) {
	var in struct {
		OrderID   string `json:"razorpay_order_id"`
		PaymentID string `json:"razorpay_payment_id"`
		Signature string `json:"razorpay_signature"`
	}
	if !decode(r, &in) || in.OrderID == "" {
		fail(w, 400, "Invalid body")
		return
	}
	mac := hmac.New(sha256.New, []byte(s.cfg.RazorpaySecret))
	mac.Write([]byte(in.OrderID + "|" + in.PaymentID))
	if !hmac.Equal([]byte(hex.EncodeToString(mac.Sum(nil))), []byte(in.Signature)) {
		fail(w, 400, "Invalid payment signature")
		return
	}
	var payID string
	err := s.db.QueryRowContext(r.Context(), `SELECT p.id FROM payments p JOIN applicants a ON a.id=p.applicant_id
		WHERE p.razorpay_order_id=$1 AND a.user_id=$2`, in.OrderID, claimsOf(r).Sub).Scan(&payID)
	if err != nil {
		fail(w, 404, "Payment not found")
		return
	}
	tx, _ := s.db.BeginTx(r.Context(), nil)
	defer tx.Rollback()
	_, _ = tx.ExecContext(r.Context(), `UPDATE payments SET razorpay_payment_id=$2, razorpay_signature=$3 WHERE id=$1`, payID, in.PaymentID, in.Signature)
	if err := completePayment(r.Context(), tx, payID, ""); err != nil || tx.Commit() != nil {
		fail(w, 500, "Failed to complete payment")
		return
	}
	s.notifyPayment(r.Context(), payID, "payment_accepted", "Payment received", "Your payment is confirmed. A unit will be allotted to you soon.")
	writeJSON(w, 200, M{"success": true})
}

// POST /api/payments/offline multipart {amount, receipt}  -> pending until finance/admin approves
func (s *Server) payOffline(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseMultipartForm(16 << 20); err != nil {
		fail(w, 400, "Invalid form")
		return
	}
	app, err := s.one(r.Context(), `SELECT id,registration_stage FROM applicants WHERE user_id=$1`, claimsOf(r).Sub)
	if err != nil || app == nil {
		fail(w, 404, "Application not found")
		return
	}
	if app["registration_stage"] != "stage_3_payment" {
		fail(w, 409, "Payment is not open for your application")
		return
	}
	amount, _ := strconv.ParseFloat(r.FormValue("amount"), 64)
	min, max := s.amountLimits(r.Context())
	if amount < min || amount > max {
		fail(w, 400, fmt.Sprintf("Amount must be between %.0f and %.0f", min, max))
		return
	}
	files := r.MultipartForm.File["receipt"]
	if len(files) == 0 {
		fail(w, 400, "Receipt file is required")
		return
	}
	id := app["id"].(string)
	rel, err := s.saveFile(r.Context(), id, "offline_receipt", files[0])
	if err != nil {
		fail(w, 400, err.Error())
		return
	}
	_, err = s.db.ExecContext(r.Context(), `INSERT INTO payments(applicant_id,amount,payment_method,payment_stage,offline_receipt_path,payment_date)
		VALUES ($1,$2,'offline','booking',$3,current_date)`, id, amount, rel)
	if err != nil {
		fail(w, 500, "Failed to record payment")
		return
	}
	writeJSON(w, 201, M{"success": true, "message": "Payment submitted for verification"})
}