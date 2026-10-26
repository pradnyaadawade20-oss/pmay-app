package app

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// POST /api/admin/applicants/{id}/thumb  {"image":"<base64 PNG/JPEG>","hand":"right|left"}
// Staff captured the applicant's thumb impression at the office; stored like any other upload.
func (s *Server) adminSaveThumb(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Image string `json:"image"`
		Hand  string `json:"hand"`
	}
	// the shared decode() caps JSON at 1 MB; a fingerprint PNG can be larger, so allow 4 MB here
	if json.NewDecoder(http.MaxBytesReader(w, r.Body, 4<<20)).Decode(&in) != nil || in.Image == "" {
		fail(w, 400, "Invalid body")
		return
	}
	id := r.PathValue("id")
	if app, _ := s.one(r.Context(), `SELECT id FROM applicants WHERE id::text=$1`, id); app == nil {
		fail(w, 404, "Applicant not found")
		return
	}
	img := in.Image
	if strings.HasPrefix(img, "data:") {
		if i := strings.Index(img, ","); i >= 0 {
			img = img[i+1:]
		}
	}
	data, err := base64.StdEncoding.DecodeString(img)
	if err != nil || len(data) < 16 {
		fail(w, 400, "Invalid image")
		return
	}
	if len(data) > 2<<20 {
		fail(w, 400, "Image too large (max 2 MB)")
		return
	}
	ext := ""
	switch {
	case data[0] == 0x89 && data[1] == 'P' && data[2] == 'N' && data[3] == 'G':
		ext = "png"
	case data[0] == 0xFF && data[1] == 0xD8:
		ext = "jpg"
	default:
		fail(w, 400, "Only PNG or JPEG images are accepted")
		return
	}
	hand := "right"
	if in.Hand == "left" {
		hand = "left"
	}
	rel := fmt.Sprintf("%s/thumb_impression_%d.%s", id, time.Now().UnixNano(), ext)
	if _, err := s.db.ExecContext(r.Context(), `INSERT INTO file_blobs(path,content_type,data) VALUES ($1,$2,$3)
		ON CONFLICT (path) DO UPDATE SET data=EXCLUDED.data, content_type=EXCLUDED.content_type`, rel, contentTypeFor(ext), data); err != nil {
		fail(w, 500, "Could not store the image")
		return
	}
	full := filepath.Join(s.cfg.UploadDir, rel)
	if err := os.MkdirAll(filepath.Dir(full), 0o755); err == nil {
		if err := os.WriteFile(full, data, 0o644); err != nil {
			log.Println("thumb: disk copy failed (database copy kept):", err)
		}
	}
	if _, err := s.db.ExecContext(r.Context(), `INSERT INTO uploads(applicant_id,upload_type,file_name,file_path,file_size,uploaded_by) VALUES ($1,$2,$3,$4,$5,$6)`,
		id, "thumb_impression", "thumb_"+hand+"."+ext, rel, len(data), claimsOf(r).Sub); err != nil {
		s.dropBlobs(r.Context(), rel)
		_ = os.Remove(full)
		fail(w, 500, "Failed to save thumb impression")
		return
	}
	s.notify(r.Context(), id, "thumb_recorded", "Thumb impression recorded", "Your thumb impression was recorded at the office. Open the app to complete signing.")
	writeJSON(w, 200, M{"success": true})
}

// GET /api/me/thumb -> latest thumb impression image of the signed-in applicant (404 if none).
func (s *Server) meThumb(w http.ResponseWriter, r *http.Request) {
	app, ok := s.myApplicant(r)
	if !ok {
		fail(w, 404, "Application not found")
		return
	}
	m, _ := s.one(r.Context(), `SELECT file_path AS p FROM uploads WHERE applicant_id=$1 AND upload_type='thumb_impression' ORDER BY uploaded_at DESC`, app["id"])
	p, _ := m["p"].(string)
	if p == "" {
		fail(w, 404, "No thumb impression recorded")
		return
	}
	s.serveStored(w, r, p)
}