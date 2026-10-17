package app

import (
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"pmay-backend/internal/ocr"
)

// At most 2 tesseract runs at once (CPU heavy; this endpoint is public).
var ocrSlots = make(chan struct{}, 2)

// Per-IP limit: Gemini calls cost money and the endpoint needs no login.
const ocrPerHour = 20

var ocrHits = struct {
	sync.Mutex
	m map[string][]time.Time
}{m: map[string][]time.Time{}}

func ocrAllowed(ip string) bool {
	ocrHits.Lock()
	defer ocrHits.Unlock()
	now := time.Now()
	recent := ocrHits.m[ip][:0]
	for _, t := range ocrHits.m[ip] {
		if now.Sub(t) < time.Hour {
			recent = append(recent, t)
		}
	}
	if len(recent) >= ocrPerHour {
		ocrHits.m[ip] = recent
		return false
	}
	ocrHits.m[ip] = append(recent, now)
	return true
}

func clientIP(r *http.Request) string {
	if xf := r.Header.Get("X-Forwarded-For"); xf != "" {
		return strings.TrimSpace(strings.Split(xf, ",")[0])
	}
	h, _, _ := net.SplitHostPort(r.RemoteAddr)
	return h
}

// POST /api/ocr/extract  multipart: type=aadhar_front|aadhar_back|pan_front, file=<jpg|png>
// Reads the card with Google Gemini (GEMINI_API_KEY) and falls back to Tesseract if Gemini is
// not configured or fails. Returns the form fields it could read; the app pre-fills the form.
func (s *Server) ocrExtract(w http.ResponseWriter, r *http.Request) {
	useGemini := s.cfg.GeminiAPIKey != ""
	if !useGemini && !ocr.Available() {
		fail(w, 503, "OCR is not available on this server")
		return
	}
	if !ocrAllowed(clientIP(r)) {
		fail(w, 429, "Too many scans. Please try again later or type the details.")
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
	path, mime := tmp.Name(), "image/png"
	if ext != ".png" {
		mime = "image/jpeg"
	}
	small := path + ".small.png"
	defer os.Remove(small)
	if ocr.Prepare(path, small) == nil { // grayscale + shrink; falls back to the original if it can't be decoded
		path, mime = small, "image/png"
	}

	if useGemini {
		img, err := os.ReadFile(path)
		if err == nil {
			fields, gerr := ocr.Gemini(r.Context(), s.cfg.GeminiAPIKey, s.cfg.GeminiModel, kind, mime, img)
			if gerr == nil {
				writeJSON(w, 200, M{"success": true, "engine": "gemini", "fields": fields})
				return
			}
			log.Println("ocr: gemini failed, falling back to tesseract:", gerr)
		}
		if !ocr.Available() {
			fail(w, 502, "Could not read the image")
			return
		}
	}

	select {
	case ocrSlots <- struct{}{}:
		defer func() { <-ocrSlots }()
	default:
		fail(w, 429, "Busy, please try again in a moment")
		return
	}
	text, err := ocr.Text(r.Context(), path)
	if err != nil {
		fail(w, 502, "Could not read the image")
		return
	}
	writeJSON(w, 200, M{"success": true, "engine": "tesseract", "fields": ocr.Parse(kind, text)})
}
