-- Simple Mortgage Deed: extra details that are not stored anywhere else.
-- Purely additive (new tables only). Existing tables and flow are untouched.
CREATE TABLE IF NOT EXISTS mortgage_deed_details (
  applicant_id UUID PRIMARY KEY REFERENCES applicants(id) ON DELETE CASCADE,
  data JSONB NOT NULL DEFAULT '{}'::jsonb,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Project-level property schedule (district, village, survey no., boundaries ...): one row, same for every flat.
CREATE TABLE IF NOT EXISTS mortgage_schedule (
  id INT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  data JSONB NOT NULL DEFAULT '{}'::jsonb,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
INSERT INTO mortgage_schedule (id, data) VALUES (1, '{}'::jsonb) ON CONFLICT (id) DO NOTHING;