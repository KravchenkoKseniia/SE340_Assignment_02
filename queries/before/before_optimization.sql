EXPLAIN (ANALYZE, VERBOSE, COSTS, SETTINGS, BUFFERS, WAL, TIMING, SUMMARY)
SELECT *
FROM customers
WHERE email LIKE '%gmail%';

EXPLAIN (ANALYZE, VERBOSE, COSTS, SETTINGS, BUFFERS, WAL, TIMING, SUMMARY)
SELECT *
FROM orders
WHERE delivery_city LIKE '%a%' AND status = 'paid';

EXPLAIN (ANALYZE, VERBOSE, COSTS, SETTINGS, BUFFERS, WAL, TIMING, SUMMARY)
SELECT
    c.customer_id,
    c.full_name,
    COUNT(o.order_id) AS orders_count,
    SUM(o.total_amount) AS revenue
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
WHERE c.status = 'active'
GROUP BY c.customer_id, c.full_name
ORDER BY revenue DESC
LIMIT 100;

EXPLAIN (ANALYZE, VERBOSE, COSTS, SETTINGS, BUFFERS, WAL, TIMING, SUMMARY)
SELECT
    customer_id,
    event_type,
    COUNT(*) AS events_count,
    MAX(event_time) AS last_event_time
FROM customer_events_wide
WHERE event_time >= NOW() - INTERVAL '180 days'
GROUP BY customer_id, event_type
ORDER BY events_count DESC
LIMIT 200;

EXPLAIN (ANALYZE, VERBOSE, COSTS, SETTINGS, BUFFERS, WAL, TIMING, SUMMARY)
SELECT
    p.category,
    COUNT(*) AS items_sold,
    SUM(oi.quantity * oi.unit_price) AS revenue
FROM order_items oi
JOIN products p ON oi.product_id = p.product_id
GROUP BY p.category
ORDER BY revenue DESC;

EXPLAIN (ANALYZE, VERBOSE, COSTS, SETTINGS, BUFFERS, WAL, TIMING, SUMMARY)
SELECT COUNT(*)
FROM customers c
JOIN orders o ON o.customer_id = c.customer_id
JOIN customer_events_wide e ON e.customer_id = c.customer_id
WHERE c.status IN ('active', 'inactive') AND e.event_time >= NOW() - INTERVAL '90 days';