-- 02-joins-aggregates/lab.sql
SET search_path = app, public;

------------------------------------------------------------
-- 1. INNER JOIN
------------------------------------------------------------
-- WHY: bring author email next to each post. Default JOIN is INNER.
SELECT p.id, p.title, u.email
FROM posts p
JOIN users u ON u.id = p.author_id
ORDER BY p.id
LIMIT 5;

------------------------------------------------------------
-- 2. LEFT JOIN as anti-join
------------------------------------------------------------
-- WHY: users with no posts. Filter on right-side PK IS NULL to keep only
-- the unmatched left rows.
SELECT u.id, u.email
FROM users u
LEFT JOIN posts p ON p.author_id = u.id
WHERE p.id IS NULL
LIMIT 5;

-- Same result via NOT EXISTS (preferred for clarity and NULL safety).
SELECT u.id, u.email
FROM users u
WHERE NOT EXISTS (SELECT 1 FROM posts p WHERE p.author_id = u.id)
LIMIT 5;

------------------------------------------------------------
-- 3. FULL OUTER JOIN: diffing two sets
------------------------------------------------------------
-- WHY: which products have inventory in 'US-EAST' but not 'EU-CENTRAL', and
-- vice versa? FULL JOIN keeps non-matches from both sides.
WITH east AS (SELECT product_id FROM inventory WHERE warehouse='US-EAST'),
     eu   AS (SELECT product_id FROM inventory WHERE warehouse='EU-CENTRAL')
SELECT e.product_id AS east_only, u.product_id AS eu_only
FROM east e
FULL JOIN eu u USING (product_id)
WHERE e.product_id IS NULL OR u.product_id IS NULL
LIMIT 10;
-- For this seed there is full overlap, so 0 rows. Verifies the diff query works.

------------------------------------------------------------
-- 4. CROSS JOIN
------------------------------------------------------------
-- WHY: build a date x status matrix you can later left-join real data into,
-- so missing combinations show as 0 instead of being absent.
SELECT d::date, s.status
FROM generate_series(date '2024-04-01', date '2024-04-07', interval '1 day') d
CROSS JOIN (VALUES ('paid'),('pending'),('shipped'),('cancelled')) AS s(status)
ORDER BY d, s.status;

------------------------------------------------------------
-- 5. LATERAL: top-N per group
------------------------------------------------------------
-- WHY: three most recent comments for each of the first 5 posts. Without
-- LATERAL the inner query could not reference p.id.
SELECT p.id AS post_id, c.id AS comment_id, c.created_at
FROM (SELECT id FROM posts ORDER BY id LIMIT 5) p
CROSS JOIN LATERAL (
    SELECT id, created_at
    FROM comments
    WHERE post_id = p.id
    ORDER BY created_at DESC, id DESC
    LIMIT 3
) c
ORDER BY p.id, c.created_at DESC;

------------------------------------------------------------
-- 6. GROUP BY + HAVING
------------------------------------------------------------
-- WHY: most prolific authors. HAVING filters after aggregation; WHERE before.
SELECT u.id, u.email, count(*) AS n_posts
FROM posts p
JOIN users u ON u.id = p.author_id
WHERE p.published_at IS NOT NULL
GROUP BY u.id, u.email
HAVING count(*) >= 5
ORDER BY n_posts DESC, u.id
LIMIT 10;

------------------------------------------------------------
-- 7. FILTER clause: conditional aggregates
------------------------------------------------------------
-- WHY: ANSI SQL. Replaces sum(CASE WHEN ...) and the planner treats it the same.
SELECT
    count(*)                                            AS total_orders,
    count(*) FILTER (WHERE status = 'paid')             AS paid_n,
    count(*) FILTER (WHERE status = 'pending')          AS pending_n,
    sum(total_cents) FILTER (WHERE status = 'paid')     AS paid_revenue_cents,
    avg(total_cents) FILTER (WHERE status = 'paid')::int AS paid_avg_cents
FROM orders;

------------------------------------------------------------
-- 8. Aggregates that build collections
------------------------------------------------------------
SELECT p.id,
       count(c.*)                                        AS n_comments,
       array_agg(c.id ORDER BY c.created_at)             AS comment_ids,
       string_agg(left(c.body, 20), ' | ' ORDER BY c.id) AS preview
FROM posts p
LEFT JOIN comments c ON c.post_id = p.id
GROUP BY p.id
ORDER BY n_comments DESC, p.id
LIMIT 5;

------------------------------------------------------------
-- 9. Percentile aggregates
------------------------------------------------------------
-- WHY: order-value percentiles for paid orders.
SELECT
    percentile_cont(0.5)  WITHIN GROUP (ORDER BY total_cents) AS p50,
    percentile_cont(0.95) WITHIN GROUP (ORDER BY total_cents) AS p95,
    percentile_cont(0.99) WITHIN GROUP (ORDER BY total_cents) AS p99
FROM orders
WHERE status = 'paid';

------------------------------------------------------------
-- 10. ROLLUP for subtotals
------------------------------------------------------------
-- WHY: monthly revenue per status + month totals + grand total in one pass.
-- GROUPING(col) tells you whether the NULL is an aggregate row or real data.
SELECT
    date_trunc('month', created_at)::date AS month,
    status,
    count(*) AS n,
    sum(total_cents) AS revenue_cents,
    GROUPING(status) AS is_total_row
FROM orders
GROUP BY ROLLUP (date_trunc('month', created_at), status)
ORDER BY month NULLS LAST, status NULLS LAST;

------------------------------------------------------------
-- 11. Set operators
------------------------------------------------------------
-- WHY: tags that appear in either Engineering posts or paid orders' product
-- attributes. UNION dedups; UNION ALL keeps duplicates (faster).
SELECT unnest(tags) AS tag FROM posts WHERE published_at IS NOT NULL
UNION
SELECT jsonb_array_elements_text(attributes->'tags') FROM products
ORDER BY tag;
