-- Bank Loan step needs admin approval: the receipt the applicant uploads is only "submitted" until an admin
-- accepts it (then the applicant moves to the mortgage stage) or rejects it (applicant uploads again).
ALTER TABLE applicants ADD COLUMN IF NOT EXISTS bank_loan_status TEXT NOT NULL DEFAULT 'pending'
  CHECK (bank_loan_status IN ('pending','submitted','accepted','rejected'));
ALTER TABLE applicants ADD COLUMN IF NOT EXISTS bank_loan_reason TEXT;

-- Applicants who already got past the bank loan step under the old automatic flow count as approved.
UPDATE applicants SET bank_loan_status='accepted'
 WHERE registration_stage IN ('stage_9_mortgage','stage_10_completed') AND bank_loan_status='pending';
