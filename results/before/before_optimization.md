# BEFORE Optimization

Data: customers = 20000 · products = 2000 · orders = 120000 · order_items = 359645 · customer_events_wide = 200000

## EXPLAIN options reference (just to save time to not open the docs)

`EXPLAIN (option, option, ...) <query>` controls what the plan shows:

| Option | What it does |
|--------|--------------|
| `ANALYZE` | Actually runs the query and shows **real** timings and row counts (`actual time`, `rows`, `loops`), not just estimates. Note: it executes the query, so it really writes for `UPDATE`/`INSERT`/`DELETE`. |
| `VERBOSE` | Adds extra detail: the `Output:` column list per node, schema-qualified names, and the `Query Identifier`. |
| `COSTS` | Shows the planner's estimated `cost=start..total` and estimated `rows`/`width` (on by default). |
| `SETTINGS` | Lists non-default planner settings in effect (e.g. `search_path`, `work_mem`) that influenced the plan. |
| `BUFFERS` | Shows block (8 KB) usage: `shared hit` = served from cache, `read` = read from disk, `dirtied`/`written` = blocks modified. The real I/O cost of the query. |
| `WAL` | Shows Write-Ahead-Log generated (records, bytes) — useful for measuring the cost of write statements. |
| `TIMING` | Per-node `actual time` measurements (on by default with `ANALYZE`; can be turned off to reduce overhead). |
| `SUMMARY` | Adds `Planning Time` and `Execution Time` totals at the end (on by default with `ANALYZE`). |

## Summary table

| # | Query | Execution Time | Access method | Buffers | Rows Removed by Filter | Main symptom |
|---|-------|---------------:|---------------|--------:|-----------------------:|--------------|
| Q1 | search_customer_by_email | 2.12 ms | Seq Scan (customers) | 333 hit | 20,000 | leading-wildcard `LIKE '%...%'` + `SELECT *` |
| Q2 | orders_by_city_and_status | 12.20 ms | Seq Scan (orders) | 1,225 hit | 103,449 | no index on `status`, wildcard `LIKE` |
| Q3 | heavy_join | 26.67 ms | 2× Seq Scan + Hash Join | 1,561 hit | 13,337 | Seq Scan on `customers.status`, full scan of orders |
| Q4 | events_aggregation | **106.06 ms** | Seq Scan (events 200k) | 8,981 hit | 103,099 | no index on `event_time`, wide table |
| Q5 | items_products_join | 67.86 ms | Parallel Seq Scan (359k) | 2,341 hit | - | full-table aggregation, no cached result |
| Q6 | cartesian_pressure | 58.12 ms | 3× Seq Scan + Hash Joins | 10,872 hit | 76,120 | triple JOIN, row multiplication, no indexes |

