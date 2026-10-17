package ocr

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func validAadhaar() string {
	for d := 0; d < 10; d++ {
		n := "99991234567" + string(rune('0'+d))
		if verhoeff(n) {
			return n
		}
	}
	return ""
}

func TestGemini(t *testing.T) {
	aad := validAadhaar()
	var gotKey, gotBody string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotKey = r.Header.Get("x-goog-api-key")
		b := make([]byte, 4096)
		n, _ := r.Body.Read(b)
		gotBody = string(b[:n])
		w.Write([]byte(`{"candidates":[{"content":{"parts":[{"text":"{\"firstName\":\"RAMESH\",\"lastName\":\"patil\",\"dateOfBirth\":\"1988-05-12\",\"aadharNumber\":\"` + aad + `\",\"panNumber\":\"X\",\"fullAddress\":\"<script>\"}"}]}}]}`))
	}))
	defer srv.Close()
	old := geminiBase
	geminiBase = srv.URL
	defer func() { geminiBase = old }()

	f, err := geminiOnce(context.Background(), "k123", "", "aadhar_front", "image/png", []byte("img"))
	if err != nil {
		t.Fatal(err)
	}
	if gotKey != "k123" || !strings.Contains(gotBody, "inline_data") {
		t.Fatalf("request: key=%q body=%q", gotKey, gotBody)
	}
	if f["firstName"] != "Ramesh" || f["lastName"] != "Patil" || f["dateOfBirth"] != "1988-05-12" || f["aadharNumber"] != aad {
		t.Fatalf("fields: %v", f)
	}
	if _, bad := f["panNumber"]; bad {
		t.Fatalf("pan must not be returned for aadhaar front: %v", f)
	}
}

func TestSanitizeRejectsBadValues(t *testing.T) {
	f := sanitize("pan_front", map[string]any{"panNumber": "abcde1234f", "dateOfBirth": "12/05/1988", "firstName": "Ra<m>esh", "fatherName": "Suresh"})
	if f["panNumber"] != "ABCDE1234F" || f["fatherName"] != "Suresh" {
		t.Fatalf("%v", f)
	}
	if _, ok := f["dateOfBirth"]; ok {
		t.Fatal("bad date accepted")
	}
	if _, ok := f["firstName"]; ok {
		t.Fatal("bad name accepted")
	}
	if g := sanitize("aadhar_front", map[string]any{"aadharNumber": "123456789012"}); len(g) != 0 {
		t.Fatalf("bad checksum accepted: %v", g)
	}
}
