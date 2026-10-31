package app

import (
	"context"
	"fmt"
	"net/http"
	"regexp"
	"strings"
	"sync"
	"time"
	"unicode"
)

// docForm is what the applicant typed on the registration form (Aadhaar digits only, PAN upper-case).
type docForm struct {
	First, Last, Father, Spouse, DOB, Address, Aadhar, PAN string
}

var (
	reDocWord = regexp.MustCompile(`[a-z0-9]+`)
	reDocPin  = regexp.MustCompile(`\b\d{6}\b`)
)

// normName lower-cases a name and keeps only letters and single spaces ("RAM  K." -> "ram k").
func normName(s string) string {
	var b strings.Builder
	space := false
	for _, r := range strings.ToLower(s) {
		switch {
		case unicode.IsLetter(r):
			b.WriteRune(r)
			space = false
		case !space && b.Len() > 0:
			b.WriteByte(' ')
			space = true
		}
	}
	return strings.TrimSpace(b.String())
}

// addressMatches is deliberately forgiving about formatting (commas, order, extra words the applicant added)
// but the PIN code must be the same and most of the words on the card must still be there.
func addressMatches(doc, typed string) bool {
	typedWords := map[string]bool{}
	for _, w := range reDocWord.FindAllString(strings.ToLower(typed), -1) {
		typedWords[w] = true
	}
	if pin := reDocPin.FindString(doc); pin != "" && !typedWords[pin] {
		return false
	}
	seen, hit := map[string]bool{}, 0
	for _, w := range reDocWord.FindAllString(strings.ToLower(doc), -1) {
		if !seen[w] {
			seen[w] = true
			if typedWords[w] {
				hit++
			}
		}
	}
	return len(seen) == 0 || float64(hit)/float64(len(seen)) >= 0.7
}

// docMismatch compares the typed form with what was read from the uploaded Aadhaar front / back and PAN images.
// It returns "" when everything that can be checked matches, otherwise a message for the applicant.
// Aadhaar and PAN numbers are always checked (they must be readable from the images); other fields are checked
// whenever the document shows them.
func docMismatch(f docForm, front, back, pan map[string]string) string {
	if front["aadharNumber"] == "" {
		return "Could not read the Aadhaar number from the Aadhaar front image. Please upload a clear photo of the front of your Aadhaar card."
	}
	if f.Aadhar != front["aadharNumber"] {
		return "Aadhaar number does not match the uploaded Aadhaar card. Please correct it."
	}
	if n := back["aadharNumber"]; n != "" && n != front["aadharNumber"] {
		return "The Aadhaar front and back images have different Aadhaar numbers. Please upload both sides of the same card."
	}
	if pan["panNumber"] == "" {
		return "Could not read a PAN number from the PAN card image. Please upload a clear photo of your PAN card."
	}
	if f.PAN != pan["panNumber"] {
		return "PAN number does not match the uploaded PAN card. Please correct it."
	}

	// name: must agree with the Aadhaar front or with the PAN card
	fn, ln := normName(f.First), normName(f.Last)
	haveName, nameOK := false, false
	for _, d := range []map[string]string{front, pan} {
		df, dl := normName(d["firstName"]), normName(d["lastName"])
		if df == "" && dl == "" {
			continue
		}
		haveName = true
		if (df == "" || df == fn) && (dl == "" || dl == ln) {
			nameOK = true
		}
	}
	if haveName && !nameOK {
		return "First / last name does not match your Aadhaar or PAN card. Please correct it."
	}

	// date of birth
	var dobs []string
	for _, d := range []map[string]string{front, pan} {
		if v := d["dateOfBirth"]; v != "" {
			dobs = append(dobs, v)
		}
	}
	if len(dobs) > 0 {
		ok := false
		for _, v := range dobs {
			ok = ok || v == strings.TrimSpace(f.DOB)
		}
		if !ok {
			return "Date of birth does not match your Aadhaar or PAN card. Please correct it."
		}
	}

	// father's name (Aadhaar back "S/O" or PAN card)
	if nf := normName(f.Father); nf != "" {
		var cands []string
		for _, d := range []map[string]string{back, pan} {
			if v := normName(d["fatherName"]); v != "" {
				cands = append(cands, v)
			}
		}
		if len(cands) > 0 {
			ok := false
			for _, v := range cands {
				ok = ok || v == nf
			}
			if !ok {
				return "Father's name does not match your Aadhaar or PAN card. Please correct it."
			}
		}
	}

	// spouse (Aadhaar back "W/O")
	if ns, ds := normName(f.Spouse), normName(back["spouseName"]); ns != "" && ds != "" && ns != ds {
		return "Spouse's name does not match your Aadhaar card. Please correct it."
	}

	// address (Aadhaar back)
	if doc := back["fullAddress"]; doc != "" && strings.TrimSpace(f.Address) != "" && !addressMatches(doc, f.Address) {
		return "Address does not match your Aadhaar card. Please correct it."
	}
	return ""
}

// verifyDocuments reads the three uploaded identity images and checks the typed details against them,
// so details cannot be edited after the scan (or typed freely) and still be submitted.
// Returns (0, "") when fine, otherwise an HTTP status and a message for the applicant.
func (s *Server) verifyDocuments(ctx context.Context, r *http.Request, f docForm) (int, string) {
	if !s.cfg.DocVerify || len(s.cfg.GeminiAPIKeys) == 0 { // DOC_VERIFY=false, or local setup without OCR
		return 0, ""
	}
	ctx, cancel := context.WithTimeout(ctx, 90*time.Second)
	defer cancel()

	kinds := []string{"aadhar_front", "aadhar_back", "pan_front"}
	labels := map[string]string{"aadhar_front": "Aadhaar front", "aadhar_back": "Aadhaar back", "pan_front": "PAN card"}
	type result struct {
		fields map[string]string
		code   int
		msg    string
	}
	res := make([]result, len(kinds))
	var wg sync.WaitGroup
	for i, k := range kinds {
		wg.Add(1)
		go func(i int, k string) {
			defer wg.Done()
			fields, code, msg := s.docFields(ctx, k, r.MultipartForm.File[k][0])
			res[i] = result{fields, code, msg}
		}(i, k)
	}
	wg.Wait()
	for i, x := range res {
		switch {
		case x.code == 0:
		case x.code == 400:
			return 400, fmt.Sprintf("%s: please upload a JPG or PNG image (up to 5MB) so it can be verified.", labels[kinds[i]])
		case x.code == 503:
			return 503, "Document verification is busy right now. Please try again in a few minutes."
		default:
			return 400, fmt.Sprintf("Could not read your %s image. Please upload a clear JPG or PNG photo.", labels[kinds[i]])
		}
	}
	if msg := docMismatch(f, res[0].fields, res[1].fields, res[2].fields); msg != "" {
		return 400, msg
	}
	return 0, ""
}