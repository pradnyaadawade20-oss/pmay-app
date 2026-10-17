package ocr

import (
	"image"
	"image/color"
	"image/jpeg"
	"image/png"
	"os"
)

const maxSide = 1400 // phone photos are 3000-4000px; OCR on that is slow and not more accurate for ID cards

// Prepare converts the image to grayscale and shrinks it so its longest side is at most maxSide,
// writing a PNG to dst. This keeps uploads to Gemini small and fast.
func Prepare(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	img, _, err := image.Decode(in)
	if err != nil {
		return err
	}
	b := img.Bounds()
	w, h := b.Dx(), b.Dy()
	scale := 1
	for w/scale > maxSide || h/scale > maxSide {
		scale++
	}
	nw, nh := w/scale, h/scale
	out := image.NewGray(image.Rect(0, 0, nw, nh))
	for y := 0; y < nh; y++ { // box filter: average each scale x scale block
		for x := 0; x < nw; x++ {
			var sum, n uint32
			for dy := 0; dy < scale; dy++ {
				for dx := 0; dx < scale; dx++ {
					g := color.GrayModel.Convert(img.At(b.Min.X+x*scale+dx, b.Min.Y+y*scale+dy)).(color.Gray)
					sum += uint32(g.Y)
					n++
				}
			}
			out.SetGray(x, y, color.Gray{Y: uint8(sum / n)})
		}
	}
	f, err := os.Create(dst)
	if err != nil {
		return err
	}
	defer f.Close()
	return png.Encode(f, out)
}

var _ = jpeg.Decode // register the JPEG decoder for image.Decode
