package app

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

// Guards against routes silently disappearing in merges (this has happened: OCR, system-status and the
// units route were lost when two people edited routes.go). Each endpoint must exist: the router answers
// 404 for unknown paths and 405 for a wrong method, so anything else (401, 400, 503...) means it is registered.
func TestRoutesRegistered(t *testing.T) {
	h := (&Server{}).routes()
	for _, rt := range [][2]string{
		{"POST", "/api/auth/register"}, {"POST", "/api/auth/signup"}, {"POST", "/api/auth/login"},
		{"POST", "/api/otp/send"}, {"POST", "/api/otp/verify"},
		{"POST", "/api/ocr/extract"},
		{"GET", "/api/me"}, {"GET", "/api/me/documents/allotment"}, {"GET", "/api/me/thumb"}, {"POST", "/api/payments/offline"},
		{"GET", "/api/admin/stats"}, {"GET", "/api/admin/system-status"},
		{"GET", "/api/admin/applicants"}, {"GET", "/api/admin/applicants/x"},
		{"GET", "/api/admin/applicants/x/documents/passport_photo"},
		{"POST", "/api/admin/applicants/x/review"}, {"POST", "/api/admin/applicants/x/agreement-review"},
		{"POST", "/api/admin/applicants/x/bank-review"}, {"POST", "/api/admin/applicants/x/stage"},
		{"POST", "/api/admin/applicants/x/send-otp"}, {"POST", "/api/admin/applicants/x/verify-otp"}, {"POST", "/api/admin/applicants/x/verify-contact"}, {"POST", "/api/admin/applicants/x/cheque"}, {"POST", "/api/admin/applicants/x/thumb"},
		{"GET", "/api/admin/units"}, {"GET", "/api/admin/units/eligible-applicants"}, {"POST", "/api/admin/units/x/allot"},
		{"GET", "/api/admin/payments"}, {"POST", "/api/admin/payments/x/confirm"}, {"GET", "/api/admin/payments/x/receipt"},
		{"GET", "/api/admin/document-settings"}, {"POST", "/api/admin/document-settings/x"},
		{"GET", "/api/admin/users"}, {"POST", "/api/admin/users/create"}, {"POST", "/api/admin/users/x/delete"},
		{"GET", "/api/admin/db/tables"}, {"GET", "/api/admin/db/tables/x"},
		{"POST", "/api/admin/db/tables/x/y/update"}, {"POST", "/api/admin/db/tables/x/y/delete"},
	} {
		w := httptest.NewRecorder()
		h.ServeHTTP(w, httptest.NewRequest(rt[0], rt[1], nil))
		if w.Code == http.StatusNotFound || w.Code == http.StatusMethodNotAllowed {
			t.Errorf("%s %s is not registered (got %d)", rt[0], rt[1], w.Code)
		}
	}
}
