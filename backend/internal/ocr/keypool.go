package ocr

import (
	"context"
	"errors"
	"log"
	"sync"
	"time"
)

// Errors that mean "this key can't be used right now, try the next one".
var (
	errQuota  = errors.New("gemini: quota or rate limit reached")
	errBadKey = errors.New("gemini: key rejected")

	// ErrAllKeysExhausted is returned when every configured key is out of quota or invalid.
	ErrAllKeysExhausted = errors.New("all Gemini API keys are exhausted")
)

const (
	quotaCooldown  = 5 * time.Minute // retry a quota-limited key after this long (per-minute limits clear sooner)
	badKeyCooldown = time.Hour
)

// KeyPool tries Gemini API keys in order. When a key hits its usage limit (HTTP 429) or is rejected,
// it is skipped for a while and the next key is used; once its cooldown ends it becomes the first choice again.
type KeyPool struct {
	keys  []string
	model string
	mu    sync.Mutex
	until []time.Time // per key: skip until this time
}

func NewKeyPool(keys []string, model string) *KeyPool {
	return &KeyPool{keys: keys, model: model, until: make([]time.Time, len(keys))}
}

func (p *KeyPool) Len() int { return len(p.keys) }

// Extract reads the card, switching to the next key when one is exhausted.
func (p *KeyPool) Extract(ctx context.Context, kind, mime string, image []byte) (map[string]string, error) {
	for i, key := range p.keys {
		if p.blocked(i) {
			continue
		}
		fields, err := geminiOnce(ctx, key, p.model, kind, mime, image)
		switch {
		case err == nil:
			return fields, nil
		case errors.Is(err, errQuota):
			log.Printf("ocr: gemini key #%d hit its limit, switching to the next key", i+1)
			p.block(i, quotaCooldown)
		case errors.Is(err, errBadKey):
			log.Printf("ocr: gemini key #%d was rejected (check it), switching to the next key", i+1)
			p.block(i, badKeyCooldown)
		default:
			return nil, err // not a key problem (network, bad answer...) - another key won't help
		}
	}
	return nil, ErrAllKeysExhausted
}

func (p *KeyPool) blocked(i int) bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	return time.Now().Before(p.until[i])
}

func (p *KeyPool) block(i int, d time.Duration) {
	p.mu.Lock()
	p.until[i] = time.Now().Add(d)
	p.mu.Unlock()
}
