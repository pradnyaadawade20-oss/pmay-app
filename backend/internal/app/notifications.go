package app

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strconv"
	"time"

	"pmay-backend/internal/fcm"
)

// ---------- notify: store in DB + push to all devices of the applicant ----------

// notify saves an in-app notification and sends a push. Never blocks or fails the caller.
func (s *Server) notify(ctx context.Context, applicantID, kind, title, body string) {
	if applicantID == "" {
		return
	}
	stage, _ := s.one(ctx, `SELECT registration_stage FROM applicants WHERE id=$1`, applicantID)
	data := M{"kind": kind}
	if stage != nil {
		data["stage"] = stage["registration_stage"]
	}
	dj, _ := json.Marshal(data)
	var nid string
	if err := s.db.QueryRowContext(ctx, `INSERT INTO notifications(applicant_id,kind,title,body,data) VALUES ($1,$2,$3,$4,$5::jsonb) RETURNING id`,
		applicantID, kind, title, body, string(dj)).Scan(&nid); err != nil {
		log.Println("notify insert:", err)
		return
	}
	if s.fcm == nil {
		log.Println("push skipped: FCM not configured (set FCM_SERVICE_ACCOUNT_JSON on Render):", kind)
		return
	}
	go func() { // detached: request context ends when the HTTP response is written
		bg, cancel := context.WithTimeout(context.Background(), 20*time.Second)
		defer cancel()
		rows, err := s.db.QueryContext(bg, `SELECT d.token FROM device_tokens d JOIN applicants a ON a.user_id=d.user_id WHERE a.id=$1`, applicantID)
		if err != nil {
			return
		}
		var tokens []string
		for rows.Next() {
			var t string
			if rows.Scan(&t) == nil {
				tokens = append(tokens, t)
			}
		}
		rows.Close()
		if len(tokens) == 0 {
			log.Println("push skipped: no device token registered for this user (log in on the phone & allow notifications):", kind)
			return
		}
		payload := map[string]string{"kind": kind, "notification_id": nid}
		if st, ok := data["stage"].(string); ok {
			payload["stage"] = st
		}
		for _, t := range tokens {
			if err := s.fcm.Send(bg, t, title, body, payload); errors.Is(err, fcm.ErrTokenInvalid) {
				_, _ = s.db.ExecContext(bg, `DELETE FROM device_tokens WHERE token=$1`, t)
			} else if err != nil {
				log.Println("push:", err)
			} else {
				log.Println("push sent:", kind)
			}
		}
	}()
}

// notifyPayment resolves the applicant of a payment and notifies them.
func (s *Server) notifyPayment(ctx context.Context, paymentID, kind, title, body string) {
	var appID string
	if s.db.QueryRowContext(ctx, `SELECT applicant_id FROM payments WHERE id=$1`, paymentID).Scan(&appID) == nil {
		s.notify(ctx, appID, kind, title, body)
	}
}

// ---------- API ----------

// GET /api/me/notifications?limit=50&before=<RFC3339>
func (s *Server) myNotifications(w http.ResponseWriter, r *http.Request) {
	app, ok := s.myApplicant(r)
	if !ok {
		writeJSON(w, 200, M{"success": true, "notifications": []M{}, "unread": 0})
		return
	}
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	if limit <= 0 || limit > 100 {
		limit = 50
	}
	before := r.URL.Query().Get("before")
	rows, err := s.many(r.Context(), `SELECT id,kind,title,body,data,read_at,created_at FROM notifications
		WHERE applicant_id=$1 AND ($2='' OR created_at < $2::timestamptz) ORDER BY created_at DESC LIMIT $3`, app["id"], before, limit)
	if err != nil {
		fail(w, 500, "DB error")
		return
	}
	var unread int
	_ = s.db.QueryRowContext(r.Context(), `SELECT count(*) FROM notifications WHERE applicant_id=$1 AND read_at IS NULL`, app["id"]).Scan(&unread)
	writeJSON(w, 200, M{"success": true, "notifications": rows, "unread": unread})
}

