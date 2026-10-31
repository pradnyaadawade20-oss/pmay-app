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
	errModel  = errors.New("gemini: model not available")

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
		fields, err := p.tryModels(ctx, key, kind, mime, image)
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

// retryDelays: pause before the 2nd and 3rd try of the same model after a temporary problem.
var retryDelays = []time.Duration{time.Second, 3 * time.Second}

// tryModels uses the configured model first, then the built-in fallbacks if Google says the model is unavailable.
// A temporary problem (overloaded, timeout, empty answer) is retried on the same model, and if it keeps failing
// the next model is tried before giving up.
func (p *KeyPool) tryModels(ctx context.Context, key, kind, mime string, image []byte) (map[string]string, error) {
	models := defaultModels
	if p.model != "" {
		models = append([]string{p.model}, defaultModels...)
	}
	var err error
	for _, m := range models {
		var f map[string]string
		for attempt := 0; ; attempt++ {
			f, err = geminiOnce(ctx, key, m, kind, mime, image)
			if !errors.Is(err, ErrTemporary) || attempt >= len(retryDelays) {
				break
			}
			log.Printf("ocr: gemini model %q had a temporary problem (%v), retrying", m, err)
			select {
			case <-time.After(retryDelays[attempt]):
			case <-ctx.Done():
				return nil, err
			}
		}
		switch {
		case errors.Is(err, errModel):
			log.Printf("ocr: gemini model %q is not available, trying the next model", m)
		case errors.Is(err, ErrTemporary):
			log.Printf("ocr: gemini model %q keeps failing (%v), trying the next model", m, err)
		default:
			return f, err
		}
	}
	return nil, err
}