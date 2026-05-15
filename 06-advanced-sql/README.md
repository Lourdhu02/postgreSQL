# 06 — Advanced SQL

By the end you can:
1. Use CTEs (`WITH`) and recursive CTEs to structure complex queries and walk hierarchies/graphs.
2. Write window functions for ranking, running totals, lead/lag, and per-group analytics.
3. Use `LATERAL` joins and grouping extensions to express "top-N per group" cleanly.

**Time budget:** 60 min reading + 60 min lab.

## CTEs (WITH)

A common table expression names a subquery you can reference like a table:

```sql
WITH paid AS (
    SELECT * FROM app.orders WHERE status = 'paid'
)
SELECT user_id, sum(total_cents) AS revenue
FROM paid
GROUP BY user_id
ORDER BY revenue DESC
LIMIT 10;
```

| Property | Behavior in PG 12+ |
|----------|--------------------|
| Inlining       | A non-recursive CTE referenced once is **inlined** by default. Force materialization with `MATERIALIZED`; force inlining with `NOT MATERIALIZED`. |
| Multiple refs  | Materialized once and reused. |
| Recursive      | Always materialized; uses `WITH RECURSIVE`. |
| DML allowed    | `INSERT`/`UPDATE`/`DELETE ... RETURNING` can be CTEs. |

```sql
WITH deleted AS (
    DELETE FROM app.comments WHERE created_at < now() - interval '5 years' RETURNING id
)
INSERT INTO app.audit_log (action, payload)
SELECT 'comment_purge', jsonb_build_object('ids', array_agg(id)) FROM deleted;
```

Pre-PG 12, CTEs were an **optimization fence** (always materialized). Knowing this matters when reading legacy advice.

## Recursive CTEs

Walk trees and graphs:

```sql
-- Category tree (path from root to leaf for each node)
WITH RECURSIVE cat_tree AS (
    SELECT id, name, parent_id, ARRAY[name] AS path, 1 AS depth
    FROM app.categories
    WHERE parent_id IS NULL                          -- anchor: roots
  UNION ALL
    SELECT c.id, c.name, c.parent_id, t.path || c.name, t.depth + 1
    FROM app.categories c
    JOIN cat_tree t ON c.parent_id = t.id            -- recursion step
)
SELECT id, name, depth, path FROM cat_tree ORDER BY path;
```

Anatomy:
1. **Anchor query** — non-recursive, seeds the result.
2. **Recursive query** — references the CTE name; runs until it produces no new rows.
3. `UNION` deduplicates intermediates; `UNION ALL` keeps them (faster; safe when impossible to revisit a node — e.g. a strict tree with `parent_id < id`).

For graphs with cycles, add cycle detection (PG 14+ has `CYCLE`):
```sql
WITH RECURSIVE walk AS (
    SELECT id, 1 AS depth FROM app.comments WHERE parent_comment_id IS NULL
    UNION ALL
    SELECT c.id, w.depth + 1
    FROM app.comments c JOIN walk w ON c.parent_comment_id = w.id
) CYCLE id SET is_cycle USING cycle_path
SELECT * FROM walk;
```

## Window functions

A window function computes a value per row using a "window" of related rows, **without collapsing rows** like `GROUP BY` does.

```sql
SELECT id, user_id, total_cents,
       row_number() OVER w  AS rn,
       rank()       OVER w  AS rk,
       dense_rank() OVER w  AS drk,
       sum(total_cents)     OVER w AS running_total
FROM app.orders
WINDOW w AS (PARTITION BY user_id ORDER BY created_at);
```

| Function | Returns |
|----------|---------|
| `row_number()` | 1, 2, 3, ... within partition (gapless) |
| `rank()`       | 1, 2, 2, 4, ... (gaps after ties) |
| `dense_rank()` | 1, 2, 2, 3, ... (no gaps) |
| `lag(col, n)`  | value `n` rows back in the partition |
| `lead(col, n)` | value `n` rows forward |
| `first_value` / `last_value` / `nth_value` | boundary values |
| `percent_rank()` / `cume_dist()` | distribution |
| `sum/avg/min/max/count` over `OVER (...)` | aggregate over the window |

### Frames

Without a frame, an aggregate over `OVER (PARTITION BY x ORDER BY y)` uses `RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`. That gives running totals. Other frames:

```sql
-- 7-day moving sum (RANGE on a sortable type)
SELECT day,
       sum(amount) OVER (
           ORDER BY day
           RANGE BETWEEN interval '6 days' PRECEDING AND CURRENT ROW
       )
FROM daily_revenue;

-- last 3 rows including current
... OVER (ORDER BY ts ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)

-- group of tied rows
... OVER (ORDER BY ts GROUPS BETWEEN 1 PRECEDING AND CURRENT ROW)  -- PG 11+
```

Frame mode | Semantics
-----------|----------
`ROWS`     | exact row offsets
`RANGE`    | value-distance offsets along `ORDER BY`
`GROUPS`   | peer-group offsets

## LATERAL recap (and where it shines)

Two patterns where `LATERAL` is hands-down the cleanest tool:

1. **Top-N per group** (covered in module 02). The window-function alternative is also idiomatic — the choice depends on what else the query needs:
   ```sql
   -- Latest post per author with window functions
   SELECT * FROM (
       SELECT p.*, row_number() OVER (PARTITION BY author_id ORDER BY published_at DESC) AS rn
       FROM app.posts p
       WHERE published_at IS NOT NULL
   ) s WHERE rn = 1;
   ```
2. **Per-row expansion** of a function or expression:
   ```sql
   SELECT p.id, t.tag
   FROM app.posts p,
        LATERAL unnest(p.tags) AS t(tag);   -- one row per (post, tag)
   ```

## Grouping extensions

| Extension | Use when |
|-----------|----------|
| `GROUPING SETS ((a,b),(a),(),...)` | You want a precise list of groupings |
| `ROLLUP (a, b)`  | Subtotals along a hierarchy: `(a,b)`, `(a)`, `()` |
| `CUBE (a, b)`    | Every combination |

Distinguish aggregate NULLs from data NULLs with `GROUPING(col) = 1`.

## DISTINCT ON revisited

For "top-1 per group" Postgres-flavored shortcuts:

```sql
-- Highest-priced product per color
SELECT DISTINCT ON (attributes->>'color')
       attributes->>'color' AS color, id, name, price_cents
FROM app.products
ORDER BY attributes->>'color', price_cents DESC;
```

## Generating data

`generate_series` produces rows from a range. Pair with `LATERAL` or a join to fabricate calendars, density curves, etc.

```sql
-- Calendar of days in 2024-05 left-joined to daily order counts
SELECT d::date, count(o.id) AS n
FROM generate_series(date '2024-05-01', date '2024-05-31', interval '1 day') d
LEFT JOIN app.orders o
       ON o.created_at >= d AND o.created_at < d + interval '1 day'
GROUP BY d
ORDER BY d;
```

## Run the lab

```powershell
psql -U postgres -d pgcourse -f 06-advanced-sql/lab.sql
```

## References

- WITH queries: <https://www.postgresql.org/docs/17/queries-with.html>
- Window functions: <https://www.postgresql.org/docs/17/tutorial-window.html> and <https://www.postgresql.org/docs/17/functions-window.html>
- LATERAL: <https://www.postgresql.org/docs/17/sql-select.html#SQL-FROM>

## Next

[Module 07 — JSON, Arrays, FTS →](../07-json-arrays-fts/)
