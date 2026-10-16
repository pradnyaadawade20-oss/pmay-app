package app

import (
	"context"
	"fmt"
	"io"
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
	dst, err := os.Create(full)
	if err != nil {
		return "", err
	}
	defer dst.Close()
	_, err = io.Copy(dst, src)
	return rel, err
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
	http.ServeFile(w, r, filepath.Join(s.cfg.UploadDir, rel))
}
