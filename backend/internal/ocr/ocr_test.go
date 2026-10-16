package ocr

import "testing"

func TestParse(t *testing.T) {
	// 2345 6789 0124 is not Verhoeff-valid; 4999 1234 5671 style numbers are built below via check digit search.
	good := ""
	for d := 0; d < 10; d++ {
		n := "99991234567" + string(rune('0'+d))
		if verhoeff(n) {
			good = n
		}
	}
	front := "Government of India\nRamesh Suresh Patil\nDOB: 12/05/1988\nMALE\n" + good[:4] + " " + good[4:8] + " " + good[8:] + "\n"
	f := Parse("aadhar_front", front)
	if f["aadharNumber"] != good || f["dateOfBirth"] != "1988-05-12" || f["firstName"] != "Ramesh" || f["lastName"] != "Patil" {
		t.Fatalf("front: %v", f)
	}
	back := "Address:\nS/O: Suresh Patil, Flat 4,\nKalyan West, Thane,\nMaharashtra - 421301\n"
	b := Parse("aadhar_back", back)
	if b["fatherName"] != "Suresh Patil" || b["fullAddress"] == "" {
		t.Fatalf("back: %v", b)
	}
	pan := "INCOME TAX DEPARTMENT\nPermanent Account Number\nABCDE1234F\nName\nRAMESH SURESH PATIL\nFather's Name\nSURESH PATIL\nDate of Birth\n12/05/1988\n"
	p := Parse("pan_front", pan)
	if p["panNumber"] != "ABCDE1234F" || p["firstName"] != "Ramesh" || p["fatherName"] != "Suresh Patil" || p["dateOfBirth"] != "1988-05-12" {
		t.Fatalf("pan: %v", p)
	}
	if h := Parse("aadhar_back", "पता: स्थान, कल्याण 421301\n"); h["fullAddress"] == "" {
		t.Fatalf("hindi address: %v", h)
	}
	if got := Parse("aadhar_front", "1234 5678 9012"); got["aadharNumber"] != "" {
		t.Fatalf("invalid checksum accepted: %v", got)
	}
}
