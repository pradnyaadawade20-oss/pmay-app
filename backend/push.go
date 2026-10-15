package main

import (
	"bytes"
	"context"
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"
)

// ---------- FCM HTTP v1 (stdlib only, service-account auth) ----------

type fcmClient struct {
	projectID, clientEmail string
	key                    *rsa.PrivateKey
	mu                     sync.Mutex
	token                  string
	tokenExp               time.Time
}

// newFCM reads FCM_SERVICE_ACCOUNT_JSON (raw JSON) or FCM_SERVICE_ACCOUNT_FILE. Returns nil if not configured.
func newFCM(cfg Config) *fcmClient {
	raw := []byte(cfg.FCMServiceAccountJSON)
	if len(raw) == 0 && cfg.FCMServiceAccountFile != "" {
		b, err := os.ReadFile(cfg.FCMServiceAccountFile)
		if err != nil {
			log.Println("fcm: cannot read service account file:", err)
			return nil
		}
		raw = b
	}
	if len(raw) == 0 {
		return nil
	}
	var sa struct {
		ProjectID   string `json:"project_id"`
		ClientEmail string `json:"client_email"`
		PrivateKey  string `json:"private_key"`
	}
	if json.Unmarshal(raw, &sa) != nil || sa.ProjectID == "" || sa.ClientEmail == "" {
		log.Println("fcm: invalid service account JSON")
		return nil
	}
	blk, _ := pem.Decode([]byte(sa.PrivateKey))
	if blk == nil {
		log.Println("fcm: invalid private key")
		return nil
	}
	k, err := x509.ParsePKCS8PrivateKey(blk.Bytes)
	rk, ok := k.(*rsa.PrivateKey)
	if err != nil || !ok {
		log.Println("fcm: private key is not RSA/PKCS8")
		return nil
	}
	log.Println("fcm: push enabled for project", sa.ProjectID)
	return &fcmClient{projectID: sa.ProjectID, clientEmail: sa.ClientEmail, key: rk}
}

func (f *fcmClient) accessToken(ctx context.Context) (string, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.token != "" && time.Now().Before(f.tokenExp.Add(-time.Minute)) {
		return f.token, nil
	}
	now := time.Now()
	hdr := b64([]byte(`{"alg":"RS256","typ":"JWT"}`))
	cl, _ := json.Marshal(M{"iss": f.clientEmail, "scope": "https://www.googleapis.com/auth/firebase.messaging",
		"aud": "https://oauth2.googleapis.com/token", "iat": now.Unix(), "exp": now.Add(55 * time.Minute).Unix()})
	unsigned := hdr + "." + b64(cl)
	h := sha256.Sum256([]byte(unsigned))
	sig, err := rsa.SignPKCS1v15(rand.Reader, f.key, crypto.SHA256, h[:])
	if err != nil {
		return "", err
	}
	form := url.Values{"grant_type": {"urn:ietf:params:oauth:grant-type:jwt-bearer"}, "assertion": {unsigned + "." + b64(sig)}}
	req, _ := http.NewRequestWithContext(ctx, "POST", "https://oauth2.googleapis.com/token", strings.NewReader(form.Encode()))
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	var out struct {
		AccessToken string `json:"access_token"`
		ExpiresIn   int    `json:"expires_in"`
	}
	b, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != 200 || json.Unmarshal(b, &out) != nil || out.AccessToken == "" {
		return "", fmt.Errorf("oauth token error %d: %s", resp.StatusCode, string(b))
	}
	f.token, f.tokenExp = out.AccessToken, now.Add(time.Duration(out.ExpiresIn)*time.Second)
	return f.token, nil
}

var errTokenInvalid = errors.New("fcm token invalid")

func (f *fcmClient) send(ctx context.Context, deviceToken, title, body string, data map[string]string) error {
	at, err := f.accessToken(ctx)
	if err != nil {
		return err
	}
	msg := M{"message": M{
		"token":        deviceToken,
		"notification": M{"title": title, "body": body},
		"data":         data,
		"android":      M{"priority": "HIGH", "notification": M{"channel_id": "pmay_updates"}},
	}}
	b, _ := json.Marshal(msg)
	req, _ := http.NewRequestWithContext(ctx, "POST", "https://fcm.googleapis.com/v1/projects/"+f.projectID+"/messages:send", bytes.NewReader(b))
	req.Header.Set("Authorization", "Bearer "+at)
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode == 200 {
		return nil
	}
	rb, _ := io.ReadAll(resp.Body)
	if resp.StatusCode == 404 || (resp.StatusCode == 400 && bytes.Contains(rb, []byte("INVALID_ARGUMENT")) && bytes.Contains(rb, []byte("registration token"))) ||
		bytes.Contains(rb, []byte("UNREGISTERED")) {
		return errTokenInvalid
	}
	return fmt.Errorf("fcm %d: %s", resp.StatusCode, string(rb))
}

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
		payload := map[string]string{"kind": kind, "notification_id": nid}
		if st, ok := data["stage"].(string); ok {
			payload["stage"] = st
		}
		for _, t := range tokens {
			if err := s.fcm.send(bg, t, title, body, payload); errors.Is(err, errTokenInvalid) {
				_, _ = s.db.ExecContext(bg, `DELETE FROM device_tokens WHERE token=$1`, t)
			} else if err != nil {
				log.Println("push:", err)
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
	if _, err := s.db.ExecContext(r.Context(), `INSERT INTO device_tokens(user_id,token,platform) VALUES ($1,$2,$3)
		ON CONFLICT (token) DO UPDATE SET user_id=EXCLUDED.user_id, platform=EXCLUDED.platform, last_seen_at=now()`,
		claimsOf(r).Sub, in.Token, in.Platform); err != nil {
		fail(w, 500, "Failed to save token")
		return
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
	_, _ = s.db.ExecContext(r.Context(), `DELETE FROM device_tokens WHERE token=$1 AND user_id=$2`, in.Token, claimsOf(r).Sub)
	writeJSON(w, 200, M{"success": true})
}