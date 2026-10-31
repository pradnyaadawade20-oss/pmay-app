package app

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"io"
	"log"
	"mime/multipart"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"pmay-backend/internal/ocr"
)

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
// Reads the card with Google Gemini (GEMINI_API_KEY ... GEMINI_API_KEY_3) and returns the form fields it found.
func (s *Server) ocrExtract(w http.ResponseWriter, r *http.Request) {
	if len(s.cfg.GeminiAPIKeys) == 0 {
		fail(w, 503, "OCR is not configured on this server")
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
	if len(files) == 0 {
		fail(w, 400, "An image up to 5MB is required")
		return
	}
	fields, code, msg := s.docFields(r.Context(), kind, files[0])
	if code != 0 {
		fail(w, code, msg)
		return
	}
	writeJSON(w, 200, M{"success": true, "fields": fields})
}

// Results are remembered by file content, so the scan done while filling the form and the check done on
// submit always see the same answer (and a registration does not cost a second round of Gemini calls).
const (
	ocrCacheTTL = 6 * time.Hour
	ocrCacheMax = 300
)

type ocrCacheEntry struct {
	fields map[string]string
	at     time.Time
}

var ocrCache = struct {
	sync.Mutex
	m map[string]ocrCacheEntry
}{m: map[string]ocrCacheEntry{}}

func copyFields(in map[string]string) map[string]string {
	out := make(map[string]string, len(in))
	for k, v := range in {
		out[k] = v
	}
	return out
}

func ocrCacheGet(key string) (map[string]string, bool) {
	ocrCache.Lock()
	defer ocrCache.Unlock()
	e, ok := ocrCache.m[key]
	if !ok || time.Since(e.at) > ocrCacheTTL {
		delete(ocrCache.m, key)
		return nil, false
	}
	return copyFields(e.fields), true
}

func ocrCachePut(key string, fields map[string]string) {
	ocrCache.Lock()
	defer ocrCache.Unlock()
	if len(ocrCache.m) >= ocrCacheMax {
		for k, e := range ocrCache.m {
			if time.Since(e.at) > ocrCacheTTL {
				delete(ocrCache.m, k)
			}
		}
		if len(ocrCache.m) >= ocrCacheMax {
			ocrCache.m = map[string]ocrCacheEntry{}
		}
	}
	ocrCache.m[key] = ocrCacheEntry{fields: copyFields(fields), at: time.Now()}
}

// docFields reads one Aadhaar / PAN image (kind = aadhar_front | aadhar_back | pan_front).
// On failure it returns an HTTP status and a message that is safe to show to the user.
func (s *Server) docFields(ctx context.Context, kind string, fh *multipart.FileHeader) (map[string]string, int, string) {
	if fh.Size > 5<<20 {
		return nil, 400, "An image up to 5MB is required"
	}
	ext := strings.ToLower(filepath.Ext(fh.Filename))
	if ext != ".jpg" && ext != ".jpeg" && ext != ".png" {
		return nil, 400, "Only JPG or PNG images can be read"
	}
	src, err := fh.Open()
	if err != nil {
		return nil, 400, "Cannot read file"
	}
	defer src.Close()
	raw, err := io.ReadAll(io.LimitReader(src, 5<<20+1))
	if err != nil || len(raw) > 5<<20 {
		return nil, 400, "Cannot read file"
	}
	sum := sha256.Sum256(raw)
	key := kind + ":" + hex.EncodeToString(sum[:])
	if f, ok := ocrCacheGet(key); ok {
		return f, 0, ""
	}

	tmp, err := os.CreateTemp("", "ocr-*"+ext)
	if err != nil {
		return nil, 500, "Server error"
	}
	defer os.Remove(tmp.Name())
	_, err = tmp.Write(raw)
	tmp.Close()
	if err != nil {
		return nil, 500, "Server error"
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
	img, err := os.ReadFile(path)
	if err != nil {
		return nil, 500, "Server error"
	}
	fields, err := s.geminiPool().Extract(ctx, kind, mime, img)
	if err != nil {
		log.Println("ocr: gemini failed:", err)
		if errors.Is(err, ocr.ErrAllKeysExhausted) {
			return nil, 503, "Document reading is busy right now. Please type the details."
		}
		return nil, 502, "Could not read the image"
	}
	if len(fields) > 0 { // an unreadable photo is not remembered, so a retry really retries
		ocrCachePut(key, fields)
	}
	return fields, 0, ""
}

var (
	poolOnce sync.Once
	pool     *ocr.KeyPool
)

// geminiPool is shared by all requests so a key's cooldown is remembered between scans.
func (s *Server) geminiPool() *ocr.KeyPool {
	poolOnce.Do(func() { pool = ocr.NewKeyPool(s.cfg.GeminiAPIKeys, s.cfg.GeminiModel) })
	return pool
}