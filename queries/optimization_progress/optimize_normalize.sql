CREATE TABLE customer_events AS
SELECT event_id, customer_id, event_type, event_time
FROM customer_events_wide;

ALTER TABLE customer_events ADD PRIMARY KEY (event_id);
CREATE INDEX idx_core_customer_time ON customer_events (customer_id, event_time);

CREATE TABLE customer_events_details AS
SELECT event_id, source, campaign, device, browser, os, ip_address, page_url, referrer, utm_source, utm_medium, utm_campaign,
attr_01, attr_02, attr_03, attr_04, attr_05, attr_06, attr_07, attr_08, attr_09, attr_10
FROM customer_events_wide;

ALTER TABLE customer_events_details ADD PRIMARY KEY (event_id);

ALTER TABLE customer_events_details ADD CONSTRAINT fk_detail_core FOREIGN KEY (event_id) REFERENCES customer_events (event_id);

ANALYZE customer_events;
ANALYZE customer_events_details;


EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT customer_id, event_type, COUNT(*) AS events_count,
       MAX(event_time) AS last_event_time
FROM customer_events
WHERE event_time >= NOW() - INTERVAL '180 days'
GROUP BY customer_id, event_type
ORDER BY events_count DESC
LIMIT 200;


EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT COUNT(*)
FROM customers c
WHERE c.status IN ('active', 'inactive')
  AND EXISTS (
    SELECT 1 FROM orders o
    WHERE o.customer_id = c.customer_id
)
  AND EXISTS (
    SELECT 1 FROM customer_events e
    WHERE e.customer_id = c.customer_id
      AND e.event_time >= NOW() - INTERVAL '90 days'
);