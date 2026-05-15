# Module 04 — Challenges

Run each with `EXPLAIN (ANALYZE, BUFFERS)` and inspect the chosen plan.

## 1. Find every index on `app.posts`. List name, definition, size.

<details><summary>Solution</summary>

```sql
SELECT
    i.indexrelid::regclass AS index_name,
    pg_get_indexdef(i.indexrelid) AS definition,
    pg_size_pretty(pg_relation_size(i.indexrelid)) AS size
FROM pg_index i
WHERE i.indrelid = 'app.posts'::regclass;
```
</details>

## 2. Make `SELECT * FROM app.posts WHERE author_id = 7 ORDER BY published_at DESC LIMIT 5` use an Index Scan. What index do you need?

<details><summary>Solution</summary>

A composite `(author_id, published_at DESC)`. The existing `posts_author_created_idx` is on `created_at`, so the planner cannot avoid a sort. Add:
```sql
CREATE INDEX posts_author_published_idx
ON app.posts (author_id, published_at DESC)
WHERE published_at IS NOT NULL;
```
Then run `ANALYZE`. Expect a `Limit` over `Index Scan` using the new index, with `actual time` ≈ 0 ms.
</details>

## 3. Build a GIN index that accelerates `WHERE attributes @> '{"specs":{"warranty_years":2}}'`. Verify it's used.

<details><summary>Solution</summary>

The seed already created `products_attrs_gin_idx` with `jsonb_path_ops`, which supports `@>` exactly. Run:
```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM app.products
WHERE attributes @> '{"specs":{"warranty_years":2}}'::jsonb;
```
Expect a `Bitmap Index Scan` on `products_attrs_gin_idx`. `jsonb_ops` supports more operators (`?`, `?|`, `?&`) but is larger and slower to build; `jsonb_path_ops` is enough when you only need `@>`.
</details>

## 4. Compute the percentage of dead tuples in `app.posts`. Should you `VACUUM`?

<details><summary>Solution</summary>

```sql
SELECT n_live_tup, n_dead_tup,
       round(100.0 * n_dead_tup / nullif(n_live_tup + n_dead_tup, 0), 2) AS dead_pct
FROM pg_stat_user_tables
WHERE relname = 'posts' AND schemaname = 'app';
```
General rule: if `dead_pct > 20%` and autovacuum hasn't caught up, run `VACUUM (ANALYZE) app.posts;`. For heavy bloat, `VACUUM FULL` reclaims space but takes an exclusive lock.
</details>

## 5. Why does this query use a Seq Scan instead of `posts_author_created_idx`?
```sql
EXPLAIN SELECT * FROM app.posts WHERE author_id + 0 = 7;
```

<details><summary>Solution</summary>

`author_id + 0` is a non-sargable expression: the planner cannot prove `author_id + 0 = 7` is equivalent to `author_id = 7`, so it cannot use the btree on `author_id`. Rewrite the predicate without the function/operator, or build an expression index on `(author_id + 0)` (don't — fix the query).
</details>

## 6. Without changing the query, force the planner to use a Seq Scan and compare time.

<details><summary>Solution</summary>

```sql
SET enable_indexscan = off;
SET enable_bitmapscan = off;
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM app.posts WHERE author_id = 7;
RESET enable_indexscan; RESET enable_bitmapscan;
```
Use the `enable_*` flags only as a diagnostic — they are not a production tool.
</details>

## 7. Create extended statistics on `(author_id, published_at)` to help the planner with correlated predicates.

<details><summary>Solution</summary>

```sql
CREATE STATISTICS posts_author_pub_stats (ndistinct, dependencies)
ON author_id, published_at FROM app.posts;
ANALYZE app.posts;
```
Inspect with `SELECT * FROM pg_stats_ext;`. Reference: <https://www.postgresql.org/docs/17/planner-stats.html#PLANNER-STATS-EXTENDED>.
</details>

## 8. Identify any unused indexes in the `app` schema (assume the seed has been running long enough that `idx_scan = 0` is meaningful — for the lab, you can pretend).

<details><summary>Solution</summary>

```sql
SELECT schemaname, relname, indexrelname, idx_scan, pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes
WHERE schemaname = 'app' AND idx_scan = 0
ORDER BY pg_relation_size(indexrelid) DESC;
```
Drop only after multi-week observation in production; right after seeding everything looks unused.
</details>

## 9. Will an index on `(status)` help `WHERE status = 'paid'` on `app.orders`?

<details><summary>Solution</summary>

Probably not for the seed. Roughly 5 of 8 orders are `paid` (>60%), so the planner will pick a `Seq Scan` because reading the heap directly is cheaper than scattered index lookups for that selectivity. A rule of thumb: btree indexes pay off below ~10% selectivity. For low-cardinality columns, a partial index `WHERE status = 'pending'` (or whatever the rare value is) is often more useful.
</details>

## 10. Build a covering index for `SELECT title, published_at FROM app.posts WHERE author_id = ? ORDER BY published_at DESC LIMIT N` and prove it produces an `Index Only Scan` with `Heap Fetches: 0`.

<details><summary>Solution</summary>

```sql
CREATE INDEX posts_author_cover2_idx
ON app.posts (author_id, published_at DESC)
INCLUDE (title)
WHERE published_at IS NOT NULL;

VACUUM (ANALYZE) app.posts;   -- updates the visibility map

EXPLAIN (ANALYZE, BUFFERS)
SELECT title, published_at FROM app.posts
WHERE author_id = 7 AND published_at IS NOT NULL
ORDER BY published_at DESC
LIMIT 5;
```
Look for `Index Only Scan` and `Heap Fetches: 0`. If `Heap Fetches > 0`, the visibility map isn't fully clean — recently-updated tuples force a heap visit.
</details>
