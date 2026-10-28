package app

import "net/http"

// routes registers every HTTP endpoint (public, applicant, admin).
func (s *Server) routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/health", func(w http.ResponseWriter, r *http.Request) { writeJSON(w, 200, M{"ok": true}) })

	// public
	mux.HandleFunc("POST /api/auth/register", s.register)
	mux.HandleFunc("POST /api/auth/signup", s.signup)
	mux.HandleFunc("POST /api/auth/login", s.login)
	mux.HandleFunc("GET /api/public/admins", s.publicAdmins)
	mux.HandleFunc("POST /api/otp/send", s.sendOTP)
	mux.HandleFunc("POST /api/otp/verify", s.verifyOTP)
	mux.HandleFunc("POST /api/ocr/extract", s.ocrExtract)

	// applicant
	mux.HandleFunc("GET /api/me", s.authed(s.me))
	mux.HandleFunc("POST /api/me/upload", s.authed(s.meUpload))
	mux.HandleFunc("POST /api/me/bank-documents", s.authed(s.meBankDocs))
	mux.HandleFunc("GET /api/me/notifications", s.authed(s.myNotifications))
	mux.HandleFunc("POST /api/me/notifications/read", s.authed(s.readNotifications))
	mux.HandleFunc("POST /api/me/device-token", s.authed(s.saveDeviceToken))
	mux.HandleFunc("POST /api/me/device-token/delete", s.authed(s.deleteDeviceToken))
	mux.HandleFunc("POST /api/payments/order", s.authed(s.payOrder))
	mux.HandleFunc("POST /api/payments/verify", s.authed(s.payVerify))
	mux.HandleFunc("POST /api/payments/offline", s.authed(s.payOffline))
	mux.HandleFunc("POST /api/payments/cashfree-webhook", s.cashfreeWebhook) // called by Cashfree, verified by signature
	mux.HandleFunc("GET /api/files/{path...}", s.authed(s.serveFile))

	// admin
	mux.HandleFunc("GET /api/admin/stats", s.authed(s.panelStats, anyAdmin...))
	mux.HandleFunc("GET /api/admin/applicants", s.authed(s.panelApplicants, anyAdmin...))
	mux.HandleFunc("GET /api/admin/applicants/{id}", s.authed(s.adminApplicant, anyAdmin...))
	mux.HandleFunc("GET /api/admin/system-status", s.authed(s.systemStatus, anyAdmin...))
	mux.HandleFunc("POST /api/admin/applicants/{id}/validation", s.authed(s.adminValidation, staff...))
	mux.HandleFunc("POST /api/admin/payments/{id}/review", s.authed(s.adminPaymentReview, financeRole...))
	mux.HandleFunc("GET /api/admin/units", s.authed(s.panelUnits, anyAdmin...))
	mux.HandleFunc("POST /api/admin/units", s.authed(s.panelAddUnit, allotRole...))
	mux.HandleFunc("GET /api/admin/applicants/{id}/mortgage-deed", s.authed(s.adminGetMortgageDeed, anyAdmin...))
	mux.HandleFunc("POST /api/admin/applicants/{id}/mortgage-deed", s.authed(s.adminSaveMortgageDeed, staff...))
	mux.HandleFunc("GET /api/admin/mortgage-schedule", s.authed(s.adminGetMortgageSchedule, anyAdmin...))
	mux.HandleFunc("POST /api/admin/mortgage-schedule", s.authed(s.adminSaveMortgageSchedule, staff...))
	mux.HandleFunc("POST /api/admin/applicants/{id}/allot", s.authed(s.adminAllot, allotRole...))
	mux.HandleFunc("POST /api/admin/applicants/{id}/agreement-review", s.authed(s.adminAgreementReview, staff...))
	mux.HandleFunc("POST /api/admin/applicants/{id}/stage", s.authed(s.adminSetStage, "super_admin"))
	mux.HandleFunc("POST /api/admin/users", s.authed(s.adminCreateUser, "super_admin"))

	// admin panel
	mux.HandleFunc("POST /api/admin/applicants/{id}/review", s.authed(s.adminReview, staff...))
	mux.HandleFunc("POST /api/admin/applicants/{id}/send-otp", s.authed(s.adminSendContactOTP, staff...))
	mux.HandleFunc("POST /api/admin/applicants/{id}/verify-otp", s.authed(s.adminVerifyContactOTP, staff...))
	mux.HandleFunc("POST /api/admin/applicants/{id}/verify-contact", s.authed(s.adminVerifyContactManually, staff...))
	mux.HandleFunc("POST /api/admin/applicants/{id}/cheque", s.authed(s.adminRecordCheque, financeRole...))
	mux.HandleFunc("GET /api/admin/applicants/{id}/documents/{kind}", s.authed(s.adminApplicantDoc, anyAdmin...))
	mux.HandleFunc("GET /api/admin/units/eligible-applicants", s.authed(s.eligibleApplicants, anyAdmin...))
	mux.HandleFunc("POST /api/admin/units/{id}/allot", s.authed(s.panelAllot, allotRole...))
	mux.HandleFunc("GET /api/admin/payments", s.authed(s.panelPayments, financeRole...))
	mux.HandleFunc("GET /api/admin/payments/awaiting", s.authed(s.panelPaymentsAwaiting, financeRole...))
	mux.HandleFunc("POST /api/admin/payments/collect-order", s.authed(s.adminPayCollectOrder, financeRole...))
	mux.HandleFunc("POST /api/admin/payments/collect-verify", s.authed(s.adminPayCollectVerify, financeRole...))
	mux.HandleFunc("POST /api/admin/payments/collect-offline", s.authed(s.adminPayCollectOffline, financeRole...))
	mux.HandleFunc("GET /api/admin/payments/{id}/receipt", s.authed(s.paymentReceipt, financeRole...))
	mux.HandleFunc("POST /api/admin/payments/{id}/{act}", s.authed(s.panelPayAct, financeRole...))
	mux.HandleFunc("GET /api/admin/document-settings", s.authed(s.docSettings, anyAdmin...))
	mux.HandleFunc("POST /api/admin/document-settings/{kind}", s.authed(s.docSettingSave, "super_admin"))
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

	return mux
}