// POST /api/me/notifications/read {ids:[...]} or {all:true}
func (s *Server) readNotifications(w http.ResponseWriter, r *http.Request) {
	var in struct {
		IDs []string `json:"ids"`
		All bool     `json:"all"`
	}
	if !decode(r, &in) {
		fail(w, 400, "Invalid body")
		return
	}
	app, ok := s.myApplicant(r)
	if !ok {
		fail(w, 404, "Application not found")
		return
	}
	if in.All {
		_, _ = s.db.ExecContext(r.Context(), `UPDATE notifications SET read_at=now() WHERE applicant_id=$1 AND read_at IS NULL`, app["id"])
	} else if len(in.IDs) > 0 {
		for _, id := range in.IDs {
			_, _ = s.db.ExecContext(r.Context(), `UPDATE notifications SET read_at=now() WHERE id=$1::uuid AND applicant_id=$2 AND read_at IS NULL`, id, app["id"])
		}
	}
	writeJSON(w, 200, M{"success": true})
}

// POST /api/me/device-token {token, platform}
func (s *Server) saveDeviceToken(w http.ResponseWriter, r *http.Request) {
	var in struct{ Token, Platform string }
	if !decode(r, &in) || len(in.Token) < 20 || len(in.Token) > 4096 {
		fail(w, 400, "Valid token required")
		return
	}
	if in.Platform == "" {
		in.Platform = "android"
	}
	// a token belongs to exactly one user (re-assigned if another account logs in on the same device)
	var fresh bool // true only when this device was not registered for this user before (i.e. a new login)
	if err := s.db.QueryRowContext(r.Context(), `INSERT INTO device_tokens(user_id,token,platform) VALUES ($1,$2,$3)
		ON CONFLICT (token) DO UPDATE SET user_id=EXCLUDED.user_id, platform=EXCLUDED.platform, last_seen_at=now()
		RETURNING (xmax = 0)`,
		claimsOf(r).Sub, in.Token, in.Platform).Scan(&fresh); err != nil {
		fail(w, 500, "Failed to save token")
		return
	}
	log.Println("device token saved, new device:", fresh)
	if fresh {
		// Push "logged in" - skipped for brand-new registrations (they get the "Registration received" push instead).
		var appID string
		if s.db.QueryRowContext(r.Context(), `SELECT id FROM applicants WHERE user_id=$1 AND created_at < now() - interval '2 minutes'`,
			claimsOf(r).Sub).Scan(&appID) == nil {
			s.notify(r.Context(), appID, "login", "Welcome back", "You are logged in to Krutarth - PMAY.")
		}
	}
	writeJSON(w, 200, M{"success": true})
}

// POST /api/me/device-token/delete {token}  (call on logout)
func (s *Server) deleteDeviceToken(w http.ResponseWriter, r *http.Request) {
	var in struct{ Token string }
	if !decode(r, &in) || in.Token == "" {
		fail(w, 400, "Token required")
		return
	}
	// Tell the user they were logged out: stored in-app + pushed to THIS device only, then the token is removed.
	var appID string
	if s.db.QueryRowContext(r.Context(), `SELECT id FROM applicants WHERE user_id=$1`, claimsOf(r).Sub).Scan(&appID) == nil {
		_, _ = s.db.ExecContext(r.Context(), `INSERT INTO notifications(applicant_id,kind,title,body) VALUES ($1,'logout','Logged out','You have been logged out of Krutarth - PMAY.')`, appID)
		if s.fcm != nil {
			ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
			if err := s.fcm.Send(ctx, in.Token, "Logged out", "You have been logged out of Krutarth - PMAY.", map[string]string{"kind": "logout"}); err != nil {
				log.Println("push logout:", err)
			}
			cancel()
		}
	}
	_, _ = s.db.ExecContext(r.Context(), `DELETE FROM device_tokens WHERE token=$1 AND user_id=$2`, in.Token, claimsOf(r).Sub)
	writeJSON(w, 200, M{"success": true})
}