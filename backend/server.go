package main

import (
	"context"
	"database/sql"
	"log"
	"net/http"
	"os"
	"strings"

	_ "github.com/lib/pq"
)

type Server struct {
	cfg Config
	db  *sql.DB
	fcm *fcmClient // nil when push is not configured
}

func main() {
	cfg := loadConfig()
	if cfg.JWTSecret == "change-me" || len(cfg.JWTSecret) < 32 {
		if !cfg.DevMode {
			log.Fatal("JWT_SECRET must be set to a random string of 32+ characters (or set DEV_MODE=true for local testing)")
		}
		log.Println("WARNING: weak JWT_SECRET (allowed only because DEV_MODE=true)")
	}
	db, err := sql.Open("postgres", cfg.DatabaseURL)
	if err != nil {
		log.Fatal(err)
	}
	db.SetMaxOpenConns(20)
	if err := db.Ping(); err != nil {
		log.Fatal("db: ", err)
	}
	s := &Server{cfg: cfg, db: db, fcm: newFCM(cfg)}
	s.migrate()
	_ = os.MkdirAll(cfg.UploadDir, 0o755)
	s.bootstrapAdmin()

	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/health", func(w http.ResponseWriter, r *http.Request) { writeJSON(w, 200, M{"ok": true}) })

	// public
	mux.HandleFunc("POST /api/auth/register", s.register)
	mux.HandleFunc("POST /api/auth/login", s.login)
	mux.HandleFunc("GET /api/public/admins", s.publicAdmins)
	mux.HandleFunc("POST /api/otp/send", s.sendOTP)
	mux.HandleFunc("POST /api/otp/verify", s.verifyOTP)

	// applicant
	mux.HandleFunc("GET /api/me", s.authed(s.me))
	mux.HandleFunc("POST /api/me/upload", s.authed(s.meUpload))
	mux.HandleFunc("POST /api/me/bank-documents", s.authed(s.meBankDocs))
	mux.HandleFunc("GET /api/me/documents/{kind}", s.authed(s.meDocument))
	mux.HandleFunc("GET /api/me/notifications", s.authed(s.myNotifications))
	mux.HandleFunc("POST /api/me/notifications/read", s.authed(s.readNotifications))
	mux.HandleFunc("POST /api/me/device-token", s.authed(s.saveDeviceToken))
	mux.HandleFunc("POST /api/me/device-token/delete", s.authed(s.deleteDeviceToken))
	mux.HandleFunc("POST /api/payments/order", s.authed(s.payOrder))
	mux.HandleFunc("POST /api/payments/verify", s.authed(s.payVerify))
	mux.HandleFunc("POST /api/payments/offline", s.authed(s.payOffline))
	mux.HandleFunc("GET /api/files/{path...}", s.authed(s.serveFile))

	// admin
	mux.HandleFunc("GET /api/admin/stats", s.authed(s.panelStats, anyAdmin...))
	mux.HandleFunc("GET /api/admin/applicants", s.authed(s.panelApplicants, anyAdmin...))
	mux.HandleFunc("GET /api/admin/applicants/{id}", s.authed(s.adminApplicant, anyAdmin...))
	mux.HandleFunc("POST /api/admin/applicants/{id}/validation", s.authed(s.adminValidation, staff...))
	mux.HandleFunc("POST /api/admin/payments/{id}/review", s.authed(s.adminPaymentReview, financeRole...))
	mux.HandleFunc("GET /api/admin/units", s.authed(s.adminUnits, anyAdmin...))
	mux.HandleFunc("POST /api/admin/applicants/{id}/allot", s.authed(s.adminAllot, allotRole...))
	mux.HandleFunc("POST /api/admin/applicants/{id}/agreement-review", s.authed(s.adminAgreementReview, staff...))
	mux.HandleFunc("POST /api/admin/applicants/{id}/bank-review", s.authed(s.adminBankReview, staff...))
	mux.HandleFunc("POST /api/admin/applicants/{id}/stage", s.authed(s.adminSetStage, "super_admin"))
	mux.HandleFunc("POST /api/admin/users", s.authed(s.adminCreateUser, "super_admin"))

	// admin panel
	mux.HandleFunc("POST /api/admin/applicants/{id}/review", s.authed(s.adminReview, staff...))
	mux.HandleFunc("GET /api/admin/applicants/{id}/documents/{kind}", s.authed(s.adminApplicantDoc, anyAdmin...))
	mux.HandleFunc("GET /api/admin/units/eligible-applicants", s.authed(s.eligibleApplicants, anyAdmin...))
	mux.HandleFunc("POST /api/admin/units/{id}/allot", s.authed(s.panelAllot, allotRole...))
	mux.HandleFunc("GET /api/admin/payments", s.authed(s.panelPayments, financeRole...))
	mux.HandleFunc("POST /api/admin/payments/{id}/{act}", s.authed(s.panelPayAct, financeRole...))
	mux.HandleFunc("GET /api/admin/document-settings", s.authed(s.docSettings, anyAdmin...))
	mux.HandleFunc("POST /api/admin/document-settings/{kind}", s.authed(s.docSettingSave, staff...))
	mux.HandleFunc("GET /api/admin/users", s.authed(s.panelUsers, anyAdmin...))
	mux.HandleFunc("POST /api/admin/users/assign", s.authed(s.userAssign, "super_admin"))
	mux.HandleFunc("POST /api/admin/users/invite", s.authed(s.userInvite, "super_admin"))
	mux.HandleFunc("POST /api/admin/users/create", s.authed(s.userCreate, "super_admin"))
	mux.HandleFunc("POST /api/admin/users/{id}/name", s.authed(s.userName, "super_admin"))
	mux.HandleFunc("POST /api/admin/users/{id}/delete", s.authed(s.userDelete, "super_admin"))
	mux.HandleFunc("GET /api/admin/db/tables", s.authed(s.dbList, "super_admin"))
	mux.HandleFunc("GET /api/admin/db/tables/{table}", s.authed(s.dbRows, "super_admin"))
	mux.HandleFunc("POST /api/admin/db/tables/{table}/{id}/update", s.authed(s.dbUpdate, "super_admin"))
	mux.HandleFunc("POST /api/admin/db/tables/{table}/{id}/delete", s.authed(s.dbDelete, "super_admin"))

	log.Println("PMAY API listening on :" + cfg.Port)
	log.Fatal(http.ListenAndServe(":"+cfg.Port, s.cors(mux)))
}

