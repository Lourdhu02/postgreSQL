-- 06-advanced-sql/lab.sql
SET search_path = app, public;

------------------------------------------------------------
-- 1. Simple CTE for readability
------------------------------------------------------------
-- WHY: pulling the "paid orders" subset out of multiple SELECTs documents
-- the slice and lets the planner inline (PG 12+).
WITH paid AS (
    SELECT * FROM orders WHERE status = 'paid'
)
SELECT user_id, count(*) AS orders, sum(total_cents) AS revenue
FROM paid
GROUP BY user_id
ORDER BY revenue DESC
LIMIT 10;

------------------------------------------------------------
-- 2. Recursive CTE: walk the categories tree
------------------------------------------------------------
WITH RECURSIVE cat_tree AS (
    SELECT id, name, parent_id, ARRAY[name] AS path, 1 AS depth
    FROM categories
    WHERE parent_id IS NULL
  UNION ALL
    SELECT c.id, c.name, c.parent_id, t.path || c.name, t.depth + 1
    FROM categories c
    JOIN cat_tree t ON c.parent_id = t.id
)
SELECT id, name, depth, path FROM cat_tree ORDER BY path;

------------------------------------------------------------
-- 3. Recursive CTE: thread comments under a post
------------------------------------------------------------
-- WHY: produce nested comment threads with depth and ancestor chain.
WITH RECURSIVE thread AS (
    SELECT id, post_id, parent_comment_id, author_id, body, created_at,
           1 AS depth, ARRAY[id] AS ancestors
    FROM comments
    WHERE post_id = 25 AND parent_comment_id IS NULL
  UNION ALL
    SELECT c.id, c.post_id, c.parent_comment_id, c.author_id, c.body, c.created_at,
           t.depth + 1, t.ancestors || c.id
    FROM comments c
    JOIN thread t ON c.parent_comment_id = t.id
)
SELECT depth, repeat('  ', depth - 1) || left(body, 60) AS preview
FROM thread
ORDER BY ancestors, created_at;

------------------------------------------------------------
-- 4. Window functions: rank, lag, running total
------------------------------------------------------------
SELECT id,
       user_id,
       created_at,
       total_cents,
       row_number()  OVER w AS rn,
       rank()        OVER w AS rk,
       lag(total_cents) OVER w AS prev_cents,
       sum(total_cents) OVER w AS running_total
FROM orders
WHERE status = 'paid'
WINDOW w AS (PARTITION BY user_id ORDER BY created_at, id)
ORDER BY user_id, created_at
LIMIT 20;

------------------------------------------------------------
-- 5. Top-N per group with row_number() vs DISTINCT ON
------------------------------------------------------------
-- WHY: latest published post per author, two ways.
SELECT *
FROM (
    SELECT p.*,
           row_number() OVER (PARTITION BY author_id ORDER BY published_at DESC, id DESC) AS rn
    FROM posts p
    WHERE published_at IS NOT NULL
) s
WHERE rn = 1
LIMIT 10;

SELECT DISTINCT ON (author_id) author_id, id, title, published_at
FROM posts
WHERE published_at IS NOT NULL
ORDER BY author_id, published_at DESC, id DESC
LIMIT 10;

------------------------------------------------------------
-- 6. 7-day moving sum with RANGE frame
------------------------------------------------------------
WITH daily AS (
    SELECT date_trunc('day', created_at)::date AS day,
           sum(total_cents)                    AS revenue
    FROM orders WHERE status = 'paid'
    GROUP BY 1
)
SELECT day,
       revenue,
       sum(revenue) OVER (
           ORDER BY day
           RANGE BETWEEN interval '6 days' PRECEDING AND CURRENT ROW
       ) AS rolling_7d
FROM daily
ORDER BY day;

------------------------------------------------------------
-- 7. LATERAL with unnest for per-tag analytics
------------------------------------------------------------
SELECT t.tag, count(*) AS n_posts
FROM posts p, LATERAL unnest(p.tags) AS t(tag)
WHERE p.published_at IS NOT NULL
GROUP BY t.tag
ORDER BY n_posts DESC, t.tag
LIMIT 10;

------------------------------------------------------------
-- 8. Calendar left-join to fill gaps
------------------------------------------------------------
SELECT d::date AS day, count(o.id) AS n_orders
FROM generate_series(date '2024-05-01', date '2024-05-31', interval '1 day') d
LEFT JOIN orders o ON o.created_at >= d AND o.created_at < d + interval '1 day'
GROUP BY d ORDER BY d;

------------------------------------------------------------
-- 9. Data-modifying CTE
------------------------------------------------------------
-- WHY: archive then audit in one statement. Wrap in a transaction in real apps.
-- This block is illustrative; it inserts into a temporary audit table.
CREATE TEMP TABLE IF NOT EXISTS lab06_audit (id bigint, archived_at timestamptz default now());

WITH old AS (
    SELECT id FROM comments WHERE created_at < timestamptz '2024-03-15'
)
INSERT INTO lab06_audit (id)
SELECT id FROM old;

SELECT count(*) FROM lab06_audit;

------------------------------------------------------------
-- 10. ROLLUP with GROUPING() to detect total rows
------------------------------------------------------------
SELECT
    date_trunc('month', created_at)::date AS month,
    status,
    count(*) AS n,
    GROUPING(status) = 1 AS is_month_total
FROM orders
GROUP BY ROLLUP (date_trunc('month', created_at), status)
ORDER BY month NULLS LAST, status NULLS LAST;
