-- The mortgage receipt must be approved by an admin before the registration is completed.
ALTER TABLE applicants ADD COLUMN IF NOT EXISTS mortgage_status TEXT NOT NULL DEFAULT 'pending'
  CHECK (mortgage_status IN ('pending','submitted','accepted','rejected'));
ALTER TABLE applicants ADD COLUMN IF NOT EXISTS mortgage_reason TEXT;

-- already completed applicants were approved under the old flow
UPDATE applicants SET mortgage_status='accepted'
 WHERE registration_stage='stage_10_completed' AND mortgage_status='pending';
-- applicants who already uploaded a receipt but are still at stage 9 wait for review
UPDATE applicants SET mortgage_status='submitted'
 WHERE registration_stage='stage_9_mortgage' AND mortgage_receipt_path IS NOT NULL AND mortgage_status='pending';
