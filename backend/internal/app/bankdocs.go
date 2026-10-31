package app

import (
	"encoding/json"
	"net/http"
)

type bankDoc struct {
	Key      string
	Required bool
}

// Required documents per profile (from Bnak_Loan_Documents.xlsx). Keep in sync with
// frontend/lib/screens/bank_docs.dart.
var commonBankDocs = []bankDoc{
	{"pan_card", true}, {"identity_proof", true}, {"address_proof", true}, {"photographs", true},
}

var bankProfiles = map[string][]bankDoc{
	"salaried": {
		{"salary_slips", true}, {"salary_bank_statement", true}, {"form16_itr", true}, {"appointment_letter", true},
	},
	"business": {
		{"business_bank_statement", true}, {"business_registration", true}, {"entity_proof", true},
		{"profit_loss", true}, {"balance_sheet", true}, {"business_itr", true},
	},
	"nip": {
		{"nip_bank_statement", true}, {"salary_certificate", true}, {"employer_certificate", true},
		{"rental_income_proof", false}, {"shop_license", true}, {"business_place_photos", true},
	},
}

func bankDocsFor(profile string) ([]bankDoc, bool) {
	extra, ok := bankProfiles[profile]
	if !ok {
		return nil, false
	}
	return append(append([]bankDoc{}, commonBankDocs...), extra...), true
}

// POST /api/me/bank-documents multipart {profile_type, <doc_key>: file ...}
func (s *Server) meBankDocs(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseMultipartForm(64 << 20); err != nil {
		fail(w, 400, "Invalid form")
		return
	}
	app, ok := s.myApplicant(r)
	if !ok {
		fail(w, 404, "Application not found")
		return
	}
	if st := app["registration_stage"].(string); st != "stage_7_bank_document" {
		fail(w, 409, "Bank documents can only be uploaded at the Bank Documents stage")
		return
	}
	id := app["id"].(string)
	_, _ = s.db.ExecContext(r.Context(), `INSERT INTO loan_details(applicant_id) VALUES ($1) ON CONFLICT DO NOTHING`, id)
	var curProfile *string
	var raw []byte
	if err := s.db.QueryRowContext(r.Context(), `SELECT profile_type, docs FROM loan_details WHERE applicant_id=$1`, id).Scan(&curProfile, &raw); err != nil {
		fail(w, 500, "DB error")
		return
	}
	profile := r.FormValue("profile_type")
	if profile == "" && curProfile != nil {
		profile = *curProfile
	}
	defs, ok := bankDocsFor(profile)
	if !ok {
		fail(w, 400, "Select a profile: salaried, business or nip")
		return
	}
	docs := map[string]string{}
	if curProfile != nil && *curProfile == profile {
		_ = json.Unmarshal(raw, &docs) // switching profile starts with a clean list
	}
	n := 0
	for _, d := range defs {
		files := r.MultipartForm.File[d.Key]
		if len(files) == 0 {
			continue
		}
		rel, err := s.saveFile(r.Context(), id, d.Key, files[0])
		if err != nil {
			fail(w, 400, err.Error())
			return
		}
		_, _ = s.db.ExecContext(r.Context(), `INSERT INTO uploads(applicant_id,upload_type,file_name,file_path,file_size,uploaded_by) VALUES ($1,$2,$3,$4,$5,$6)`,
			id, d.Key, files[0].Filename, rel, files[0].Size, claimsOf(r).Sub)
		docs[d.Key] = rel
		n++
	}
	if n == 0 && (curProfile != nil && *curProfile == profile) {
		fail(w, 400, "No files received")
		return
	}
	complete, count := true, 0
	for _, d := range defs {
		if docs[d.Key] != "" {
			count++
		} else if d.Required {
			complete = false
		}
	}
	b, _ := json.Marshal(docs)
	_, _ = s.db.ExecContext(r.Context(), `UPDATE loan_details SET profile_type=$2, docs=$3::jsonb, docs_complete=$4, docs_count=$5,
		loan_status='pending', verification_notes=NULL, updated_at=now() WHERE applicant_id=$1`, id, profile, string(b), complete, count)
	loan, _ := s.one(r.Context(), `SELECT * FROM loan_details WHERE applicant_id=$1`, id)
	if complete {
		s.notify(r.Context(), id, "bank_docs_submitted", "Documents submitted", "All bank documents received. They are under review.")
	}
	writeJSON(w, 200, M{"success": true, "loan": loan})
}