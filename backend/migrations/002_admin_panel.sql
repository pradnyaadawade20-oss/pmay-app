-- Admin panel support
ALTER TABLE user_roles ADD COLUMN IF NOT EXISTS assigned_at TIMESTAMPTZ DEFAULT now();

ALTER TABLE document_settings ADD COLUMN IF NOT EXISTS label TEXT;
ALTER TABLE document_settings ADD COLUMN IF NOT EXISTS ai_validation BOOLEAN NOT NULL DEFAULT false;
UPDATE document_settings SET label = CASE document_type
  WHEN 'passport_photo' THEN 'Passport Photo'  WHEN 'pan_front' THEN 'PAN Card'
  WHEN 'aadhar_front' THEN 'Aadhaar Front'     WHEN 'aadhar_back' THEN 'Aadhaar Back'
  WHEN 'membership_proof' THEN 'Membership Proof' WHEN 'agreement_signed' THEN 'Signed Agreement'
  WHEN 'bank_statement' THEN 'Bank Statement'  WHEN 'upi_statement' THEN 'UPI Statement'
  WHEN 'itr' THEN 'ITR'                        WHEN 'bank_loan_receipt' THEN 'Bank Loan Receipt'
  WHEN 'mortgage_receipt' THEN 'Mortgage Receipt' ELSE document_type END
WHERE label IS NULL;
