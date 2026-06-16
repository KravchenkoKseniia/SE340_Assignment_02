CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- to improve Q1
CREATE INDEX IF NOT EXISTS idx_customers_email ON customers USING gin (email gin_trgm_ops);

-- to improve Q2
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders (status);

-- to improve Q4
CREATE INDEX IF NOT EXISTS idx_events_time_cust_type ON customer_events_wide (event_time, customer_id, event_type);
CREATE INDEX IF NOT EXISTS idx_events_time_cust_type ON customer_events (event_time, customer_id, event_type);
-- to improve Q6
CREATE INDEX IF NOT EXISTS idx_events_customer_time ON customer_events_wide (customer_id, event_time);

ANALYZE customers;
ANALYZE orders;
ANALYZE customer_events_wide;