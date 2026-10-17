package app

import (
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"pmay-backend/internal/ocr"
)

// At most 2 OCR runs at once (tesseract is CPU heavy and this endpoint is public).
var ocrSlots = make(chan struct{}, 2)

// POST /api/ocr/extract  multipart: type=aadhar_front|aadhar_back|pan_front, file=<jpg|png>
// Returns the form fields it could read; the app pre-fills the registration form with them.
func (s *Server) ocrExtract(w http.ResponseWriter, r *http.Request) {
	if !ocr.Available() {
		fail(w, 503, "OCR is not available on this server")
		return
	}
	if err := r.ParseMultipartForm(8 << 20); err != nil {
		fail(w, 400, "Invalid form")
		return
	}
	kind := r.FormValue("type")
	if kind != "aadhar_front" && kind != "aadhar_back" && kind != "pan_front" {
		fail(w, 400, "type must be aadhar_front, aadhar_back or pan_front")
		return
	}
	files := r.MultipartForm.File["file"]
	if len(files) == 0 || files[0].Size > 5<<20 {
		fail(w, 400, "An image up to 5MB is required")
		return
	}
	ext := strings.ToLower(filepath.Ext(files[0].Filename))
	if ext != ".jpg" && ext != ".jpeg" && ext != ".png" {
		fail(w, 400, "Only JPG or PNG images can be read")
		return
	}
	select {
	case ocrSlots <- struct{}{}:
		defer func() { <-ocrSlots }()
	default:
		fail(w, 429, "Busy, please try again in a moment")
		return
	}
	src, err := files[0].Open()
	if err != nil {
		fail(w, 400, "Cannot read file")
		return
	}
	defer src.Close()
	tmp, err := os.CreateTemp("", "ocr-*"+ext)
	if err != nil {
		fail(w, 500, "Server error")
		return
	}
	defer os.Remove(tmp.Name())
	_, err = io.Copy(tmp, src)
	tmp.Close()
	if err != nil {
		fail(w, 500, "Server error")
		return
	}
	path := tmp.Name()
	small := path + ".small.png"
	defer os.Remove(small)
	if ocr.Prepare(path, small) == nil { // grayscale + shrink; falls back to the original if it can't be decoded
		path = small
	}
	text, err := ocr.Text(r.Context(), path)
	if err != nil {
		fail(w, 502, "Could not read the image")
		return
	}
	writeJSON(w, 200, M{"success": true, "fields": ocr.Parse(kind, text)})
}
