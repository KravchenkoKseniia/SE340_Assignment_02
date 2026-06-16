-- Claude helped me to look more closely here
-- SELECT relname, n_dead_tup, n_live_tup, last_vacuum, last_autovacuum, last_analyze
-- FROM pg_stat_all_tables
-- WHERE relname = 'customer_events_wide';

VACUUM (ANALYZE) customer_events_wide;

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
