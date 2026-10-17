// Package ocr reads Aadhaar / PAN card images with Google Gemini and returns validated form fields.
package ocr

import (
	"regexp"
	"strings"
)

var rePAN = regexp.MustCompile(`\b[A-Z]{5}[0-9]{4}[A-Z]\b`)

func titleCase(s string) string {
	w := strings.Fields(strings.ToLower(s))
	for i := range w {
		w[i] = strings.ToUpper(w[i][:1]) + w[i][1:]
	}
	return strings.Join(w, " ")
}

var (
	vD = [10][10]int{{0, 1, 2, 3, 4, 5, 6, 7, 8, 9}, {1, 2, 3, 4, 0, 6, 7, 8, 9, 5}, {2, 3, 4, 0, 1, 7, 8, 9, 5, 6}, {3, 4, 0, 1, 2, 8, 9, 5, 6, 7},
		{4, 0, 1, 2, 3, 9, 5, 6, 7, 8}, {5, 9, 8, 7, 6, 0, 4, 3, 2, 1}, {6, 5, 9, 8, 7, 1, 0, 4, 3, 2}, {7, 6, 5, 9, 8, 2, 1, 0, 4, 3},
		{8, 7, 6, 5, 9, 3, 2, 1, 0, 4}, {9, 8, 7, 6, 5, 4, 3, 2, 1, 0}}
	vP = [8][10]int{{0, 1, 2, 3, 4, 5, 6, 7, 8, 9}, {1, 5, 7, 6, 2, 8, 3, 0, 9, 4}, {5, 8, 0, 3, 7, 9, 6, 1, 4, 2}, {8, 9, 1, 6, 0, 4, 3, 5, 2, 7},
		{9, 4, 5, 3, 1, 2, 6, 8, 7, 0}, {4, 2, 8, 6, 5, 7, 3, 9, 0, 1}, {2, 7, 9, 3, 8, 0, 6, 4, 1, 5}, {7, 0, 4, 6, 9, 1, 3, 2, 5, 8}}
)

// verhoeff reports whether the digit string passes the Verhoeff checksum (used by Aadhaar numbers).
func verhoeff(num string) bool {
	c := 0
	for i := 0; i < len(num); i++ {
		d := int(num[len(num)-1-i] - '0')
		c = vD[c][vP[i%8][d]]
	}
	return c == 0
}
