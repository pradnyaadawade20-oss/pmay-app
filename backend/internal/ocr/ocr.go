// Package ocr reads Aadhaar / PAN card images with the Tesseract CLI and extracts form fields.
package ocr

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"strings"
	"time"
)

// Available reports whether the tesseract binary is installed.
func Available() bool { _, err := exec.LookPath("tesseract"); return err == nil }

// Text runs tesseract on an image file and returns the recognised text.
func Text(ctx context.Context, imagePath string) (string, error) {
	if !Available() {
		return "", errors.New("tesseract is not installed")
	}
	ctx, cancel := context.WithTimeout(ctx, 80*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "tesseract", imagePath, "stdout", "-l", lang(), "--psm", "6")
	cmd.Env = append(os.Environ(), "OMP_THREAD_LIMIT=1") // 1 thread: more only slows down small servers
	out, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("tesseract: %w", err)
	}
	return string(out), nil
}

// lang is "eng" by default; set OCR_LANGS=eng+hin if the Hindi data pack is installed.
func lang() string {
	if v := os.Getenv("OCR_LANGS"); v != "" {
		return v
	}
	return "eng"
}

var (
	reAadhaar = regexp.MustCompile(`\b([2-9]\d{3})\s?(\d{4})\s?(\d{4})\b`)
	rePAN     = regexp.MustCompile(`\b[A-Z]{5}[0-9]{4}[A-Z]\b`)
	reDate    = regexp.MustCompile(`\b(\d{2})\s?[/\-.]\s?(\d{2})\s?[/\-.]\s?((?:19|20)\d{2})\b`)
	rePIN     = regexp.MustCompile(`\b\d{6}\b`)
	reRel     = regexp.MustCompile(`(?i)\b([SDWC])\s*/\s*O\s*[:;.,-]?\s*([A-Za-z][A-Za-z .]+)`)
)

// Parse extracts form fields from OCR text. kind: aadhar_front | aadhar_back | pan_front.
// Only fields that were found are returned; the keys match the registration form.
func Parse(kind, text string) map[string]string {
	f := map[string]string{}
	lines := cleanLines(text)
	switch kind {
	case "aadhar_front":
		if n := findAadhaar(text); n != "" {
			f["aadharNumber"] = n
		}
		dobIdx := -1
		for i, l := range lines {
			if m := reDate.FindStringSubmatch(l); m != nil {
				f["dateOfBirth"] = m[3] + "-" + m[2] + "-" + m[1]
				dobIdx = i
				break
			}
		}
		for i := dobIdx - 1; i >= 0 && dobIdx > 0; i-- { // the name is printed just above the DOB
			if n := asName(lines[i]); n != "" && !isNoise(lines[i]) {
				splitName(f, n)
				break
			}
		}
	case "aadhar_back":
		if n := findAadhaar(text); n != "" {
			f["aadharNumber"] = n
		}
		if m := reRel.FindStringSubmatch(text); m != nil {
			name := asName(strings.SplitN(m[2], "\n", 2)[0])
			if name != "" {
				if strings.EqualFold(m[1], "W") {
					f["spouseName"] = name
				} else if strings.EqualFold(m[1], "S") || strings.EqualFold(m[1], "D") {
					f["fatherName"] = name
				}
			}
		}
		if addr := address(text); addr != "" {
			f["fullAddress"] = addr
		}
	case "pan_front":
		if p := rePAN.FindString(strings.ToUpper(text)); p != "" {
			f["panNumber"] = p
		}
		if m := reDate.FindStringSubmatch(text); m != nil {
			f["dateOfBirth"] = m[3] + "-" + m[2] + "-" + m[1]
		}
		for i, l := range lines {
			low := strings.ToLower(l)
			switch {
			case strings.Contains(low, "father") && i+1 < len(lines):
				if n := asName(lines[i+1]); n != "" {
					f["fatherName"] = titleCase(n)
				}
			case strings.HasPrefix(low, "name") && !strings.Contains(low, "father") && i+1 < len(lines):
				if n := asName(lines[i+1]); n != "" {
					splitName(f, titleCase(n))
				}
			}
		}
	}
	return f
}

