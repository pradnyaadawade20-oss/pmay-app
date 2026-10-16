# PMAY backend (Go + PostgreSQL)

## Folder structure
```
backend/
├── cmd/api/main.go            entry point (just calls app.Run)
├── internal/
│   ├── app/                   HTTP server, routes and handlers
│   │   ├── server.go          Server struct, startup (Run), CORS, first-admin bootstrap
│   │   ├── routes.go          every endpoint in one place
│   │   ├── auth.go            JWT, password hashing, login middleware
│   │   ├── public.go          register / login / public lists
│   │   ├── otp.go             email + SMS OTP send/verify
│   │   ├── applicant.go       applicant ("/api/me") endpoints
│   │   ├── payments.go        Razorpay + offline payments
│   │   ├── files.go           document upload / download
│   │   ├── notifications.go   in-app notifications + push (device tokens)
│   │   ├── admin.go           admin workflow (validation, allotment, reviews)
│   │   ├── admin_panel.go     admin panel (users, units, DB viewer, settings)
│   │   ├── migrate.go         runs migrations/*.sql on start
│   │   └── util.go            JSON helpers, validators, DB helpers
│   ├── config/config.go       environment variables -> Config
│   ├── fcm/client.go          Firebase Cloud Messaging (HTTP v1) client
│   └── mailer/smtp.go         SMTP email sender
├── migrations/                001_init.sql, 002_admin_panel.sql, 003_notifications.sql
├── Dockerfile
├── docker-compose.yml         local Postgres + API
├── .env.example               copy to .env (never commit .env or firebase.json)
├── go.mod / go.sum
```

## Run locally
```
cp .env.example .env
docker compose up --build
curl http://localhost:8080/api/health
```
Or without Docker: `go run ./cmd/api` (needs Postgres, see DATABASE_URL).

## Deploy (Render)
Root Directory `backend`, Language Docker. Set the variables from `.env.example` under Environment.
Tables are created automatically by `migrations/` on first start.
