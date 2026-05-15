-- 04-indexes-explain/lab.sql
SET search_path = app, public;

-- WHY: refresh stats so EXPLAIN row estimates are realistic. Cheap, idempotent.
ANALYZE;

------------------------------------------------------------
-- 1. EXPLAIN (ANALYZE, BUFFERS) on a known-fast query
------------------------------------------------------------
-- WHY: a selective predicate on an indexed column should use Index Scan.
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title
FROM posts
WHERE author_id = 7
ORDER BY created_at DESC
LIMIT 5;

------------------------------------------------------------
-- 2. Same query without using the (author_id, created_at DESC) index
------------------------------------------------------------
-- WHY: disable index scan to force a Seq Scan + Sort and compare cost/time.
-- Restore enable_indexscan = on afterwards.
SET enable_indexscan = off;
SET enable_bitmapscan = off;
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title
FROM posts
WHERE author_id = 7
ORDER BY created_at DESC
LIMIT 5;
RESET enable_indexscan;
RESET enable_bitmapscan;

------------------------------------------------------------
-- 3. Bitmap Index Scan: multiple selective predicates
------------------------------------------------------------
-- WHY: when more than one index could be useful, the planner often combines
-- bitmaps with BitmapAnd / BitmapOr.
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title
FROM posts
WHERE author_id IN (3, 9, 17)
  AND created_at > now() - interval '6 months';

------------------------------------------------------------
-- 4. Index Only Scan: covering index
------------------------------------------------------------
-- WHY: build a covering index, then verify the planner avoids the heap.
CREATE INDEX IF NOT EXISTS posts_author_cover_idx
    ON posts (author_id, created_at DESC)
    INCLUDE (title);

ANALYZE posts;

EXPLAIN (ANALYZE, BUFFERS)
SELECT title
FROM posts
WHERE author_id = 7
ORDER BY created_at DESC
LIMIT 5;
-- Look for "Index Only Scan" and "Heap Fetches: 0" in the output.

------------------------------------------------------------
-- 5. Partial index
------------------------------------------------------------
-- WHY: most queries ask for published posts only. A partial index is smaller
-- and the planner uses it when the WHERE clause matches.
-- (posts_published_at_idx is already created by the seed.)
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title FROM posts
WHERE published_at IS NOT NULL
ORDER BY published_at DESC
LIMIT 20;

------------------------------------------------------------
-- 6. Expression index
------------------------------------------------------------
-- WHY: without this index, `lower(email)` is non-sargable and forces a Seq Scan.
CREATE INDEX IF NOT EXISTS users_lower_email_idx ON users ((lower(email)));
ANALYZE users;

EXPLAIN (ANALYZE, BUFFERS)
SELECT id FROM users WHERE lower(email) = 'user7@example.com';

------------------------------------------------------------
-- 7. GIN on text[]
------------------------------------------------------------
-- WHY: posts_tags_gin_idx (seeded) supports @> for membership.
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title
FROM posts
WHERE tags @> ARRAY['pgvector'];

------------------------------------------------------------
-- 8. GIN on jsonb with jsonb_path_ops
------------------------------------------------------------
-- WHY: products_attrs_gin_idx supports the @> containment operator.
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, name, attributes
FROM products
WHERE attributes @> '{"color":"red"}'::jsonb;

------------------------------------------------------------
-- 9. Sargability rewrite
------------------------------------------------------------
-- WHY: function on indexed column breaks index use; rewrite as a range.
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM posts
WHERE date_trunc('month', created_at) = date_trunc('month', timestamptz '2024-06-10');

EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM posts
WHERE created_at >= timestamptz '2024-06-01'
  AND created_at <  timestamptz '2024-07-01';

------------------------------------------------------------
-- 10. Inspect index usage on the live cluster
------------------------------------------------------------
-- WHY: low idx_scan over a long observation window means the index is unused
-- and a candidate for removal.
SELECT schemaname, relname, indexrelname, idx_scan, idx_tup_read, idx_tup_fetch
FROM pg_stat_user_indexes
WHERE schemaname = 'app'
ORDER BY idx_scan;

------------------------------------------------------------
-- 11. Estimation problem demo
------------------------------------------------------------
-- WHY: a predicate the planner cannot reason about precisely.
EXPLAIN (ANALYZE)
SELECT count(*) FROM posts
WHERE length(title) > 25 AND length(title) < 40;
-- The 'rows=' estimate may be far off the 'actual rows=' because the planner
-- has no per-row length statistic by default. Multivariate or per-column
-- statistics can help in real systems.
