package fcm

import (
	"bytes"
	"context"
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"strings"
	"sync"
	"time"

	"pmay-backend/internal/config"
)

type obj = map[string]any

func b64(b []byte) string { return base64.RawURLEncoding.EncodeToString(b) }

// ---------- FCM HTTP v1 (stdlib only, service-account auth) ----------

type Client struct {
	projectID, clientEmail string
	key                    *rsa.PrivateKey
	mu                     sync.Mutex
	token                  string
	tokenExp               time.Time
}

// New reads FCM_SERVICE_ACCOUNT_JSON (raw JSON) or FCM_SERVICE_ACCOUNT_FILE. Returns nil if not configured.
func New(cfg config.Config) *Client {
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
	return &Client{projectID: sa.ProjectID, clientEmail: sa.ClientEmail, key: rk}
}

func (f *Client) accessToken(ctx context.Context) (string, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.token != "" && time.Now().Before(f.tokenExp.Add(-time.Minute)) {
		return f.token, nil
	}
	now := time.Now()
	hdr := b64([]byte(`{"alg":"RS256","typ":"JWT"}`))
	cl, _ := json.Marshal(obj{"iss": f.clientEmail, "scope": "https://www.googleapis.com/auth/firebase.messaging",
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

var ErrTokenInvalid = errors.New("fcm token invalid")

func (f *Client) Send(ctx context.Context, deviceToken, title, body string, data map[string]string) error {
	at, err := f.accessToken(ctx)
	if err != nil {
		return err
	}
	msg := obj{"message": obj{
		"token":        deviceToken,
		"notification": obj{"title": title, "body": body},
		"data":         data,
		"android":      obj{"priority": "HIGH", "notification": obj{"channel_id": "pmay_updates"}},
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
		return ErrTokenInvalid
	}
	return fmt.Errorf("fcm %d: %s", resp.StatusCode, string(rb))
}
