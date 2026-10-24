-- Payments recorded by an admin from a cheque photo (payment proof kept for future reference)
ALTER TABLE payments ADD COLUMN IF NOT EXISTS payment_mode TEXT;      -- e.g. 'cheque'
ALTER TABLE payments ADD COLUMN IF NOT EXISTS cheque_number TEXT;
ALTER TABLE payments ADD COLUMN IF NOT EXISTS cheque_bank TEXT;
ALTER TABLE payments ADD COLUMN IF NOT EXISTS note TEXT;
ALTER TABLE payments ADD COLUMN IF NOT EXISTS recorded_by UUID;       -- admin who uploaded the proof

INSERT INTO document_settings (document_type, max_size_mb, label)
VALUES ('cheque_photo', 5, 'Cheque Photo')
ON CONFLICT (document_type) DO NOTHING;
