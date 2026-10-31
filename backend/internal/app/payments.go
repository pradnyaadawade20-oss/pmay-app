package app

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"math"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

func (s *Server) amountLimits(ctx context.Context) (min, max float64) {
	min, max = 25000, 2550000
	_ = s.db.QueryRowContext(ctx, `SELECT booking_amount,total_cost FROM project_settings LIMIT 1`).Scan(&min, &max)
	return
}

// completePaymentOnce marks a payment completed and moves the applicant 3 -> 4 (inside tx).
// done is true only for the call that actually completed it (so webhook + verify don't notify twice).
func completePaymentOnce(ctx context.Context, tx *sql.Tx, paymentID, verifier string) (done bool, err error) {
	var appID, method string
	err = tx.QueryRowContext(ctx, `UPDATE payments SET payment_status='completed',
		receipt_number='RCP-'||to_char(current_date,'YYYYMMDD')||'-'||lpad(nextval('payment_receipt_seq')::text,5,'0'),
		payment_date=current_date, verified_by=NULLIF($2,'')::uuid, updated_at=now()
		WHERE id=$1 AND payment_status<>'completed' RETURNING applicant_id, payment_method`, paymentID, verifier).Scan(&appID, &method)
	if err == sql.ErrNoRows {
		return false, nil // already completed: idempotent
	}
	if err != nil {
		return false, err
	}
	_, err = tx.ExecContext(ctx, `UPDATE applicants SET registration_stage='stage_4_allotment', stage_3_payment_status='completed',
		stage_3_payment_method=$2, stage_3_completed_at=now(), updated_at=now()
		WHERE id=$1 AND registration_stage='stage_3_payment'`, appID, method)
	return err == nil, err
}

func completePayment(ctx context.Context, tx *sql.Tx, paymentID, verifier string) error {
	_, err := completePaymentOnce(ctx, tx, paymentID, verifier)
	return err
}

// ===================== Cashfree Payment Gateway =====================
// Flow (same for the applicant app and the admin "Collect Payment" screen):
//  1. client -> our API: create order      -> we create a Cashfree order, store a pending payment, return payment_session_id
//  2. client opens Cashfree checkout (mobile SDK / web JS SDK) with that session id
//  3. client -> our API: verify {order_id} -> WE ask Cashfree for the real order status; only "PAID" completes the payment
//  4. Cashfree webhook (optional) does the same as step 3 in case the client never came back.
// The client's word is never trusted: status always comes from Cashfree's server API.

const cfAPIVersion = "2023-08-01"

var (
	cfHTTP           = &http.Client{Timeout: 20 * time.Second}
	errPaymentLookup = errors.New("payment not found")
)

func (s *Server) cfEnabled() bool { return s.cfg.CashfreeAppID != "" && s.cfg.CashfreeSecret != "" }

func (s *Server) cfProduction() bool { return s.cfg.CashfreeEnv == "production" }

func (s *Server) cfEnvName() string {
	if s.cfProduction() {
		return "production"
	}
	return "sandbox"
}

func (s *Server) cfBase() string {
	if s.cfProduction() {
		return "https://api.cashfree.com/pg"
	}
	return "https://sandbox.cashfree.com/pg"
}

