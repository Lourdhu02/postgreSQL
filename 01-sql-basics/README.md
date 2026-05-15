# 01 — SQL Basics

By the end you can:
1. Read and write `SELECT` statements with `WHERE`, `ORDER BY`, `LIMIT`, and `OFFSET`.
2. Predict the result of expressions involving `NULL` (three-valued logic).
3. Use the most common scalar functions and `CASE` expressions.

**Time budget:** 30 min reading + 30 min lab.

Assumes you have run `seed/schema.sql` and `seed/data.sql`. Every example uses `SET search_path = app, public;`.

## The shape of a SELECT

```sql
SELECT   columns
FROM     tables
WHERE    row filter
GROUP BY ...
HAVING   group filter
ORDER BY ...
LIMIT    n  OFFSET m;
```

That is the logical order Postgres processes the clauses (not the order you type them). Knowing this explains why a column alias defined in `SELECT` is not visible in `WHERE`: `WHERE` runs before `SELECT`. See [SELECT in the docs](https://www.postgresql.org/docs/17/sql-select.html).

```mermaid
flowchart LR
    FROM --> WHERE --> GROUP[GROUP BY] --> HAVING --> SELECT --> DISTINCT --> ORDER[ORDER BY] --> LIMIT
```

## WHERE: row-level filtering

| Operator | Meaning |
|----------|---------|
| `=`, `<>`, `<`, `<=`, `>`, `>=` | Standard comparison. `<>` is ANSI for "not equal". `!=` is a Postgres synonym. |
| `BETWEEN a AND b`               | `a <= x <= b`. Inclusive on both ends. |
| `IN (...)`                      | Set membership. `x = ANY (ARRAY[...])` is the equivalent form. |
| `LIKE`, `ILIKE`                 | Pattern match. `%` matches any string, `_` matches one char. `ILIKE` is case-insensitive (Postgres). |
| `IS NULL`, `IS NOT NULL`        | The **only** way to test for NULL. `x = NULL` is always NULL (i.e. neither true nor false). |
| `IS [NOT] DISTINCT FROM`        | NULL-safe equality. `NULL IS NOT DISTINCT FROM NULL` is true. |

## NULL: the part that trips everyone up

NULL means "unknown", not "empty string" and not "zero". SQL uses **three-valued logic**: every boolean expression is `TRUE`, `FALSE`, or `NULL` (unknown). A row is included in the result only if its `WHERE` clause evaluates to `TRUE` — `NULL` is treated as false for filtering, but it propagates through arithmetic and comparisons.

| Expression | Result |
|------------|--------|
| `NULL = NULL`             | `NULL` |
| `NULL = 1`                | `NULL` |
| `NULL <> 1`               | `NULL` |
| `NULL OR TRUE`            | `TRUE`  (short-circuits) |
| `NULL OR FALSE`           | `NULL` |
| `NULL AND TRUE`           | `NULL` |
| `NULL AND FALSE`          | `FALSE` (short-circuits) |
| `1 + NULL`                | `NULL` |
| `coalesce(NULL, NULL, 5)` | `5` |
| `nullif(0, 0)`            | `NULL` |

Practical rules:
- Use `IS NULL` / `IS NOT NULL`, never `= NULL`.
- `coalesce(a, b, c)` returns the first non-null argument. Use it to provide defaults.
- `nullif(a, b)` returns NULL if `a = b`, else `a`. Useful for avoiding divide-by-zero: `x / nullif(y, 0)`.

See [Section 9.18 — Conditional Expressions](https://www.postgresql.org/docs/17/functions-conditional.html).

## ORDER BY, LIMIT, OFFSET

```sql
SELECT id, email, created_at
FROM app.users
ORDER BY created_at DESC, id        -- tiebreaker, otherwise ordering is unstable
LIMIT 10 OFFSET 20;                 -- skip 20, take 10
```

Notes:
- `ORDER BY` without a tiebreaker is **not deterministic** when the sort key has duplicates. Always include a unique column (usually the PK) as the last sort key for pagination.
- `OFFSET` is cheap for small offsets, expensive for deep pagination (it still has to count rows). Prefer **keyset pagination** for large offsets:
  ```sql
  SELECT * FROM app.posts
  WHERE  (created_at, id) < (:last_created_at, :last_id)
  ORDER BY created_at DESC, id DESC
  LIMIT 20;
  ```
- `NULLS FIRST` / `NULLS LAST` controls null ordering. Default in Postgres is `NULLS LAST` for ASC and `NULLS FIRST` for DESC.

## DISTINCT, DISTINCT ON

`SELECT DISTINCT` deduplicates entire rows after `SELECT`. **`DISTINCT ON (...)`** is Postgres-specific (flag it!) and picks one row per group, taking the first per `ORDER BY`:

```sql
-- Latest post per author (Postgres-specific)
SELECT DISTINCT ON (author_id)
       author_id, id, title, published_at
FROM app.posts
WHERE published_at IS NOT NULL
ORDER BY author_id, published_at DESC;
```

The ANSI-portable alternative uses a window function (covered in module 06).

## CASE expressions

Inline conditional:

```sql
SELECT id,
       status,
       CASE
           WHEN status = 'paid'    THEN 'revenue'
           WHEN status = 'pending' THEN 'pipeline'
           ELSE 'other'
       END AS bucket
FROM app.orders;
```

`CASE` can appear anywhere an expression can — `SELECT`, `WHERE`, `ORDER BY`, even inside aggregates.

## Common scalar functions

| Function | Example | Notes |
|----------|---------|-------|
| `lower`, `upper`, `length`        | `length('hello') → 5` | UTF-8 character count, not byte count. |
| `trim`, `ltrim`, `rtrim`          | `trim('  x  ') → 'x'` | |
| `substring`, `position`           | `position('s' in 'abs') → 3` | 1-indexed. |
| `concat`, `concat_ws`, `\|\|`       | `'a' \|\| 'b' → 'ab'` | `\|\|` returns NULL if either side is NULL; `concat` skips NULLs. |
| `to_char`, `to_date`, `to_number` | `to_char(now(),'YYYY-MM-DD')` | Locale-sensitive formatting. |
| `age`, `date_trunc`, `extract`    | `date_trunc('month', now())` | Time bucketing. |
| `round`, `floor`, `ceil`          | `round(3.14, 1) → 3.1` | |
| `coalesce`, `nullif`              | see above | |

Full reference: <https://www.postgresql.org/docs/17/functions.html>.

## When NULL bites

```sql
-- Wrong: this returns 0 rows because '!= NULL' is NULL for every row.
SELECT count(*) FROM app.posts WHERE published_at != NULL;

-- Right
SELECT count(*) FROM app.posts WHERE published_at IS NOT NULL;
```

```sql
-- Wrong: dividing by a possibly-zero quantity
SELECT total_cents / quantity FROM app.order_items;          -- divide by zero risk

-- Right
SELECT total_cents / nullif(quantity, 0) FROM app.order_items;
```

## Run the lab

```powershell
psql -U postgres -d pgcourse -f 01-sql-basics/lab.sql
```

## References

- SELECT statement: <https://www.postgresql.org/docs/17/sql-select.html>
- Conditional expressions: <https://www.postgresql.org/docs/17/functions-conditional.html>
- String functions: <https://www.postgresql.org/docs/17/functions-string.html>
- Date/time functions: <https://www.postgresql.org/docs/17/functions-datetime.html>

## Next

[Module 02 — Joins &amp; Aggregates →](../02-joins-aggregates/)
