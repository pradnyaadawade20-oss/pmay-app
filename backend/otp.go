package main

import (
	"bytes"
	"crypto/rand"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"math/big"
	"net/http"
	"net/url"
	"strings"
	"time"
)

func genOTP() string {
	n, _ := rand.Int(rand.Reader, big.NewInt(900000))
	return fmt.Sprintf("%06d", n.Int64()+100000)
}

// POST /api/otp/send {type:"email"|"phone", email?, phone?}
func (s *Server) sendOTP(w http.ResponseWriter, r *http.Request) {
	var in struct{ Type, Email, Phone string }
	if !decode(r, &in) {
		fail(w, 400, "Invalid body")
		return
	}
	otp := genOTP()
	exp := time.Now().Add(10 * time.Minute)
	switch in.Type {
	case "email":
		email := normEmail(in.Email)
		if !reEmail.MatchString(email) {
			fail(w, 400, "Valid email is required")
			return
		}
		if _, err := s.db.ExecContext(r.Context(), `INSERT INTO otp_verifications(email,otp_code,otp_type,expires_at) VALUES ($1,$2,'email',$3)`, email, otp, exp); err != nil {
			fail(w, 500, "Failed to store OTP")
			return
		}
		if s.cfg.smtpEnabled() {
			html := fmt.Sprintf(`<h2>PMAY Registration</h2><p>Your OTP is <b style="font-size:28px;letter-spacing:6px">%s</b></p><p>Valid for 10 minutes.</p>`, otp)
			if err := sendSMTP(s.cfg, email, "Your OTP for PMAY Registration", html); err != nil {
				log.Println("smtp send failed:", err)
				fail(w, 502, "Failed to send email OTP")
				return
			}
		} else if s.cfg.ResendKey != "" {
			body, _ := json.Marshal(M{"from": s.cfg.ResendFrom, "to": []string{email}, "subject": "Your OTP for PMAY Registration",
				"html": fmt.Sprintf(`<h2>PMAY Registration</h2><p>Your OTP is <b style="font-size:28px;letter-spacing:6px">%s</b></p><p>Valid for 10 minutes.</p>`, otp)})
			req, _ := http.NewRequest("POST", "https://api.resend.com/emails", bytes.NewReader(body))
			req.Header.Set("Authorization", "Bearer "+s.cfg.ResendKey)
			req.Header.Set("Content-Type", "application/json")
			resp, err := http.DefaultClient.Do(req)
			if err != nil || resp.StatusCode >= 300 {
				fail(w, 502, "Failed to send email OTP")
				return
			}
			resp.Body.Close()
		}
	case "phone":
		phone := normPhone(in.Phone)
		if len(phone) != 13 {
			fail(w, 400, "Valid 10-digit phone is required")
			return
		}
		if _, err := s.db.ExecContext(r.Context(), `INSERT INTO otp_verifications(phone,otp_code,otp_type,expires_at) VALUES ($1,$2,'phone',$3)`, phone, otp, exp); err != nil {
			fail(w, 500, "Failed to store OTP")
			return
		}
		if s.cfg.MSG91Key != "" {
			q := url.Values{"authkey": {s.cfg.MSG91Key}, "mobiles": {strings.TrimPrefix(phone, "+")},
				"message": {"Your PMAY Registration OTP is " + otp + ". Valid for 10 minutes."},
				"sender":  {s.cfg.MSG91Sender}, "route": {"4"}, "country": {"91"}}
			resp, err := http.Get("https://api.msg91.com/api/sendhttp.php?" + q.Encode())
			if err != nil {
				fail(w, 502, "Failed to send SMS")
				return
			}
			b, _ := io.ReadAll(resp.Body)
			resp.Body.Close()
			if strings.Contains(strings.ToLower(string(b)), "error") {
				fail(w, 502, "SMS sending failed")
				return
			}
		}
	default:
		fail(w, 400, "Invalid verification type")
		return
	}
	res := M{"success": true, "message": "OTP sent successfully"}
	if s.cfg.DevMode {
		res["devOtp"] = otp // only when DEV_MODE=true
	}
	writeJSON(w, 200, res)
}

// POST /api/otp/verify {type, email?, phone?, otp}
func (s *Server) verifyOTP(w http.ResponseWriter, r *http.Request) {
	var in struct{ Type, Email, Phone, Otp string }
	if !decode(r, &in) || len(in.Otp) != 6 {
		fail(w, 400, "Please enter a valid OTP")
		return
	}
	col, val := "email", normEmail(in.Email)
	if in.Type == "phone" {
		col, val = "phone", normPhone(in.Phone)
	} else if in.Type != "email" {
		fail(w, 400, "Invalid verification type")
		return
	}
	rec, err := s.one(r.Context(), `SELECT id, otp_code, attempts FROM otp_verifications
		WHERE `+col+`=$1 AND otp_type=$2 AND verified_at IS NULL AND expires_at>now()
		ORDER BY created_at DESC LIMIT 1`, val, in.Type)
	if err != nil || rec == nil {
		fail(w, 400, "Invalid or expired OTP. Please request a new one.")
		return
	}
	id := rec["id"].(string)
	if rec["attempts"].(float64) >= 5 {
		fail(w, 429, "Too many attempts. Please request a new OTP.")
		return
	}
	_, _ = s.db.ExecContext(r.Context(), `UPDATE otp_verifications SET attempts=attempts+1 WHERE id=$1`, id)
	if rec["otp_code"].(string) != in.Otp {
		fail(w, 400, "Incorrect OTP")
		return
	}
	_, _ = s.db.ExecContext(r.Context(), `UPDATE otp_verifications SET verified_at=now() WHERE id=$1`, id)
	_, _ = s.db.ExecContext(r.Context(), `UPDATE applicants SET `+col+`_verified=true WHERE `+col+`=$1`, val)
	writeJSON(w, 200, M{"success": true, "verified": true})
}