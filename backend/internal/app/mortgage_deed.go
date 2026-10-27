package app

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"unicode/utf8"
)

// Simple Mortgage Deed support. Everything here is additive: if nothing was saved
// the customer app keeps printing the old mortgage document.

// loadDeed returns the per-applicant deed details and the project-level property schedule.
// Any error (e.g. migration not applied yet) simply yields empty maps.
func (s *Server) loadDeed(ctx context.Context, applicantID any) (M, M) {
	deed, schedule := M{}, M{}
	var raw []byte
	if err := s.db.QueryRowContext(ctx, `SELECT data FROM mortgage_deed_details WHERE applicant_id=$1`, applicantID).Scan(&raw); err == nil {
		_ = json.Unmarshal(raw, &deed)
	}
	var raw2 []byte
	if err := s.db.QueryRowContext(ctx, `SELECT data FROM mortgage_schedule WHERE id=1`).Scan(&raw2); err == nil {
		_ = json.Unmarshal(raw2, &schedule)
	}
	return deed, schedule
}

// cleanDeedData keeps only short text values (the deed is plain text).
func cleanDeedData(in map[string]any) (map[string]string, string) {
	if len(in) > 80 {
		return nil, "Too many fields"
	}
	out := map[string]string{}
	for k, v := range in {
		if v == nil {
			continue
		}
		str, ok := v.(string)
		if !ok {
			return nil, "Invalid value for " + k
		}
		str = strings.TrimSpace(str)
		limit := 500
		if k == "extra_terms" {
			limit = 1000
		}
		if utf8.RuneCountInString(str) > limit {
			return nil, k + " is too long"
		}
		if str != "" {
			out[k] = str
		}
	}
	return out, ""
}

// GET /api/admin/applicants/{id}/mortgage-deed
func (s *Server) adminGetMortgageDeed(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	app, err := s.one(r.Context(), `SELECT id FROM applicants WHERE id=$1`, id)
	if err != nil || app == nil {
		fail(w, 404, "Applicant not found")
		return
	}
	deed, schedule := s.loadDeed(r.Context(), id)
	writeJSON(w, 200, M{"success": true, "deed": deed, "schedule": schedule})
}

// POST /api/admin/applicants/{id}/mortgage-deed {data:{...}}
func (s *Server) adminSaveMortgageDeed(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	var in struct {
		Data map[string]any `json:"data"`
	}
	if !decode(r, &in) || in.Data == nil {
		fail(w, 400, "data required")
		return
	}
	clean, msg := cleanDeedData(in.Data)
	if msg != "" {
		fail(w, 400, msg)
		return
	}
	app, err := s.one(r.Context(), `SELECT id FROM applicants WHERE id=$1`, id)
	if err != nil || app == nil {
		fail(w, 404, "Applicant not found")
		return
	}
	b, _ := json.Marshal(clean)
	if _, err := s.db.ExecContext(r.Context(),
		`INSERT INTO mortgage_deed_details (applicant_id,data) VALUES ($1,$2::jsonb)
		 ON CONFLICT (applicant_id) DO UPDATE SET data=EXCLUDED.data, updated_at=now()`, id, string(b)); err != nil {
		fail(w, 500, "DB error")
		return
	}
	writeJSON(w, 200, M{"success": true})
}

// GET /api/admin/mortgage-schedule
func (s *Server) adminGetMortgageSchedule(w http.ResponseWriter, r *http.Request) {
	_, schedule := s.loadDeed(r.Context(), "00000000-0000-0000-0000-000000000000")
	writeJSON(w, 200, M{"success": true, "schedule": schedule})
}

// POST /api/admin/mortgage-schedule {data:{...}}
func (s *Server) adminSaveMortgageSchedule(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Data map[string]any `json:"data"`
	}
	if !decode(r, &in) || in.Data == nil {
		fail(w, 400, "data required")
		return
	}
	clean, msg := cleanDeedData(in.Data)
	if msg != "" {
		fail(w, 400, msg)
		return
	}
	b, _ := json.Marshal(clean)
	if _, err := s.db.ExecContext(r.Context(),
		`INSERT INTO mortgage_schedule (id,data) VALUES (1,$1::jsonb)
		 ON CONFLICT (id) DO UPDATE SET data=EXCLUDED.data, updated_at=now()`, string(b)); err != nil {
		fail(w, 500, "DB error")
		return
	}
	writeJSON(w, 200, M{"success": true})
}