func cleanLines(text string) []string {
	var out []string
	for _, l := range strings.Split(strings.ReplaceAll(text, "\r", ""), "\n") {
		if l = strings.TrimSpace(l); l != "" {
			out = append(out, l)
		}
	}
	return out
}

var reName = regexp.MustCompile(`^[A-Za-z][A-Za-z .']{2,}$`)

// asName returns the line as a person name if it looks like one (letters only, 2+ chars).
func asName(l string) string {
	l = strings.TrimSpace(strings.Trim(l, "|:;,._- "))
	if !reName.MatchString(l) || len(strings.Fields(l)) > 5 {
		return ""
	}
	return strings.Join(strings.Fields(l), " ")
}

func isNoise(l string) bool {
	low := strings.ToLower(l)
	for _, w := range []string{"government", "india", "authority", "unique", "identification", "aadhaar", "male", "female", "dob", "birth", "income", "tax", "department", "permanent", "account"} {
		if strings.Contains(low, w) {
			return true
		}
	}
	return false
}

func titleCase(s string) string {
	w := strings.Fields(strings.ToLower(s))
	for i := range w {
		w[i] = strings.ToUpper(w[i][:1]) + w[i][1:]
	}
	return strings.Join(w, " ")
}

func splitName(f map[string]string, n string) {
	p := strings.Fields(n)
	if len(p) == 0 {
		return
	}
	f["firstName"] = p[0]
	if len(p) > 1 {
		f["lastName"] = p[len(p)-1]
	}
}

// findAadhaar returns the first 12-digit number that passes the Verhoeff checksum (rejects OCR misreads).
func findAadhaar(text string) string {
	for _, m := range reAadhaar.FindAllStringSubmatch(text, -1) {
		if n := m[1] + m[2] + m[3]; verhoeff(n) {
			return n
		}
	}
	return ""
}

func address(text string) string {
	label := "address"
	i := strings.Index(strings.ToLower(text), label)
	if i < 0 {
		label = "पता" // Hindi "pata" (address)
		i = strings.Index(text, label)
	}
	if i < 0 {
		return ""
	}
	t := text[i+len(label):]
	t = strings.TrimLeft(t, ": \n")
	if loc := rePIN.FindStringIndex(t); loc != nil {
		t = t[:loc[1]]
	} else if len(t) > 200 {
		t = t[:200]
	}
	return strings.Join(strings.Fields(strings.ReplaceAll(t, "\n", " ")), " ")
}

var (
	vD = [10][10]int{{0, 1, 2, 3, 4, 5, 6, 7, 8, 9}, {1, 2, 3, 4, 0, 6, 7, 8, 9, 5}, {2, 3, 4, 0, 1, 7, 8, 9, 5, 6}, {3, 4, 0, 1, 2, 8, 9, 5, 6, 7},
		{4, 0, 1, 2, 3, 9, 5, 6, 7, 8}, {5, 9, 8, 7, 6, 0, 4, 3, 2, 1}, {6, 5, 9, 8, 7, 1, 0, 4, 3, 2}, {7, 6, 5, 9, 8, 2, 1, 0, 4, 3},
		{8, 7, 6, 5, 9, 3, 2, 1, 0, 4}, {9, 8, 7, 6, 5, 4, 3, 2, 1, 0}}
	vP = [8][10]int{{0, 1, 2, 3, 4, 5, 6, 7, 8, 9}, {1, 5, 7, 6, 2, 8, 3, 0, 9, 4}, {5, 8, 0, 3, 7, 9, 6, 1, 4, 2}, {8, 9, 1, 6, 0, 4, 3, 5, 2, 7},
		{9, 4, 5, 3, 1, 2, 6, 8, 7, 0}, {4, 2, 8, 6, 5, 7, 3, 9, 0, 1}, {2, 7, 9, 3, 8, 0, 6, 4, 1, 5}, {7, 0, 4, 6, 9, 1, 3, 2, 5, 8}}
)

func verhoeff(num string) bool {
	c := 0
	for i := 0; i < len(num); i++ {
		d := int(num[len(num)-1-i] - '0')
		c = vD[c][vP[i%8][d]]
	}
	return c == 0
}
