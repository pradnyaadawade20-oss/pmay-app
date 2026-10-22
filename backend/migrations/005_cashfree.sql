-- Payment gateway columns (Cashfree). Old razorpay_* columns are kept for existing rows.
ALTER TABLE payments ADD COLUMN IF NOT EXISTS gateway TEXT;
ALTER TABLE payments ADD COLUMN IF NOT EXISTS gateway_order_id TEXT;
ALTER TABLE payments ADD COLUMN IF NOT EXISTS gateway_payment_id TEXT;
CREATE INDEX IF NOT EXISTS payments_gateway_order_idx ON payments (gateway_order_id);
UPDATE payments SET gateway='razorpay', gateway_order_id=razorpay_order_id, gateway_payment_id=razorpay_payment_id
  WHERE razorpay_order_id IS NOT NULL AND gateway IS NULL;