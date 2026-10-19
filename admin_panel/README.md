# Krutarth PMAY - Admin Panel (Flutter Web)

Talks to the same Go backend as the mobile app (`pmay-app/backend`). There is no demo/mock mode: every screen reads and writes real data through the API.

## Run
```
flutter pub get
flutter run -d chrome                                   # uses the live API https://pmay-app.onrender.com/api
flutter run -d chrome --dart-define=API_BASE=http://localhost:8080/api   # local backend
flutter build web --release                             # output: build/web
```
The API URL can also be changed on the login screen under "Server settings".

## Login
Sign in with an account that has an admin role (created by the backend from `ADMIN_EMAIL`/`ADMIN_PASSWORD`, or by a super admin in User Management). The token is a JWT issued by `POST /api/auth/login`; a 401 logs you out.

| Role | Can |
|---|---|
| super_admin | everything, incl. User Management, Database Tables, Document Settings, stage override |
| admin | review applicants / agreements / bank documents, payments, allotment |
| finance | view applicants, confirm/reject offline payments |
| allotment_manager | view applicants, allot units |
| auditor | read-only |

Buttons a role may not use are hidden; the backend enforces the same rules.