> Note on `Buffers`: all values are `shared hit` (served from PostgreSQL's cache), with **no** `read` (disk). The data set is small enough to fit fully in RAM and was already warm from previous runs, so a cold first run would show some `read=...` instead. Either way the number of blocks **touched** is the same — the cache only hides the disk cost, it does not reduce the work. `hit` still counts as real work the query has to do.

```sql
SELECT *
FROM customers
WHERE email LIKE '%gmail%';
```

```text
Seq Scan on public.customers  (cost=0.00..585.27 rows=2 width=96) (actual time=2.086..2.087 rows=0.00 loops=1)
  Output: customer_id, full_name, email, phone, city, country, created_at, status
  Filter: (customers.email ~~ '%gmail%'::text)
  Rows Removed by Filter: 20000
  Buffers: shared hit=333
Query Identifier: -5422201427205123227
Planning:
  Buffers: shared hit=105
Planning Time: 0.289 ms
Execution Time: 2.116 ms
```

What we have here:
- `Seq Scan` - we read all rows of the table and apply the filter to each one.
- `Rows Removed by Filter: 20000`, `rows=0` - the whole table was scanned and no row returned. So the whole work is wasted.
- `LIKE '%gmail%'` - starts with `%`, a B-tree index is not be used.
- `SELECT *` - pulls all 8 columns (`width=96`) when usually only 1–2 are needed.
---

## Q2 - `orders_by_city_and_status`

```sql
SELECT *
FROM orders
WHERE delivery_city LIKE '%a%'
  AND status = 'paid';
```

```text
Seq Scan on public.orders  (cost=0.00..3026.47 rows=17310 width=50) (actual time=0.007..11.638 rows=16551.00 loops=1)
  Output: order_id, customer_id, order_date, status, total_amount, payment_method, delivery_city
  Filter: ((orders.delivery_city ~~ '%a%'::text) AND (orders.status = 'paid'::text))
  Rows Removed by Filter: 103449
  Buffers: shared hit=1225
Query Identifier: 1511564414729942011
Planning:
  Buffers: shared hit=60
Planning Time: 0.165 ms
Execution Time: 12.200 ms
```

What we have here
- Full scan of `orders` table; 103449 discarded, 16551 returned.
- No index on `orders.status` - the status filter cannot narrow the search.
- `delivery_city LIKE '%a%'` - another filter that only simulates load (the `a` is in almost every city name, so it does not filter much) but forces a full scan

---

## Q3 - `heavy_join`

```sql
SELECT c.customer_id, c.full_name,
       COUNT(o.order_id) AS orders_count,
       SUM(o.total_amount) AS revenue
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
WHERE c.status = 'active'
GROUP BY c.customer_id, c.full_name
ORDER BY revenue DESC
LIMIT 100;
```

```text
Limit  (cost=4051.65..4051.90 rows=100 width=58) (actual time=26.592..26.603 rows=100.00 loops=1)
  Output: c.customer_id, c.full_name, (count(o.order_id)), (sum(o.total_amount))
  Buffers: shared hit=1561
  ->  Sort  (cost=4051.65..4068.46 rows=6723 width=58) (actual time=26.591..26.596 rows=100.00 loops=1)
        Sort Key: (sum(o.total_amount)) DESC
        Sort Method: top-N heapsort  Memory: 36kB
        Buffers: shared hit=1561
        ->  HashAggregate  (cost=3710.67..3794.71 rows=6723 width=58) (actual time=24.564..25.666 rows=6647.00 loops=1)
              Group Key: c.customer_id
              Batches: 1  Memory Usage: 2833kB
              Buffers: shared hit=1558
              ->  Hash Join  (cost=669.31..3410.62 rows=40007 width=28) (actual time=2.091..17.944 rows=39978.00 loops=1)
                    Inner Unique: true
                    Hash Cond: (o.customer_id = c.customer_id)
                    Buffers: shared hit=1558
                    ->  Seq Scan on public.orders o  (cost=0.00..2425.98 rows=120098 width=14) (actual time=0.003..5.072 rows=120000.00 loops=1)
                          Buffers: shared hit=1225
                    ->  Hash  (cost=585.27..585.27 rows=6723 width=18) (actual time=2.074..2.074 rows=6663.00 loops=1)
                          Buckets: 8192  Batches: 1  Memory Usage: 391kB
                          Buffers: shared hit=333
                          ->  Seq Scan on public.customers c  (cost=0.00..585.27 rows=6723 width=18) (actual time=0.004..1.515 rows=6663.00 loops=1)
                                Filter: (c.status = 'active'::text)
                                Rows Removed by Filter: 13337
                                Buffers: shared hit=333
Query Identifier: -3404305087332701794
Planning Time: 0.271 ms
Execution Time: 26.666 ms
```

What we have here
- `customers` is scanned fully, leaving 6663 rows with `status='active'`
- `orders` is scanned fully (120k), then a Hash Join yields 39978 pairs, followed by aggregation and a top-N sort.
- Seq Scan on `customers.status` - no index
- Seq Scan of all 120k orders - even though the join is on `customer_id` (which is indexed), for a mass aggregation the planner picks a full scan of orders

---

## Q4 - `events_aggregation`

```sql
SELECT customer_id, event_type, COUNT(*) AS events_count,
       MAX(event_time) AS last_event_time
FROM customer_events_wide
WHERE event_time >= NOW() - INTERVAL '180 days'
GROUP BY customer_id, event_type
ORDER BY events_count DESC
LIMIT 200;
```

```text
Limit  (cost=14597.43..14597.93 rows=200 width=27) (actual time=105.988..106.009 rows=200.00 loops=1)
  Output: customer_id, event_type, (count(*)), (max(event_time))
  Buffers: shared hit=8984
  ->  Sort  (cost=14597.43..14648.15 rows=20288 width=27) (actual time=105.988..105.995 rows=200.00 loops=1)
        Sort Key: (count(*)) DESC
        Sort Method: top-N heapsort  Memory: 44kB
        Buffers: shared hit=8984
        ->  HashAggregate  (cost=13517.72..13720.60 rows=20288 width=27) (actual time=95.407..101.423 rows=62157.00 loops=1)
              Group Key: customer_events_wide.customer_id, customer_events_wide.event_type
              Batches: 1  Memory Usage: 6169kB
              Buffers: shared hit=8981
              ->  Seq Scan on public.customer_events_wide  (cost=0.00..12536.30 rows=98142 width=19) (actual time=0.012..75.523 rows=96901.00 loops=1)
                    Output: event_id, customer_id, event_type, event_time, source, campaign, device, browser, os, ip_address, page_url, referrer, utm_source, utm_medium, utm_campaign, attr_01 ... attr_10
                    Filter: (customer_events_wide.event_time >= (now() - '180 days'::interval))
                    Rows Removed by Filter: 103099
                    Buffers: shared hit=8981
Query Identifier: 4981100713785290681
Planning Time: 0.187 ms
Execution Time: 106.063 ms
```

What we have here
- Full scan of `customer_events_wide` table; 102980 discarded by the date filter
- `read=609` - part of the data was read from disk, not from cache. This is the slowest query (134 ms)
- No index on `event_time` - the date range filter is forced to read the whole table
- Wide table (`customer_events_wide`, 24 columns) - every row is heavy, so scanning costs 8375 buffers and triggers disk reads

---

## Q5 - `items_products_join`

```sql
SELECT p.category, COUNT(*) AS items_sold,
       SUM(oi.quantity * oi.unit_price) AS revenue
FROM order_items oi
JOIN products p ON oi.product_id = p.product_id
GROUP BY p.category
ORDER BY revenue DESC;
```

```text
Sort  (cost=8674.77..8674.78 rows=5 width=47) (actual time=66.470..67.820 rows=5.00 loops=1)
  Sort Key: (sum(((oi.quantity)::numeric * oi.unit_price))) DESC
  Sort Method: quicksort  Memory: 25kB
  Buffers: shared hit=2341
  ->  Finalize GroupAggregate  (cost=8673.65..8674.71 rows=5 width=47) (actual time=66.461..67.816 rows=5.00 loops=1)
        Group Key: p.category
        Buffers: shared hit=2341
        ->  Gather Merge  (cost=8673.65..8674.57 rows=8 width=47) (actual time=66.455..67.806 rows=10.00 loops=1)
              Workers Planned: 1
              Workers Launched: 1
              Buffers: shared hit=2341
              ->  Sort  (cost=7673.64..7673.66 rows=5 width=47) (actual time=64.809..64.810 rows=5.00 loops=2)
                    Sort Key: p.category
                    Buffers: shared hit=2341
                    ->  Partial HashAggregate  (cost=7673.52..7673.59 rows=5 width=47) (actual time=64.794..64.795 rows=5.00 loops=2)
                          Group Key: p.category
                          Batches: 1  Memory Usage: 32kB
                          Buffers: shared hit=2333
                          ->  Hash Join  (cost=66.00..5029.07 rows=211556 width=17) (actual time=0.352..33.901 rows=179822.50 loops=2)
                                Inner Unique: true
                                Hash Cond: (oi.product_id = p.product_id)
                                Buffers: shared hit=2333
                                ->  Parallel Seq Scan on public.order_items oi  (cost=0.00..4406.56 rows=211556 width=14) (actual time=0.005..9.030 rows=179822.50 loops=2)
                                      Buffers: shared hit=2291
                                ->  Hash  (cost=41.00..41.00 rows=2000 width=11) (actual time=0.325..0.325 rows=2000.00 loops=2)
                                      Buckets: 2048  Batches: 1  Memory Usage: 104kB
                                      Buffers: shared hit=42
                                      ->  Seq Scan on public.products p  (cost=0.00..41.00 rows=2000 width=11) (actual time=0.016..0.175 rows=2000.00 loops=2)
                                            Buffers: shared hit=42
Query Identifier: -4903131155092333173
Planning Time: 0.469 ms
Execution Time: 67.860 ms
```

What we have here
- The entire `order_items` table is scanned by 2 parallel workers, joined with `products`
- The query returns only 5 rows but grinds through 359644 line items every time

---

## Q6 - `cartesian_pressure`

```sql
SELECT COUNT(*)
FROM customers c
JOIN orders o ON o.customer_id = c.customer_id
JOIN customer_events_wide e ON e.customer_id = c.customer_id
WHERE c.status IN ('active', 'inactive')
  AND e.event_time >= NOW() - INTERVAL '90 days';
```

```text
Finalize Aggregate  (cost=15388.21..15388.22 rows=1 width=8) (actual time=56.322..58.092 rows=1.00 loops=1)
  Output: count(*)
  Buffers: shared hit=10872
  ->  Gather  (cost=15388.00..15388.21 rows=2 width=8) (actual time=56.232..58.089 rows=2.00 loops=1)
        Workers Planned: 1
        Workers Launched: 1
        Buffers: shared hit=10872
        ->  Partial Aggregate  (actual time=54.872..54.873 rows=1.00 loops=2)
              Buffers: shared hit=10872
              ->  Parallel Hash Join  (cost=11433.16..14094.71 rows=117314 width=0) (actual time=37.632..51.258 rows=94650.50 loops=2)
                    Hash Cond: (o.customer_id = c.customer_id)
                    Buffers: shared hit=10872
                    ->  Parallel Seq Scan on public.orders o  (cost=0.00..1931.46 rows=70646 width=4) (actual time=0.004..2.921 rows=60000.00 loops=2)
                          Buffers: shared hit=1225
                    ->  Parallel Hash  (cost=11267.05..11267.05 rows=13289 width=8) (actual time=37.589..37.589 rows=15834.50 loops=2)
                          Buckets: 32768  Batches: 1  Memory Usage: 1536kB
                          Buffers: shared hit=9647
                          ->  Hash Join  (cost=751.82..11267.05 rows=13289 width=8) (actual time=2.930..36.036 rows=15834.50 loops=2)
                                Inner Unique: true
                                Hash Cond: (e.customer_id = c.customer_id)
                                Buffers: shared hit=9647
                                ->  Parallel Seq Scan on public.customer_events_wide e  (cost=0.00..10462.38 rows=20129 width=4) (actual time=0.008..30.278 rows=23880.00 loops=2)
                                      Output: e.event_id, e.customer_id, ... e.attr_10   (all 24 columns)
                                      Filter: (e.event_time >= (now() - '90 days'::interval))
                                      Rows Removed by Filter: 76120
                                      Buffers: shared hit=8981
                                ->  Hash  (cost=585.27..585.27 rows=13324 width=4) (actual time=2.913..2.914 rows=13204.00 loops=2)
                                      Buckets: 16384  Batches: 1  Memory Usage: 593kB
                                      Buffers: shared hit=666
                                      ->  Seq Scan on public.customers c  (cost=0.00..585.27 rows=13324 width=4) (actual time=0.020..2.173 rows=13204.00 loops=2)
                                            Filter: (c.status = ANY ('{active,inactive}'::text[]))
                                            Rows Removed by Filter: 6796
                                            Buffers: shared hit=666
Query Identifier: 2503301008247879905
Planning Time: 0.282 ms
Execution Time: 58.117 ms
```

What we have here
- Three full scans and two hash joins.
- Large I/O: 10357 buffers hit + 515 read and single number is returned :D
- No indexes on `customers.status` or `events.event_time` - both filters run via full scans

---

## Short summary

1. Missing indexes on the filter columns
2. `LIKE '%...%'` - B-tree is not applicable
3. `SELECT *` - unnecessary data volume
4. `customer_events_wide` (24 columns) - expensive scans, disk reads, a candidate for normalization, maybe even partitioning
5. Heavy full aggregations - candidates for materialized views or rewriting
6. Most expensive by amount of work: Q4 (time) and Q6 (I/O) - the primary optimization targets.

I asked Claude to generate this md file to add tables, EXPLAIN cheatsheet to male it more readable and save time on looking up the docs :D