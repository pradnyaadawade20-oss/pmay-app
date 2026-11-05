package app

import "net/http"

// Cheap "has anything changed?" checks. The admin panel and the customer app ask every 2 seconds and
// reload their data only when the revision they get back is different from the last one, so changes made by
// someone else (an admin approving a step, an applicant uploading a file) show up without a manual refresh.
// The revision is a hash of counts, timestamps and status columns, so it changes whenever those do.

// GET /api/admin/sync -> {rev}
func (s *Server) adminSync(w http.ResponseWriter, r *http.Request) {
	var rev string
	err := s.db.QueryRowContext(r.Context(), `SELECT md5(concat_ws('|',
		(SELECT count(*)::text || coalesce(max(updated_at)::text,'') || coalesce(sum(hashtext(
			registration_stage || '/' || coalesce(stage_2_status,'') || '/' || coalesce(stage_4_status,'') || '/' || coalesce(bank_loan_status,'') || '/' ||
			email_verified::text || phone_verified::text || coalesce(handling_admin_id::text,'')))::text,'') FROM applicants),
		(SELECT count(*)::text || coalesce(max(updated_at)::text,'') || coalesce(sum(hashtext(payment_status))::text,'') FROM payments),
		(SELECT count(*)::text || coalesce(max(updated_at)::text,'') || coalesce(sum(docs_count),0)::text FROM loan_details),
		(SELECT count(*)::text || coalesce(max(uploaded_at)::text,'') FROM uploads),
		(SELECT count(*)::text || coalesce(sum(hashtext(status || coalesce(allocated_to::text,''))),0)::text FROM units)
	))`).Scan(&rev)
	if err != nil {
		fail(w, 500, "DB error")
		return
	}
	writeJSON(w, 200, M{"success": true, "rev": rev})
}

// GET /api/me/sync -> {rev}  (the signed-in applicant's own record, payments, bank documents and notifications)
func (s *Server) meSync(w http.ResponseWriter, r *http.Request) {
	var rev string
	err := s.db.QueryRowContext(r.Context(), `SELECT md5(concat_ws('|', a.updated_at::text, a.registration_stage,
		coalesce(a.stage_2_status,''), coalesce(a.stage_4_status,''), coalesce(a.bank_loan_status,''), a.email_verified::text, a.phone_verified::text,
		(SELECT count(*)::text || coalesce(max(updated_at)::text,'') || coalesce(string_agg(payment_status, ''),'') FROM payments WHERE applicant_id=a.id),
		(SELECT count(*)::text || coalesce(max(updated_at)::text,'') || coalesce(sum(docs_count),0)::text FROM loan_details WHERE applicant_id=a.id),
		(SELECT count(*)::text || coalesce(max(created_at)::text,'') || count(read_at)::text FROM notifications WHERE applicant_id=a.id)))
		FROM applicants a WHERE a.user_id=$1`, claimsOf(r).Sub).Scan(&rev)
	if err != nil { // no applicant yet (signed up, form not filled): nothing to watch
		writeJSON(w, 200, M{"success": true, "rev": "none"})
		return
	}
	writeJSON(w, 200, M{"success": true, "rev": rev})
}
