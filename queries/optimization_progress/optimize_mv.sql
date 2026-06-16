CREATE MATERIALIZED VIEW mv_category_revenue AS
SELECT p.category, COUNT(*) AS items_sold, SUM(oi.quantity * oi.unit_price)  AS revenue
FROM order_items oi
JOIN products p ON oi.product_id = p.product_id
GROUP BY p.category;

CREATE UNIQUE INDEX idx_mv_category_revenue ON mv_category_revenue (category);

EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT category, items_sold, revenue
FROM mv_category_revenue
ORDER BY revenue DESC;


-- just for fun :)
CREATE EXTENSION IF NOT EXISTS pg_cron;

CREATE OR REPLACE PROCEDURE refresh_mv()
    LANGUAGE plpgsql
AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_category_revenue;
END;
$$;

SELECT cron.schedule('refresh','0 0 * * *', 'CALL refresh_mv()');
SELECT cron.unschedule('refresh');