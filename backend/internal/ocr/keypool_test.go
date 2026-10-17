package ocr

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
)

const okBody = `{"candidates":[{"content":{"parts":[{"text":"{\"panNumber\":\"ABCDE1234F\"}"}]}}]}`

func TestKeyPoolSwitchesKeys(t *testing.T) {
	var used []string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		k := r.Header.Get("x-goog-api-key")
		used = append(used, k)
		switch k {
		case "k1", "k2":
			w.WriteHeader(429)
			w.Write([]byte(`{"error":{"status":"RESOURCE_EXHAUSTED"}}`))
		case "k3":
			w.WriteHeader(400)
			w.Write([]byte(`{"error":{"details":[{"reason":"API_KEY_INVALID"}]}}`))
		default:
			w.Write([]byte(okBody))
		}
	}))
	defer srv.Close()
	old := geminiBase
	geminiBase = srv.URL
	defer func() { geminiBase = old }()

	p := NewKeyPool([]string{"k1", "k2", "k3", "k4", "k5"}, "")
	f, err := p.Extract(context.Background(), "pan_front", "image/png", []byte("x"))
	if err != nil || f["panNumber"] != "ABCDE1234F" {
		t.Fatalf("got %v %v", f, err)
	}
	if len(used) != 4 || used[3] != "k4" {
		t.Fatalf("expected k1,k2,k3,k4 in order, got %v", used)
	}
	// next scan must skip the exhausted/invalid keys and go straight to k4
	used = nil
	if _, err := p.Extract(context.Background(), "pan_front", "image/png", []byte("x")); err != nil || len(used) != 1 || used[0] != "k4" {
		t.Fatalf("second scan used %v err %v", used, err)
	}
}

func TestKeyPoolAllExhausted(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(429) }))
	defer srv.Close()
	old := geminiBase
	geminiBase = srv.URL
	defer func() { geminiBase = old }()
	p := NewKeyPool([]string{"a", "b"}, "")
	if _, err := p.Extract(context.Background(), "pan_front", "image/png", []byte("x")); err != ErrAllKeysExhausted {
		t.Fatalf("got %v", err)
	}
}