func (s *Server) cors(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", s.cfg.CORSOrigins)
		w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		if r.Method == "OPTIONS" {
			w.WriteHeader(204)
			return
		}
		r.Body = http.MaxBytesReader(w, r.Body, 40<<20)
		next.ServeHTTP(w, r)
	})
}

// bootstrapAdmin creates the first super_admin from ADMIN_EMAIL / ADMIN_PASSWORD (if set and missing).
func (s *Server) bootstrapAdmin() {
	if s.cfg.AdminEmail == "" || s.cfg.AdminPassword == "" {
		return
	}
	ctx := context.Background()
	var id string
	email := normEmail(s.cfg.AdminEmail)
	err := s.db.QueryRowContext(ctx, `INSERT INTO users(email,password_hash) VALUES ($1,$2)
		ON CONFLICT (email) DO UPDATE SET email=EXCLUDED.email RETURNING id`, email, hashPassword(s.cfg.AdminPassword)).Scan(&id)
	if err != nil {
		log.Println("bootstrap admin:", err)
		return
	}
	_, _ = s.db.ExecContext(ctx, `INSERT INTO user_roles(user_id,role,display_name) VALUES ($1,'super_admin','Super Admin') ON CONFLICT DO NOTHING`, id)
	log.Println("super_admin ready:", email)
}

func isUniqueErr(err error) string {
	if err == nil {
		return ""
	}
	m := err.Error()
	if strings.Contains(m, "duplicate key") {
		switch {
		case strings.Contains(m, "aadhar"):
			return "This Aadhaar number is already registered"
		case strings.Contains(m, "pan_number"):
			return "This PAN number is already registered"
		case strings.Contains(m, "phone"):
			return "This phone number is already registered"
		case strings.Contains(m, "email"):
			return "This email is already registered"
		}
		return "Already registered"
	}
	return ""
}