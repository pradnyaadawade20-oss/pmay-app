package app

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"log"
	"mime/multipart"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// settingKey maps upload types to document_settings rows.
func settingKey(t string) string {
	if strings.HasPrefix(t, "itr_") {
		return "itr"
	}
	if strings.HasPrefix(t, "agreement_signed_") { // extra pages of a multi-file agreement
		return "agreement_signed"
	}
	return t
}

// saveFile validates the upload against document_settings and stores it under UPLOAD_DIR/<applicantID>/.
// Returns the relative path stored in DB.
func (s *Server) saveFile(ctx context.Context, applicantID, utype string, fh *multipart.FileHeader) (string, error) {
	maxMB, exts := 5.0, []string{"jpg", "jpeg", "png", "pdf"}
	var arr string
	if err := s.db.QueryRowContext(ctx, `SELECT max_size_mb, array_to_string(allowed_extensions, ',') FROM document_settings WHERE document_type=$1`, settingKey(utype)).Scan(&maxMB, &arr); err == nil && arr != "" {
		exts = strings.Split(arr, ",")
	}
	if float64(fh.Size) > maxMB*1024*1024 {
		return "", fmt.Errorf("%s: file too large (max %.0f MB)", utype, maxMB)
	}
	ext := strings.ToLower(strings.TrimPrefix(filepath.Ext(fh.Filename), "."))
	ok := false
	for _, e := range exts {
		if e == ext {
			ok = true
		}
	}
	if !ok {
		return "", fmt.Errorf("%s: file type .%s not allowed (allowed: %s)", utype, ext, strings.Join(exts, ", "))
	}
	rel := fmt.Sprintf("%s/%s_%d.%s", applicantID, utype, time.Now().UnixNano(), ext)
	full := filepath.Join(s.cfg.UploadDir, rel)
	if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
		return "", err
	}
	src, err := fh.Open()
	if err != nil {
		return "", err
	}
	defer src.Close()
	data, err := io.ReadAll(io.LimitReader(src, int64(maxMB*1024*1024)+1))
	if err != nil {
		return "", err
	}
	// The database copy is what survives redeploys; the disk copy is just a fast cache.
	if _, err := s.db.ExecContext(ctx, `INSERT INTO file_blobs(path,content_type,data) VALUES ($1,$2,$3)
		ON CONFLICT (path) DO UPDATE SET data=EXCLUDED.data, content_type=EXCLUDED.content_type`, rel, contentTypeFor(ext), data); err != nil {
		return "", fmt.Errorf("could not store the file: %w", err)
	}
	if err := os.WriteFile(full, data, 0o644); err != nil {
		log.Println("saveFile: disk copy failed (database copy kept):", err)
	}
	return rel, nil
}

func contentTypeFor(ext string) string {
	switch ext {
	case "jpg", "jpeg":
		return "image/jpeg"
	case "png":
		return "image/png"
	case "pdf":
		return "application/pdf"
	}
	return "application/octet-stream"
}

// serveStored sends an uploaded file: from disk if present, otherwise from the database copy.
// rel is the relative path stored in the DB (checked by the caller for ownership / role).
func (s *Server) serveStored(w http.ResponseWriter, r *http.Request, rel string) {
	rel = filepath.Clean(rel)
	if strings.Contains(rel, "..") {
		fail(w, 400, "Bad path")
		return
	}
	full := filepath.Join(s.cfg.UploadDir, rel)
	if st, err := os.Stat(full); err == nil && !st.IsDir() {
		http.ServeFile(w, r, full)
		return
	}
	var ct string
	var data []byte
	var created time.Time
	if err := s.db.QueryRowContext(r.Context(), `SELECT content_type, data, created_at FROM file_blobs WHERE path=$1`, filepath.ToSlash(rel)).Scan(&ct, &data, &created); err != nil {
		fail(w, 404, "The file is no longer stored. Ask the applicant to upload it again.")
		return
	}
	w.Header().Set("Content-Type", ct)
	http.ServeContent(w, r, filepath.Base(rel), created, bytes.NewReader(data))
}

// dropBlobs removes stored copies under a path prefix (e.g. an applicant folder) after a failed or deleted upload.
func (s *Server) dropBlobs(ctx context.Context, prefix string) {
	_, _ = s.db.ExecContext(ctx, `DELETE FROM file_blobs WHERE path LIKE $1`, prefix+"%")
}

// GET /api/files/{path...}  -> owner (first path segment == own applicant id) or any admin role.
func (s *Server) serveFile(w http.ResponseWriter, r *http.Request) {
	c := claimsOf(r)
	rel := filepath.Clean(r.PathValue("path"))
	if strings.Contains(rel, "..") {
		fail(w, 400, "Bad path")
		return
	}
	if !c.has(anyAdmin...) {
		me, _ := s.one(r.Context(), `SELECT id FROM applicants WHERE user_id=$1`, c.Sub)
		if me == nil || !strings.HasPrefix(rel, me["id"].(string)+"/") {
			fail(w, 403, "Forbidden")
			return
		}
	}
	s.serveStored(w, r, rel)
}
