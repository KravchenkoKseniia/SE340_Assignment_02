# AFTER - materialized view

## The problem (Q5 - `items_products_join`)

```sql
SELECT p.category, COUNT(*) AS items_sold,
       SUM(oi.quantity * oi.unit_price) AS revenue
FROM order_items oi
JOIN products p ON oi.product_id = p.product_id
GROUP BY p.category
ORDER BY revenue DESC;
```

Every call scans all `order_items` rows, joins `products`, and aggregates
- just to return 5 rows (one per category). The result changes slowly, so recomputing the full scan on every call is wasteful.

## The fix

A materialized view stores the pre-aggregated result on disk:

```sql
CREATE MATERIALIZED VIEW mv_category_revenue AS
SELECT p.category,
       COUNT(*)                          AS items_sold,
       SUM(oi.quantity * oi.unit_price)  AS revenue
FROM order_items oi
JOIN products p ON oi.product_id = p.product_id
GROUP BY p.category;

CREATE UNIQUE INDEX idx_mv_category_revenue ON mv_category_revenue (category);
```

The unique index on `category` lets us use `REFRESH MATERIALIZED VIEW CONCURRENTLY`,
which rebuilds the view without blocking readers.

## Before / After

| | Before (live query) | After (materialized view) |
|---|---:|---:|
| Execution time | 77.91 ms | 0.031 ms |
| Buffers | 2,341 | 1 |
| Plan | Parallel Seq Scan 359k -> Hash Join -> Aggregate -> Sort | Seq Scan 5 rows -> Sort |

### Before plan (full)
```text
Sort  (cost=8674.77..8674.78 rows=5 width=47) (actual time=76.370..77.851 rows=5.00 loops=1)
  Output: p.category, (count(*)), (sum(((oi.quantity)::numeric * oi.unit_price)))
  Sort Key: (sum(((oi.quantity)::numeric * oi.unit_price))) DESC
  Sort Method: quicksort  Memory: 25kB
  Buffers: shared hit=2341
  ->  Finalize GroupAggregate  (cost=8673.65..8674.71 rows=5 width=47) (actual time=76.358..77.843 rows=5.00 loops=1)
        Output: p.category, count(*), sum(((oi.quantity)::numeric * oi.unit_price))
        Group Key: p.category
        Buffers: shared hit=2341
        ->  Gather Merge  (cost=8673.65..8674.57 rows=8 width=47) (actual time=76.348..77.830 rows=10.00 loops=1)
              Output: p.category, (PARTIAL count(*)), (PARTIAL sum(((oi.quantity)::numeric * oi.unit_price)))
              Workers Planned: 1
              Workers Launched: 1
              Buffers: shared hit=2341
              ->  Sort  (cost=7673.64..7673.66 rows=5 width=47) (actual time=73.906..73.909 rows=5.00 loops=2)
                    Output: p.category, (PARTIAL count(*)), (PARTIAL sum(((oi.quantity)::numeric * oi.unit_price)))
                    Sort Key: p.category
                    Sort Method: quicksort  Memory: 25kB
                    Buffers: shared hit=2341
                    Worker 0:  actual time=71.625..71.627 rows=5.00 loops=1
                      Sort Method: quicksort  Memory: 25kB
                      Buffers: shared hit=1142
                    ->  Partial HashAggregate  (cost=7673.52..7673.59 rows=5 width=47) (actual time=73.885..73.888 rows=5.00 loops=2)
                          Output: p.category, PARTIAL count(*), PARTIAL sum(((oi.quantity)::numeric * oi.unit_price))
                          Group Key: p.category
                          Batches: 1  Memory Usage: 32kB
                          Buffers: shared hit=2333
                          Worker 0:  actual time=71.590..71.593 rows=5.00 loops=1
                            Batches: 1  Memory Usage: 32kB
                            Buffers: shared hit=1134
                          ->  Hash Join  (cost=66.00..5029.07 rows=211556 width=17) (actual time=0.490..37.230 rows=179822.50 loops=2)
                                Output: p.category, oi.quantity, oi.unit_price
                                Inner Unique: true
                                Hash Cond: (oi.product_id = p.product_id)
                                Buffers: shared hit=2333
                                Worker 0:  actual time=0.607..36.604 rows=174741.00 loops=1
                                  Buffers: shared hit=1134
                                ->  Parallel Seq Scan on public.order_items oi  (cost=0.00..4406.56 rows=211556 width=14) (actual time=0.007..8.503 rows=179822.50 loops=2)
                                      Output: oi.order_item_id, oi.order_id, oi.product_id, oi.quantity, oi.unit_price
                                      Buffers: shared hit=2291
                                      Worker 0:  actual time=0.009..8.996 rows=174741.00 loops=1
                                        Buffers: shared hit=1113
                                ->  Hash  (cost=41.00..41.00 rows=2000 width=11) (actual time=0.463..0.463 rows=2000.00 loops=2)
                                      Output: p.category, p.product_id
                                      Buckets: 2048  Batches: 1  Memory Usage: 104kB
                                      Buffers: shared hit=42
                                      Worker 0:  actual time=0.582..0.582 rows=2000.00 loops=1
                                        Buffers: shared hit=21
                                      ->  Seq Scan on public.products p  (cost=0.00..41.00 rows=2000 width=11) (actual time=0.035..0.232 rows=2000.00 loops=2)
                                            Output: p.category, p.product_id
                                            Buffers: shared hit=42
                                            Worker 0:  actual time=0.060..0.302 rows=2000.00 loops=1
                                              Buffers: shared hit=21
Query Identifier: -4903131155092333173
Planning:
  Buffers: shared hit=12
Planning Time: 0.207 ms
Execution Time: 77.910 ms
```

### After plan
```text
Sort  (cost=1.11..1.12 rows=5 width=26) (actual time=0.017..0.017 rows=5.00 loops=1)
"  Output: category, items_sold, revenue"
  Sort Key: mv_category_revenue.revenue DESC
  Sort Method: quicksort  Memory: 25kB
  Buffers: shared hit=1
  ->  Seq Scan on public.mv_category_revenue  (cost=0.00..1.05 rows=5 width=26) (actual time=0.010..0.011 rows=5.00 loops=1)
"        Output: category, items_sold, revenue"
        Buffers: shared hit=1
Query Identifier: 540000305974396500
Planning:
  Buffers: shared hit=34 read=2 dirtied=1
Planning Time: 0.367 ms
Execution Time: 0.031 ms
```

---
This md file was generated by Claude Code from the EXPLAIN output to make it more readable and easier to view :D