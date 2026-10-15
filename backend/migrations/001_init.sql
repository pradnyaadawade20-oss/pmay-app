-- PMAY backend schema (standalone Postgres, no Supabase dependency)
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- roles: super_admin | admin | finance | allotment_manager | auditor
CREATE TABLE user_roles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('super_admin','admin','finance','allotment_manager','auditor')),
  display_name TEXT,
  UNIQUE(user_id, role)
);

CREATE SEQUENCE applicant_id_seq START 1;
CREATE SEQUENCE payment_receipt_seq START 1;

CREATE TABLE applicants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  unique_id TEXT UNIQUE NOT NULL DEFAULT ('PMAY-' || LPAD(nextval('applicant_id_seq')::TEXT, 5, '0')),
  user_id UUID UNIQUE REFERENCES users(id) ON DELETE CASCADE NOT NULL,
  first_name TEXT NOT NULL,
  last_name TEXT NOT NULL,
  father_name TEXT,
  spouse_name TEXT,
  date_of_birth DATE,
  age INT,
  occupation TEXT,
  blood_group TEXT,
  full_address TEXT,
  aadhar_number TEXT UNIQUE NOT NULL,
  pan_number TEXT UNIQUE NOT NULL,
  email TEXT NOT NULL,
  email_verified BOOLEAN DEFAULT false,
  phone TEXT UNIQUE NOT NULL,
  phone_verified BOOLEAN DEFAULT false,
  has_co_applicant BOOLEAN DEFAULT false,
  co_applicant_name TEXT, co_applicant_relation TEXT, co_applicant_dob DATE,
  co_applicant_aadhar TEXT, co_applicant_pan TEXT, co_applicant_phone TEXT,
  handling_admin_id UUID, handling_admin_selected_at TIMESTAMPTZ,
  registration_stage TEXT NOT NULL DEFAULT 'stage_1_registered'
    CHECK (registration_stage IN ('stage_1_registered','stage_3_payment','stage_4_allotment','stage_5_agreement',
      'stage_6_agreement_receipt','stage_7_bank_document','stage_8_bank_loan','stage_9_mortgage','stage_10_completed')),
  -- stage 2 = admin validation
  stage_2_status TEXT DEFAULT 'pending' CHECK (stage_2_status IN ('pending','accepted','rejected')),
  stage_2_reason TEXT,
  stage_2_verified_at TIMESTAMPTZ, stage_2_verified_by UUID,
  stage_3_payment_status TEXT DEFAULT 'pending',
  stage_3_payment_method TEXT, stage_3_completed_at TIMESTAMPTZ,
  -- stage 4 status column in the original = agreement receipt review
  stage_4_status TEXT DEFAULT 'pending' CHECK (stage_4_status IN ('pending','accepted','rejected')),
  stage_4_reason TEXT,
  stage_5_allotment_id UUID,
  allotment_date TIMESTAMPTZ,
  agreement_signed_at TIMESTAMPTZ, agreement_receipt_path TEXT,
  bank_loan_form_uploaded_at TIMESTAMPTZ, bank_loan_receipt_path TEXT,
  mortgage_deed_signed_at TIMESTAMPTZ, mortgage_receipt_path TEXT,
  registration_completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now(), updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE units (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  unit_number TEXT UNIQUE NOT NULL,
  wing TEXT NOT NULL, tower TEXT NOT NULL, floor INT NOT NULL,
  status TEXT DEFAULT 'available' CHECK (status IN ('available','reserved','allotted')),
  allocated_to UUID REFERENCES applicants(id), allocated_at TIMESTAMPTZ,
  building_name TEXT, carpet_area_sqm NUMERIC(10,2), rera_carpet_area NUMERIC(10,2),
  consideration_amount NUMERIC(12,2) DEFAULT 2550000,
  parking_number TEXT, parking_type TEXT, parking_area_sqm NUMERIC(10,2)
);
-- 110 units: floors 1-22, 5 per floor (same as original seed)
INSERT INTO units (unit_number,floor,wing,tower,building_name,carpet_area_sqm,rera_carpet_area,parking_number,parking_type,parking_area_sqm)
SELECT f || LPAD(u::text,2,'0'), f, 'A', 'Tower A', 'DABBEWALA & CHARMAKAR BUILDING', 26.94, 26.94,
       'P-A-' || f || LPAD(u::text,2,'0'), 'covered', 12.5
