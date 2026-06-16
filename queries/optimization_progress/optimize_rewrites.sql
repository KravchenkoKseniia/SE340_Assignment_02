-- Q1 BEFORE

-- SELECT *
-- FROM customers
-- WHERE email LIKE '%gmail%';

-- AFTER
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT customer_id, full_name, email
FROM customers
WHERE email LIKE '%gmail%';


-- Q2 BEFORE

-- SELECT *
-- FROM orders
-- WHERE delivery_city LIKE '%a%' AND status = 'paid';

-- AFTER
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT order_id, customer_id, total_amount, delivery_city
FROM orders
WHERE status = 'paid';


-- Q6 BEFORE

-- SELECT COUNT(*)
-- FROM customers c
--          JOIN orders o ON o.customer_id = c.customer_id
--          JOIN customer_events_wide e ON e.customer_id = c.customer_id
-- WHERE c.status IN ('active', 'inactive') AND e.event_time >= NOW() - INTERVAL '90 days';

-- AFTER (will update to use customer_events after normalization, but the same logic applies)

EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT COUNT(*)
FROM customers c
WHERE c.status IN ('active', 'inactive')
  AND EXISTS (
        SELECT 1 FROM orders o
        WHERE o.customer_id = c.customer_id
      )
  AND EXISTS (
        SELECT 1 FROM customer_events_wide e
        WHERE e.customer_id = c.customer_id
          AND e.event_time >= NOW() - INTERVAL '90 days'
      );

EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT COUNT(*)
FROM customers c
WHERE c.status IN ('active', 'inactive')
  AND EXISTS (
    SELECT 1 FROM orders o
    WHERE o.customer_id = c.customer_id
)
  AND EXISTS (
    SELECT 1 FROM customer_events_wide e
    WHERE e.customer_id = c.customer_id
      AND e.event_time >= NOW() - INTERVAL '90 days'
);
