-- Bank documents depend on the applicant's profile: salaried / business / nip.
-- Files are stored in loan_details.docs as {doc_key: path}; the old fixed columns stay for old rows.
ALTER TABLE loan_details ADD COLUMN IF NOT EXISTS profile_type TEXT CHECK (profile_type IN ('salaried','business','nip'));
ALTER TABLE loan_details ADD COLUMN IF NOT EXISTS docs JSONB NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE loan_details ADD COLUMN IF NOT EXISTS docs_complete BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE loan_details ADD COLUMN IF NOT EXISTS docs_count INT NOT NULL DEFAULT 0;

-- backfill rows created with the old 5 fixed documents
UPDATE loan_details SET
  docs_count = (CASE WHEN upi_statement_path IS NOT NULL THEN 1 ELSE 0 END + CASE WHEN itr_year1_path IS NOT NULL THEN 1 ELSE 0 END +
                CASE WHEN itr_year2_path IS NOT NULL THEN 1 ELSE 0 END + CASE WHEN itr_year3_path IS NOT NULL THEN 1 ELSE 0 END +
                CASE WHEN bank_statement_path IS NOT NULL THEN 1 ELSE 0 END),
  docs_complete = (upi_statement_path IS NOT NULL AND itr_year1_path IS NOT NULL AND itr_year2_path IS NOT NULL
                   AND itr_year3_path IS NOT NULL AND bank_statement_path IS NOT NULL)
WHERE profile_type IS NULL;