FROM generate_series(1,22) f CROSS JOIN generate_series(1,5) u;

CREATE TABLE uploads (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  applicant_id UUID REFERENCES applicants(id) ON DELETE CASCADE NOT NULL,
  upload_type TEXT NOT NULL, file_name TEXT NOT NULL, file_path TEXT NOT NULL, file_size BIGINT,
  uploaded_by UUID REFERENCES users(id), uploaded_at TIMESTAMPTZ DEFAULT now(),
  validation_bypassed BOOLEAN DEFAULT false
);

CREATE TABLE payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  applicant_id UUID REFERENCES applicants(id) ON DELETE CASCADE NOT NULL,
  amount NUMERIC(12,2) NOT NULL,
  payment_method TEXT NOT NULL CHECK (payment_method IN ('online','offline')),
  payment_status TEXT DEFAULT 'pending' CHECK (payment_status IN ('pending','completed','failed')),
  payment_stage TEXT DEFAULT 'booking',
  razorpay_order_id TEXT, razorpay_payment_id TEXT, razorpay_signature TEXT,
  offline_receipt_path TEXT, receipt_number TEXT, payment_date DATE,
  verified_by UUID, created_at TIMESTAMPTZ DEFAULT now(), updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE loan_details (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  applicant_id UUID UNIQUE REFERENCES applicants(id) ON DELETE CASCADE NOT NULL,
  upi_statement_path TEXT, itr_year1_path TEXT, itr_year2_path TEXT, itr_year3_path TEXT, bank_statement_path TEXT,
  loan_status TEXT DEFAULT 'pending' CHECK (loan_status IN ('pending','approved','rejected')),
  verification_notes TEXT, verified_by UUID, verified_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now(), updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE otp_verifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT, phone TEXT,
  otp_code TEXT NOT NULL, otp_type TEXT NOT NULL CHECK (otp_type IN ('email','phone')),
  expires_at TIMESTAMPTZ NOT NULL, verified_at TIMESTAMPTZ,
  attempts INT DEFAULT 0, created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX ON otp_verifications (email); CREATE INDEX ON otp_verifications (phone);

CREATE TABLE stage_2_daily_counter (date DATE PRIMARY KEY DEFAULT CURRENT_DATE, count INT NOT NULL DEFAULT 0 CHECK (count BETWEEN 0 AND 1000));

CREATE TABLE document_settings (
  document_type TEXT PRIMARY KEY, max_size_mb NUMERIC NOT NULL DEFAULT 5,
  allowed_extensions TEXT[] DEFAULT ARRAY['jpg','jpeg','png','pdf']
);
INSERT INTO document_settings (document_type,max_size_mb) VALUES
 ('passport_photo',2),('pan_front',5),('aadhar_front',5),('aadhar_back',5),('membership_proof',5),
 ('agreement_signed',5),('bank_statement',5),('upi_statement',5),('itr',5),('bank_loan_receipt',5),('mortgage_receipt',5);

CREATE TABLE project_settings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_name TEXT DEFAULT 'DABBEWALA & CHARMAKAR BUILDING',
  rera_registration_no TEXT DEFAULT 'P52000054498',
  developer_name TEXT DEFAULT 'PRIYANKA HOME REALTORS PVT LTD',
  developer_address TEXT DEFAULT 'Office No. A-1 & A-2, 1st Floor, Swastik Residency CHS, Survey No 65, Hissa No 4, Village Ambivali, Taluka Kalyan, District Thane - 421102',
  possession_date DATE DEFAULT '2028-12-31',
  bank_name TEXT DEFAULT 'Yes Bank Ltd', bank_branch TEXT DEFAULT 'Kalyan Branch',
  bank_account_no TEXT, bank_ifsc TEXT,
  booking_amount NUMERIC(12,2) DEFAULT 25000, total_cost NUMERIC(12,2) DEFAULT 2550000
);
INSERT INTO project_settings DEFAULT VALUES;

CREATE TABLE audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), user_id UUID, action TEXT NOT NULL,
  entity_type TEXT NOT NULL, entity_id UUID, details JSONB, created_at TIMESTAMPTZ DEFAULT now()
);
