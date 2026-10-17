package ocr

import (
	"image"
	"image/color"
	"image/png"
	"os"
	"path/filepath"
	"testing"
)

func TestPrepareShrinks(t *testing.T) {
	dir := t.TempDir()
	src := filepath.Join(dir, "big.png")
	img := image.NewRGBA(image.Rect(0, 0, 4000, 3000))
	for y := 0; y < 3000; y += 50 {
		for x := 0; x < 4000; x++ {
			img.Set(x, y, color.Black)
		}
	}
	f, _ := os.Create(src)
	_ = png.Encode(f, img)
	f.Close()
	dst := filepath.Join(dir, "small.png")
	if err := Prepare(src, dst); err != nil {
		t.Fatal(err)
	}
	g, _ := os.Open(dst)
	defer g.Close()
	cfg, _, err := image.DecodeConfig(g)
	if err != nil || cfg.Width > maxSide || cfg.Height > maxSide || cfg.Width < 1000 {
		t.Fatalf("got %v %v", cfg, err)
	}
}
