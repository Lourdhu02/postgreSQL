-- 01-sql-basics/lab.sql
-- Runnable demonstration of every concept from the lesson. Each block is
-- annotated with WHY rather than WHAT.
SET search_path = app, public;

------------------------------------------------------------
-- 1. Basic SELECT
------------------------------------------------------------
-- WHY: prefer explicit column lists over SELECT * in application code; you
-- get smaller rowsets and break loudly when a column is renamed/removed.
SELECT id, email, full_name
FROM users
LIMIT 5;

------------------------------------------------------------
-- 2. WHERE with comparison operators
------------------------------------------------------------
-- WHY: paid orders over $50. price_cents is integer, so no float comparison
-- surprises here.
SELECT id, user_id, total_cents
FROM orders
WHERE status = 'paid'
  AND total_cents > 5000
ORDER BY total_cents DESC
LIMIT 10;

------------------------------------------------------------
-- 3. LIKE vs ILIKE
------------------------------------------------------------
-- WHY: LIKE is case-sensitive; ILIKE is the Postgres-specific case-insensitive
-- variant. Note: leading-% LIKE patterns cannot use a normal btree index;
-- you would use pg_trgm + GIN/GiST for that (module 07).
SELECT id, title
FROM posts
WHERE title ILIKE '%pgvector%'
LIMIT 5;

------------------------------------------------------------
-- 4. NULL semantics
------------------------------------------------------------
-- WHY: drafts have published_at IS NULL. Demonstrate why '!= NULL' is wrong.
SELECT count(*) AS drafts_correct
FROM posts WHERE published_at IS NULL;

SELECT count(*) AS drafts_wrong
FROM posts WHERE published_at != NULL;   -- always returns 0; '!= NULL' is unknown.

-- IS DISTINCT FROM is NULL-safe equality (treats NULL as a value).
SELECT 1 IS DISTINCT FROM 1     AS one_vs_one,
       1 IS DISTINCT FROM NULL  AS one_vs_null,
       NULL IS DISTINCT FROM NULL AS null_vs_null;

------------------------------------------------------------
-- 5. coalesce and nullif
------------------------------------------------------------
-- WHY: replace NULL with a friendly default; avoid divide-by-zero with nullif.
SELECT id,
       coalesce(published_at, created_at) AS effective_date,
       total_cents / nullif(0, 0)         AS will_be_null
FROM (
    SELECT p.id, p.published_at, p.created_at, o.total_cents
    FROM posts p
    LEFT JOIN orders o ON FALSE   -- intentional no-match so total_cents is NULL
    LIMIT 5
) s;

------------------------------------------------------------
-- 6. ORDER BY and pagination
------------------------------------------------------------
-- WHY: always include a unique tiebreaker (id) so pagination is stable.
SELECT id, title, published_at
FROM posts
WHERE published_at IS NOT NULL
ORDER BY published_at DESC, id DESC
LIMIT 10 OFFSET 20;

-- WHY: keyset pagination is O(log n) regardless of offset depth. Replace the
-- placeholder values with the (published_at, id) of the last row of the
-- previous page.
SELECT id, title, published_at
FROM posts
WHERE published_at IS NOT NULL
  AND (published_at, id) < (timestamptz '2024-12-01', 999999999)
ORDER BY published_at DESC, id DESC
LIMIT 10;

------------------------------------------------------------
-- 7. DISTINCT ON (Postgres-specific)
------------------------------------------------------------
-- WHY: latest published post per author in one pass. Note the ORDER BY: the
-- column(s) in DISTINCT ON must be the leading sort key(s).
SELECT DISTINCT ON (author_id)
       author_id, id, title, published_at
FROM posts
WHERE published_at IS NOT NULL
ORDER BY author_id, published_at DESC, id DESC
LIMIT 10;

------------------------------------------------------------
-- 8. CASE expression
------------------------------------------------------------
-- WHY: bucket orders into a small set of categories you can then aggregate.
SELECT status,
       count(*)                        AS n,
       sum(total_cents)                AS revenue_cents,
       avg(total_cents)::int           AS avg_cents
FROM orders
GROUP BY status
ORDER BY revenue_cents DESC;

------------------------------------------------------------
-- 9. Scalar functions on text and time
------------------------------------------------------------
SELECT email,
       lower(email)                          AS lowered,
       length(email)                         AS char_len,
       split_part(email, '@', 1)             AS local_part,
       split_part(email, '@', 2)             AS domain
FROM users
LIMIT 5;

SELECT date_trunc('month', created_at)::date AS month_bucket,
       count(*)                              AS posts_in_month
FROM posts
GROUP BY 1
ORDER BY 1;

------------------------------------------------------------
-- 10. IN / NOT IN / EXISTS preview
------------------------------------------------------------
-- WHY: IN with a NULL behaves surprisingly. NOT IN (..., NULL) is always
-- empty because '= NULL' is unknown. Prefer NOT EXISTS for nullable cols.
SELECT count(*) FROM users
WHERE id NOT IN (SELECT author_id FROM posts WHERE author_id IS NOT NULL);

SELECT count(*) FROM users u
WHERE NOT EXISTS (SELECT 1 FROM posts p WHERE p.author_id = u.id);