// cfCall performs one Cashfree PG API request. in/out may be nil.
func (s *Server) cfCall(ctx context.Context, method, path string, in, out any) error {
	var body io.Reader
	if in != nil {
		b, _ := json.Marshal(in)
		body = bytes.NewReader(b)
	}
	req, err := http.NewRequestWithContext(ctx, method, s.cfBase()+path, body)
	if err != nil {
		return err
	}
	req.Header.Set("x-client-id", s.cfg.CashfreeAppID)
	req.Header.Set("x-client-secret", s.cfg.CashfreeSecret)
	req.Header.Set("x-api-version", cfAPIVersion)
	req.Header.Set("Content-Type", "application/json")
	resp, err := cfHTTP.Do(req)
	if err != nil {
		log.Printf("cashfree %s %s: %v", method, path, err)
		return errors.New("could not reach Cashfree")
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if resp.StatusCode >= 300 {
		var e struct {
			Message string `json:"message"`
		}
		_ = json.Unmarshal(data, &e)
		log.Printf("cashfree %s %s -> %d: %s", method, path, resp.StatusCode, string(data))
		return errors.New(orDefault(e.Message, resp.Status))
	}
	if out == nil {
		return nil
	}
	return json.Unmarshal(data, out)
}

type cfOrder struct {
	OrderID          string  `json:"order_id"`
	OrderStatus      string  `json:"order_status"`
	OrderAmount      float64 `json:"order_amount"`
	PaymentSessionID string  `json:"payment_session_id"`
}

type cfPayment struct {
	CFPaymentID   json.RawMessage `json:"cf_payment_id"`
	PaymentStatus string          `json:"payment_status"`
}

func round2(v float64) float64 { return math.Round(v*100) / 100 }

// last10 returns the last 10 digits of a phone number (Cashfree wants a plain 10 digit Indian mobile).
func last10(p string) string {
	d := reDigits.ReplaceAllString(p, "")
	if len(d) > 10 {
		d = d[len(d)-10:]
	}
	return d
}

// cfCreateOrder creates the Cashfree order and the pending payment row. tag: "bk" (applicant) | "adm" (admin collected).
// Returns the JSON the client needs to open the checkout.
func (s *Server) cfCreateOrder(ctx context.Context, app M, amount float64, tag string) (M, int, error) {
	amount = round2(amount)
	orderID := fmt.Sprintf("%v-%s-%d", app["unique_id"], tag, time.Now().UnixMilli())
	meta := M{}
	if strings.HasPrefix(s.cfg.PublicAPIURL, "https://") {
		meta["notify_url"] = s.cfg.PublicAPIURL + "/api/payments/cashfree-webhook"
	}
	in := M{
		"order_id":       orderID,
		"order_amount":   amount,
		"order_currency": "INR",
		"order_note":     "Booking amount - " + fmt.Sprint(app["unique_id"]),
		"customer_details": M{
			"customer_id":    strings.ReplaceAll(fmt.Sprint(app["id"]), "-", ""),
			"customer_name":  strings.TrimSpace(fmt.Sprintf("%v %v", app["first_name"], app["last_name"])),
			"customer_email": fmt.Sprint(app["email"]),
			"customer_phone": last10(fmt.Sprint(app["phone"])),
		},
	}
	if len(meta) > 0 {
		in["order_meta"] = meta
	}
	var o cfOrder
	if err := s.cfCall(ctx, "POST", "/orders", in, &o); err != nil {
		return nil, 502, fmt.Errorf("Failed to create Cashfree order: %v", err)
	}
	if o.PaymentSessionID == "" {
		return nil, 502, errors.New("Cashfree did not return a payment session")
	}
	var payID string
	if err := s.db.QueryRowContext(ctx, `INSERT INTO payments(applicant_id,amount,payment_method,payment_stage,gateway,gateway_order_id)
		VALUES ($1,$2,'online','booking','cashfree',$3) RETURNING id`, app["id"], amount, orderID).Scan(&payID); err != nil {
		return nil, 500, errors.New("Failed to record payment")
	}
	return M{"success": true, "orderId": orderID, "paymentSessionId": o.PaymentSessionID, "paymentId": payID,
		"amount": amount, "currency": "INR", "environment": s.cfEnvName(),
		"name": fmt.Sprintf("%v %v", app["first_name"], app["last_name"]), "email": app["email"], "phone": app["phone"]}, 200, nil
}

type cfSettleResult struct {
	Status string // paid | pending | failed
	PayID  string
	Done   bool // true if this call is the one that completed the payment
}

// settleCashfreeOrder asks Cashfree for the real status of the order and completes our payment when it is PAID.
func (s *Server) settleCashfreeOrder(ctx context.Context, orderID, verifier string) (cfSettleResult, error) {
	var payID, status string
	var amount float64
	err := s.db.QueryRowContext(ctx, `SELECT id, amount::float8, payment_status FROM payments
		WHERE gateway='cashfree' AND gateway_order_id=$1`, orderID).Scan(&payID, &amount, &status)
	if err != nil {
		return cfSettleResult{}, errPaymentLookup
	}
	res := cfSettleResult{PayID: payID}
	if status == "completed" {
		res.Status = "paid"
		return res, nil
	}
	var o cfOrder
	if err := s.cfCall(ctx, "GET", "/orders/"+url.PathEscape(orderID), nil, &o); err != nil {
		return res, err
	}
	switch strings.ToUpper(o.OrderStatus) {
	case "PAID":
	case "EXPIRED", "TERMINATED", "TERMINATION_REQUESTED":
		_, _ = s.db.ExecContext(ctx, `UPDATE payments SET payment_status='failed', updated_at=now() WHERE id=$1 AND payment_status='pending'`, payID)
		res.Status = "failed"
		return res, nil
	default: // ACTIVE: customer has not paid (yet) - they may still retry
		res.Status = "pending"
		return res, nil
	}
	if math.Abs(o.OrderAmount-amount) > 0.01 {
		log.Printf("cashfree: amount mismatch for %s: cashfree=%.2f ours=%.2f", orderID, o.OrderAmount, amount)
		return res, errors.New("payment amount mismatch")
	}
	txn := ""
	var list []cfPayment
	if s.cfCall(ctx, "GET", "/orders/"+url.PathEscape(orderID)+"/payments", nil, &list) == nil {
		for _, p := range list {
			if strings.EqualFold(p.PaymentStatus, "SUCCESS") {
				txn = strings.Trim(string(p.CFPaymentID), `"`)
				break
			}
		}
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return res, err
	}
	defer tx.Rollback()
	if _, err := tx.ExecContext(ctx, `UPDATE payments SET gateway_payment_id=NULLIF($2,'') WHERE id=$1`, payID, txn); err != nil {
		return res, err
	}
	done, err := completePaymentOnce(ctx, tx, payID, verifier)
	if err != nil {
		return res, err
	}
	if err := tx.Commit(); err != nil {
		return res, err
	}
	res.Status, res.Done = "paid", done
	return res, nil
}

const msgPaymentAccepted = "Your payment is confirmed. A unit will be allotted to you soon."

// POST /api/payments/order {amount}
func (s *Server) payOrder(w http.ResponseWriter, r *http.Request) {
	var in struct{ Amount float64 }
	if !decode(r, &in) {
		fail(w, 400, "Invalid body")
		return
	}
	if !s.cfEnabled() {
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
	out, code, err := s.cfCreateOrder(r.Context(), app, in.Amount, "bk")
	if err != nil {
		fail(w, code, err.Error())
		return
	}
	writeJSON(w, 200, out)
}

// POST /api/payments/verify {order_id} -> {success, status: paid|pending|failed}
func (s *Server) payVerify(w http.ResponseWriter, r *http.Request) {
	var in struct {
		OrderID string `json:"order_id"`
	}
	if !decode(r, &in) || in.OrderID == "" {
		fail(w, 400, "Invalid body")
		return
	}
	var owned bool
	_ = s.db.QueryRowContext(r.Context(), `SELECT EXISTS(SELECT 1 FROM payments p JOIN applicants a ON a.id=p.applicant_id
		WHERE p.gateway_order_id=$1 AND a.user_id=$2)`, in.OrderID, claimsOf(r).Sub).Scan(&owned)
	if !owned {
		fail(w, 404, "Payment not found")
		return
	}
	res, err := s.settleCashfreeOrder(r.Context(), in.OrderID, "")
	if err != nil {
		fail(w, 502, "Could not confirm the payment yet: "+err.Error())
		return
	}
	if res.Done {
		s.notifyPayment(r.Context(), res.PayID, "payment_accepted", "Payment received", msgPaymentAccepted)
	}
	writeJSON(w, 200, M{"success": true, "status": res.Status})
}

// POST /api/payments/cashfree-webhook  (Cashfree -> us). Configure the URL in Cashfree dashboard -> Developers -> Webhooks,
// or set PUBLIC_API_URL and it is sent automatically with every order. Authenticity = HMAC-SHA256(timestamp+rawBody) with the secret key.
func (s *Server) cashfreeWebhook(w http.ResponseWriter, r *http.Request) {
	raw, err := io.ReadAll(io.LimitReader(r.Body, 1<<20))
	if err != nil || !s.cfEnabled() {
		fail(w, 400, "Bad request")
		return
	}
	mac := hmac.New(sha256.New, []byte(s.cfg.CashfreeSecret))
	mac.Write([]byte(r.Header.Get("x-webhook-timestamp")))
	mac.Write(raw)
	want := base64.StdEncoding.EncodeToString(mac.Sum(nil))
	if !hmac.Equal([]byte(want), []byte(r.Header.Get("x-webhook-signature"))) {
		fail(w, 401, "Invalid signature")
		return
	}
	var ev struct {
		Type string `json:"type"`
		Data struct {
			Order struct {
				OrderID string `json:"order_id"`
			} `json:"order"`
		} `json:"data"`
	}
	_ = json.Unmarshal(raw, &ev)
	if ev.Type == "PAYMENT_SUCCESS_WEBHOOK" && ev.Data.Order.OrderID != "" {
		res, err := s.settleCashfreeOrder(r.Context(), ev.Data.Order.OrderID, "")
		switch {
		case errors.Is(err, errPaymentLookup):
			// not one of our orders: acknowledge so Cashfree stops retrying
		case err != nil:
			fail(w, 500, "Could not process") // Cashfree retries
			return
		case res.Done:
			s.notifyPayment(r.Context(), res.PayID, "payment_accepted", "Payment received", msgPaymentAccepted)
		}
	}
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

// ===================== admin-initiated "Collect Payment" =====================
// Lets an admin (finance role) collect a booking payment on an applicant's behalf,
// either online (Cashfree checkout, charged there and then at the counter/desk) or offline
// (upload a receipt that is marked completed immediately, since the admin already
// has the money in hand).

// GET /api/admin/payments/awaiting?search= : applicants at stage_3_payment with their paid-so-far total.
func (s *Server) panelPaymentsAwaiting(w http.ResponseWriter, r *http.Request) {
	search := r.URL.Query().Get("search")
	rows, err := s.many(r.Context(), `SELECT a.id,a.unique_id,a.first_name||' '||a.last_name AS applicant_name,
		a.email,a.phone,a.created_at,
		COALESCE((SELECT sum(amount) FROM payments p WHERE p.applicant_id=a.id AND p.payment_status='completed'),0) AS paid
		FROM applicants a
		WHERE a.registration_stage='stage_3_payment'
		AND ($1='' OR a.first_name||' '||a.last_name ILIKE '%'||$1||'%' OR a.unique_id ILIKE '%'||$1||'%'
		     OR a.phone LIKE '%'||$1||'%' OR a.email ILIKE '%'||$1||'%')
		ORDER BY a.created_at DESC LIMIT 500`, search)
	if err != nil {
		fail(w, 500, "DB error")
		return
	}
	_, total := s.amountLimits(r.Context())
	writeJSON(w, 200, M{"success": true, "applicants": rows, "total_cost": total})
}

// POST /api/admin/payments/collect-order {applicant_id, amount} -> Cashfree order for the admin to charge at the counter.
func (s *Server) adminPayCollectOrder(w http.ResponseWriter, r *http.Request) {
	var in struct {
		ApplicantID string `json:"applicant_id"`
		Amount      float64
	}
	if !decode(r, &in) || in.ApplicantID == "" || in.Amount <= 0 {
		fail(w, 400, "applicant_id and amount are required")
		return
	}
	if in.Amount < 1 {
		fail(w, 400, "Minimum online amount is 1")
		return
	}
	if !s.cfEnabled() {
		fail(w, 503, "Online payments are not configured")
		return
	}
	app, err := s.one(r.Context(), `SELECT id,unique_id,first_name,last_name,email,phone,registration_stage FROM applicants WHERE id::text=$1`, in.ApplicantID)
	if err != nil || app == nil {
		fail(w, 404, "Applicant not found")
		return
	}
	if app["registration_stage"] != "stage_3_payment" {
		fail(w, 409, "Payment is not open for this applicant")
		return
	}
	out, code, err := s.cfCreateOrder(r.Context(), app, in.Amount, "adm")
	if err != nil {
		fail(w, code, err.Error())
		return
	}
	writeJSON(w, 200, out)
}

// POST /api/admin/payments/collect-verify {order_id} -> {success, status: paid|pending|failed}
func (s *Server) adminPayCollectVerify(w http.ResponseWriter, r *http.Request) {
	var in struct {
		OrderID string `json:"order_id"`
	}
	if !decode(r, &in) || in.OrderID == "" {
		fail(w, 400, "Invalid body")
		return
	}
	uid := claimsOf(r).Sub
	res, err := s.settleCashfreeOrder(r.Context(), in.OrderID, uid)
	if errors.Is(err, errPaymentLookup) {
		fail(w, 404, "Payment not found")
		return
	}
	if err != nil {
		fail(w, 502, "Could not confirm the payment yet: "+err.Error())
		return
	}
	if res.Done {
		s.notifyPayment(r.Context(), res.PayID, "payment_accepted", "Payment received", msgPaymentAccepted)
		s.audit(r.Context(), uid, "payment_collected_online", "payment", res.PayID, nil)
	}
	writeJSON(w, 200, M{"success": true, "status": res.Status})
}

// POST /api/admin/payments/collect-offline multipart {applicant_id, amount, receipt}
// The admin already has the money (cash/cheque/DD) in hand, so this is recorded as completed right away.
func (s *Server) adminPayCollectOffline(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseMultipartForm(16 << 20); err != nil {
		fail(w, 400, "Invalid form")
		return
	}
	appID := r.FormValue("applicant_id")
	app, err := s.one(r.Context(), `SELECT id,registration_stage FROM applicants WHERE id::text=$1`, appID)
	if err != nil || app == nil {
		fail(w, 404, "Applicant not found")
		return
	}
	if app["registration_stage"] != "stage_3_payment" {
		fail(w, 409, "Payment is not open for this applicant")
		return
	}
	amount, _ := strconv.ParseFloat(r.FormValue("amount"), 64)
	if amount <= 0 {
		fail(w, 400, "amount must be greater than 0")
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
	uid := claimsOf(r).Sub
	// optional form field "mode" (cash | dd | other): shown as the payment mode in Payment Management
	mode := strings.ToLower(strings.TrimSpace(r.FormValue("mode")))
	if mode != "cash" && mode != "dd" && mode != "other" {
		mode = ""
	}
	tx, _ := s.db.BeginTx(r.Context(), nil)
	defer tx.Rollback()
	var payID string
	if err := tx.QueryRowContext(r.Context(), `INSERT INTO payments(applicant_id,amount,payment_method,payment_stage,offline_receipt_path,payment_date,payment_mode,recorded_by)
		VALUES ($1,$2,'offline','booking',$3,current_date,NULLIF($4,''),$5::uuid) RETURNING id`, id, amount, rel, mode, uid).Scan(&payID); err != nil {
		fail(w, 500, "Failed to record payment")
		return
	}
	if err := completePayment(r.Context(), tx, payID, uid); err != nil || tx.Commit() != nil {
		fail(w, 500, "Failed to complete payment")
		return
	}
	s.notifyPayment(r.Context(), payID, "payment_accepted", "Payment received", "Your payment is confirmed. A unit will be allotted to you soon.")
	s.audit(r.Context(), uid, "payment_collected_offline", "payment", payID, M{"mode": mode})
	writeJSON(w, 201, M{"success": true, "message": "Payment recorded"})
}