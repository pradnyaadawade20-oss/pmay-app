package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"net/http"
	"regexp"
	"strconv"
	"strings"
)

type M = map[string]any

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}
func fail(w http.ResponseWriter, code int, msg string) {
	writeJSON(w, code, M{"success": false, "error": msg})
}
func decode(r *http.Request, v any) bool {
	return json.NewDecoder(http.MaxBytesReader(nil, r.Body, 1<<20)).Decode(v) == nil
}

// one runs a SELECT and returns the first row as a map (nil if none).
func (s *Server) one(ctx context.Context, q string, args ...any) (M, error) {
	return queryOne(ctx, s.db, q, args...)
}

type querier interface {
	QueryRowContext(ctx context.Context, q string, args ...any) *sql.Row
}

func queryOne(ctx context.Context, db querier, q string, args ...any) (M, error) {
	var raw []byte
	err := db.QueryRowContext(ctx, "SELECT to_jsonb(t) FROM ("+q+") t LIMIT 1", args...).Scan(&raw)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var m M
	return m, json.Unmarshal(raw, &m)
}

func (s *Server) many(ctx context.Context, q string, args ...any) ([]M, error) {
	var raw []byte
	if err := s.db.QueryRowContext(ctx, "SELECT COALESCE(jsonb_agg(to_jsonb(t)),'[]'::jsonb) FROM ("+q+") t", args...).Scan(&raw); err != nil {
		return nil, err
	}
	out := []M{}
	return out, json.Unmarshal(raw, &out)
}

func (s *Server) audit(ctx context.Context, userID, action, entity, entityID string, details M) {
	d, _ := json.Marshal(details)
	_, _ = s.db.ExecContext(ctx, `INSERT INTO audit_logs(user_id,action,entity_type,entity_id,details)
		VALUES (NULLIF($1,'')::uuid,$2,$3,NULLIF($4,'')::uuid,$5::jsonb)`, userID, action, entity, entityID, string(d))
}

var (
	reAadhar = regexp.MustCompile(`^\d{12}$`)
	rePAN    = regexp.MustCompile(`^[A-Z]{5}[0-9]{4}[A-Z]$`)
	reEmail  = regexp.MustCompile(`^[^@\s]+@[^@\s]+\.[^@\s]+$`)
	reDigits = regexp.MustCompile(`\D`)
)

func normEmail(e string) string { return strings.ToLower(strings.TrimSpace(e)) }

// normPhone: 10-digit Indian numbers become +91XXXXXXXXXX
func normPhone(p string) string {
	d := reDigits.ReplaceAllString(p, "")
	if len(d) == 10 {
		d = "91" + d
	}
	return "+" + d
}

// stageNum("stage_7_bank_document") == 7
func stageNum(s string) int {
	parts := strings.Split(s, "_")
	if len(parts) < 2 {
		return 0
	}
	n, _ := strconv.Atoi(parts[1])
	return n
}

var stageNames = M{
	"stage_1_registered": "Registered", "stage_3_payment": "Payment", "stage_4_allotment": "Allotment",
	"stage_5_agreement": "Agreement", "stage_6_agreement_receipt": "Agreement Receipt",
	"stage_7_bank_document": "Bank Documents", "stage_8_bank_loan": "Bank Loan",
	"stage_9_mortgage": "Mortgage Deed", "stage_10_completed": "Completed",
}

func orDefault(v, d string) string {
	if strings.TrimSpace(v) == "" {
		return d
	}
	return v
}