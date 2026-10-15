# PMAY Registration – Flow

```
[Register]  ->  [OTP verify: phone OR email]  ->  stage_1_registered
      |
      v  ADMIN validation (accept/reject, max 1000 accepts/day)
stage_3_payment      -> applicant pays booking (min Rs 25,000): Razorpay (auto) OR offline receipt (admin approves)
      v
stage_4_allotment    -> admin allots a unit (110 units, 22 floors x 5)
      v
stage_5_agreement    -> applicant downloads allotment letter + agreement, signs, uploads signed copy
      v
stage_6_agreement_receipt -> admin reviews:  accept -> stage_7 | reject -> back to stage_5 (with reason)
      v
stage_7_bank_document -> applicant uploads 5 docs (UPI stmt, ITR x3, bank stmt) -> admin approve/reject
      v
stage_8_bank_loan    -> applicant downloads loan form, uploads loan receipt
      v
stage_9_mortgage     -> applicant downloads mortgage deed, uploads signed receipt
      v
stage_10_completed
```

## Roles
super_admin, admin, finance (payments), allotment_manager (allotment), auditor (read-only)

## API (Go)
Public: POST /api/auth/register (multipart) | /auth/login | GET /public/admins | POST /otp/send | /otp/verify
Applicant: GET /me | POST /me/upload | /me/bank-documents | GET /me/documents/{allotment|agreement|bank-loan|mortgage}
           POST /payments/order | /payments/verify | /payments/offline | GET /files/{path}
Admin: GET /admin/stats | /admin/applicants | /admin/applicants/{id} | /admin/units
       POST /admin/applicants/{id}/validation | /allot | /agreement-review | /bank-review | /stage
       POST /admin/payments/{id}/review | /admin/users

## Admin panel API (same backend, base http://localhost:8080/api)
Login: POST /auth/login (roles must include admin/super_admin for the panel)
GET /admin/stats -> {stats:{total,pending_review,pending_payments,completed,available_units,by_stage}}
GET /admin/applicants?search=&stage= | /admin/applicants/{id} | /admin/applicants/{id}/documents/{kind} (file bytes)
POST /admin/applicants/{id}/review {decision:approve|reject,reason} | /stage {stage}
GET /admin/units | /admin/units/eligible-applicants ; POST /admin/units/{id}/allot {applicant_id}
GET /admin/payments?status= ; POST /admin/payments/{id}/confirm|reject
GET /admin/document-settings ; POST /admin/document-settings/{kind} {max_size_mb,ai_validation}
GET /admin/users ; POST /admin/users/assign|invite|create, /users/{id}/name, /users/{id}/delete   (super_admin)
GET /admin/db/tables, /db/tables/{t}?search= ; POST /db/tables/{t}/{id}/update|delete           (super_admin, whitelisted)
Migration 002_admin_panel.sql adds user_roles.assigned_at + document_settings.label/ai_validation.
Existing DBs: run 002 manually (docker initdb only runs on first start).
Panel: turn off Demo mode, set base URL to the backend; CORS_ORIGINS must allow the panel origin.

## Structure
```
pmay-app/
├─ FLOW.md
├─ backend/   (Go)  main: server.go | public.go applicant.go payments.go admin.go otp.go files.go auth.go
│                   migrations/001_init.sql | Dockerfile | docker-compose.yml | .env.example
└─ frontend/  (Flutter)  pubspec.yaml
   └─ lib/ main.dart api.dart state.dart widgets.dart pdf_docs.dart
      └─ screens/ login register otp dashboard payment bank_docs
```

## Run
Backend:  cd backend && cp .env.example .env && docker compose up --build
Flutter:  cd frontend && flutter create --org com.krutarth --project-name pmay_app . && flutter pub get
          flutter run --dart-define=API_BASE=http://10.0.2.2:8080/api
Android: minSdkVersion 21 + INTERNET permission (razorpay_flutter).

## Notes
- Backend tested end-to-end on Postgres (register -> completed). Flutter code NOT compiled here (no SDK).
- Razorpay live flow untested (needs keys). Admin screens not in Flutter yet (admin APIs ready).
- Legal clause text for PDFs: paste into _clauses() in lib/pdf_docs.dart.
- Original bug fixed: bank approval now -> stage_8_bank_loan (website used stage_7_bank_loan).
