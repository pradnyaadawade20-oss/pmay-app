package app

import (
	"strings"
	"testing"
)

var (
	tFront = map[string]string{"firstName": "Pratiksha", "lastName": "Yadav", "dateOfBirth": "2005-09-24", "aadharNumber": "234123412346"}
	tBack  = map[string]string{"aadharNumber": "234123412346", "fatherName": "Parbati", "fullAddress": "S/O Parbati Yadav, 12 Gandhi Road, Andheri East, Mumbai, Maharashtra 400069"}
	tPAN   = map[string]string{"panNumber": "ABCDE1234F", "firstName": "Pratiksha", "lastName": "Yadav", "fatherName": "Parbati", "dateOfBirth": "2005-09-24"}
)

func goodForm() docForm {
	return docForm{First: "Pratiksha", Last: "Yadav", Father: "Parbati", DOB: "2005-09-24",
		Address: "S/O Parbati Yadav, 12 Gandhi Road, Andheri East, Mumbai, Maharashtra 400069",
		Aadhar:  "234123412346", PAN: "ABCDE1234F"}
}

func TestDocMismatch(t *testing.T) {
	cases := []struct {
		name   string
		mutate func(f *docForm)
		front  map[string]string
		back   map[string]string
		pan    map[string]string
		want   string // substring of the error; "" = must pass
	}{
		{"everything matches", func(f *docForm) {}, tFront, tBack, tPAN, ""},
		{"name case/spacing is ignored", func(f *docForm) { f.First = " PRATIKSHA "; f.Last = "yadav" }, tFront, tBack, tPAN, ""},
		{"aadhaar number edited", func(f *docForm) { f.Aadhar = "234123412347" }, tFront, tBack, tPAN, "Aadhaar number does not match"},
		{"PAN number edited", func(f *docForm) { f.PAN = "ZZZZZ9999Z" }, tFront, tBack, tPAN, "PAN number does not match"},
		{"same Aadhaar image uploaded as PAN (no PAN readable)", func(f *docForm) {}, tFront, tBack, map[string]string{"aadharNumber": "234123412346"}, "PAN number from the PAN card"},
		{"aadhaar image unreadable", func(f *docForm) {}, map[string]string{}, tBack, tPAN, "Aadhaar number from the Aadhaar front"},
		{"front and back are different cards", func(f *docForm) {}, tFront, map[string]string{"aadharNumber": "999988887777"}, tPAN, "different Aadhaar numbers"},
		{"first name edited", func(f *docForm) { f.First = "Rahul" }, tFront, tBack, tPAN, "name does not match"},
		{"last name edited", func(f *docForm) { f.Last = "Sharma" }, tFront, tBack, tPAN, "name does not match"},
		{"dob edited", func(f *docForm) { f.DOB = "2000-01-01" }, tFront, tBack, tPAN, "Date of birth"},
		{"father name edited", func(f *docForm) { f.Father = "Sunita" }, tFront, tBack, tPAN, "Father's name"},
		{"father name with surname added is rejected", func(f *docForm) { f.Father = "Parbati Yadav" }, tFront, tBack, tPAN, "Father's name"},
		{"father not on any document: free text allowed", func(f *docForm) { f.Father = "Anything" }, tFront, map[string]string{"aadharNumber": "234123412346"}, map[string]string{"panNumber": "ABCDE1234F"}, ""},
		{"address with extra words is fine", func(f *docForm) { f.Address += ", near Station" }, tFront, tBack, tPAN, ""},
		{"address reordered/punctuation is fine", func(f *docForm) {
			f.Address = "12 Gandhi Road Andheri East Mumbai Maharashtra 400069 S/O Parbati Yadav"
		}, tFront, tBack, tPAN, ""},
		{"address PIN changed", func(f *docForm) { f.Address = strings.Replace(f.Address, "400069", "411001", 1) }, tFront, tBack, tPAN, "Address"},
		{"address replaced", func(f *docForm) { f.Address = "Somewhere else entirely, Pune 411001" }, tFront, tBack, tPAN, "Address"},
		{"spouse edited", func(f *docForm) { f.Spouse = "Amit" }, tFront, map[string]string{"aadharNumber": "234123412346", "spouseName": "Rohit"}, tPAN, "Spouse"},
		{"name only on PAN is enough", func(f *docForm) {}, map[string]string{"aadharNumber": "234123412346"}, tBack, tPAN, ""},
	}
	for _, c := range cases {
		f := goodForm()
		c.mutate(&f)
		got := docMismatch(f, c.front, c.back, c.pan)
		if c.want == "" && got != "" {
			t.Errorf("%s: expected pass, got %q", c.name, got)
		}
		if c.want != "" && !strings.Contains(got, c.want) {
			t.Errorf("%s: expected error containing %q, got %q", c.name, c.want, got)
		}
	}
}

func TestOCRCache(t *testing.T) {
	ocrCachePut("k1", map[string]string{"a": "b"})
	got, ok := ocrCacheGet("k1")
	if !ok || got["a"] != "b" {
		t.Fatal("cache miss")
	}
	got["a"] = "changed" // callers must not be able to modify the stored copy
	if again, _ := ocrCacheGet("k1"); again["a"] != "b" {
		t.Fatal("cache returned a shared map")
	}
	if _, ok := ocrCacheGet("missing"); ok {
		t.Fatal("unexpected hit")
	}
}