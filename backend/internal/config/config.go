package config

import (
	"os"
	"strconv"
	"strings"
)

type Config struct {
	Port, DatabaseURL, JWTSecret, UploadDir          string
	ResendKey, ResendFrom                            string
	SMTPHost, SMTPPort, SMTPUser, SMTPPass, SMTPFrom string // email via SMTP (needs a paid Render instance)
	MSG91Key, MSG91Sender                            string
	GeminiModel                                      string   // OCR via Google Gemini
	GeminiAPIKeys                                    []string // up to 5 keys, tried in order (see geminiKeys)
	RazorpayKeyID, RazorpaySecret                    string
	AdminEmail, AdminPassword                        string
	DevMode                                          bool // DEV_MODE=true -> OTP returned in API response (never use in prod)
	CORSOrigins                                      string
	RequireContactVerified                           bool   // REQUIRE_CONTACT_VERIFIED=false -> admin may accept applicants who skipped OTP
	FCMServiceAccountFile, FCMServiceAccountJSON     string // Firebase push (optional)
}

func env(k, d string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return d
}

func Load() Config {
	return Config{
		Port:                   env("PORT", "8080"),
		DatabaseURL:            env("DATABASE_URL", "postgres://pmay:pmay@localhost:5432/pmay?sslmode=disable"),
		JWTSecret:              env("JWT_SECRET", "change-me"),
		UploadDir:              env("UPLOAD_DIR", "./uploads"),
		ResendKey:              os.Getenv("RESEND_API_KEY"),
		SMTPHost:               os.Getenv("SMTP_HOST"),
		SMTPPort:               env("SMTP_PORT", "587"),
		SMTPUser:               os.Getenv("SMTP_USER"),
		SMTPPass:               os.Getenv("SMTP_PASS"),
		SMTPFrom:               os.Getenv("SMTP_FROM"),
		ResendFrom:             env("RESEND_FROM", "PMAY Registration <noreply@pmay.beellz.com>"),
		MSG91Key:               os.Getenv("MSG91_AUTH_KEY"),
		MSG91Sender:            env("MSG91_SENDER_ID", "PMAYOT"),
		GeminiAPIKeys:          geminiKeys(),
		GeminiModel:            env("GEMINI_MODEL", "gemini-2.5-flash"),
		RazorpayKeyID:          os.Getenv("RAZORPAY_KEY_ID"),
		RazorpaySecret:         os.Getenv("RAZORPAY_KEY_SECRET"),
		AdminEmail:             os.Getenv("ADMIN_EMAIL"),
		AdminPassword:          os.Getenv("ADMIN_PASSWORD"),
		DevMode:                strings.EqualFold(os.Getenv("DEV_MODE"), "true"),
		CORSOrigins:            env("CORS_ORIGINS", "*"),
		RequireContactVerified: !strings.EqualFold(os.Getenv("REQUIRE_CONTACT_VERIFIED"), "false"),
		FCMServiceAccountFile:  os.Getenv("FCM_SERVICE_ACCOUNT_FILE"),
		FCMServiceAccountJSON:  os.Getenv("FCM_SERVICE_ACCOUNT_JSON"),
	}
}

// SMTPEnabled is true when SMTP_HOST, SMTP_USER and SMTP_PASS are all set.
func (c Config) SMTPEnabled() bool {
	return c.SMTPHost != "" && c.SMTPUser != "" && c.SMTPPass != ""
}

// geminiKeys collects the Gemini API keys in priority order: GEMINI_API_KEY, GEMINI_API_KEY_2 .. _5,
// then any in the comma-separated GEMINI_API_KEYS. Duplicates and blanks are dropped; at most 5 are used.
func geminiKeys() []string {
	var raw []string
	raw = append(raw, os.Getenv("GEMINI_API_KEY"))
	for i := 2; i <= 5; i++ {
		raw = append(raw, os.Getenv("GEMINI_API_KEY_"+strconv.Itoa(i)))
	}
	raw = append(raw, strings.Split(os.Getenv("GEMINI_API_KEYS"), ",")...)
	seen := map[string]bool{}
	var out []string
	for _, k := range raw {
		if k = strings.TrimSpace(k); k != "" && !seen[k] && len(out) < 5 {
			seen[k] = true
			out = append(out, k)
		}
	}
	return out
}
