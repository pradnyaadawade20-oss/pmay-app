package main

import (
	"os"
	"strings"
)

type Config struct {
	Port, DatabaseURL, JWTSecret, UploadDir      string
	ResendKey, ResendFrom                        string
	MSG91Key, MSG91Sender                        string
	RazorpayKeyID, RazorpaySecret                string
	AdminEmail, AdminPassword                    string
	DevMode                                      bool // DEV_MODE=true -> OTP returned in API response (never use in prod)
	CORSOrigins                                  string
	FCMServiceAccountFile, FCMServiceAccountJSON string // Firebase push (optional)
}

func env(k, d string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return d
}

func loadConfig() Config {
	return Config{
		Port:                  env("PORT", "8080"),
		DatabaseURL:           env("DATABASE_URL", "postgres://pmay:pmay@localhost:5432/pmay?sslmode=disable"),
		JWTSecret:             env("JWT_SECRET", "change-me"),
		UploadDir:             env("UPLOAD_DIR", "./uploads"),
		ResendKey:             os.Getenv("RESEND_API_KEY"),
		ResendFrom:            env("RESEND_FROM", "PMAY Registration <noreply@pmay.beellz.com>"),
		MSG91Key:              os.Getenv("MSG91_AUTH_KEY"),
		MSG91Sender:           env("MSG91_SENDER_ID", "PMAYOT"),
		RazorpayKeyID:         os.Getenv("RAZORPAY_KEY_ID"),
		RazorpaySecret:        os.Getenv("RAZORPAY_KEY_SECRET"),
		AdminEmail:            os.Getenv("ADMIN_EMAIL"),
		AdminPassword:         os.Getenv("ADMIN_PASSWORD"),
		DevMode:               strings.EqualFold(os.Getenv("DEV_MODE"), "true"),
		CORSOrigins:           env("CORS_ORIGINS", "*"),
		FCMServiceAccountFile: os.Getenv("FCM_SERVICE_ACCOUNT_FILE"),
		FCMServiceAccountJSON: os.Getenv("FCM_SERVICE_ACCOUNT_JSON"),
	}
}