package app

import (
	"context"
	"database/sql"
	"log"
	"net/http"
	"os"
	"strings"

	_ "github.com/lib/pq"

	"pmay-backend/internal/config"
	"pmay-backend/internal/fcm"
)

type Server struct {
	cfg config.Config
	db  *sql.DB
	fcm *fcm.Client // nil when push is not configured
}

// Run loads config, connects to Postgres, runs migrations and serves the API (blocks).
func Run() {
	cfg := config.Load()
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
	s := &Server{cfg: cfg, db: db, fcm: fcm.New(cfg)}
	s.migrate()
	_ = os.MkdirAll(cfg.UploadDir, 0o755)
	s.bootstrapAdmin()

	log.Println("PMAY API listening on :" + cfg.Port)
	log.Fatal(http.ListenAndServe(":"+cfg.Port, s.cors(s.routes())))
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
