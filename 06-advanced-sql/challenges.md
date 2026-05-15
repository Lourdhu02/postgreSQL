# Module 06 — Challenges

## 1. Compute, for each user, their cumulative number of orders ordered by `created_at`.

<details><summary>Solution</summary>

```sql
SELECT user_id, id, created_at,
       count(*) OVER (PARTITION BY user_id ORDER BY created_at, id) AS cum_orders
FROM app.orders
ORDER BY user_id, created_at;
```
</details>

## 2. Top 3 most expensive products per `attributes->>'color'`.

<details><summary>Solution</summary>

```sql
SELECT * FROM (
    SELECT id, name, attributes->>'color' AS color, price_cents,
           row_number() OVER (PARTITION BY attributes->>'color' ORDER BY price_cents DESC, id) AS rn
    FROM app.products
) s WHERE rn <= 3
ORDER BY color, rn;
```
</details>

## 3. Recursive CTE: list every category with its full path joined by `' > '`.

<details><summary>Solution</summary>

```sql
WITH RECURSIVE t AS (
    SELECT id, name, parent_id, name AS path FROM app.categories WHERE parent_id IS NULL
    UNION ALL
    SELECT c.id, c.name, c.parent_id, t.path || ' > ' || c.name
    FROM app.categories c JOIN t ON c.parent_id = t.id
)
SELECT id, path FROM t ORDER BY path;
```
</details>

## 4. For each post, fetch the **two** most recent comments inline using `LATERAL`.

<details><summary>Solution</summary>

```sql
SELECT p.id AS post_id, c.id AS comment_id, c.created_at
FROM app.posts p
LEFT JOIN LATERAL (
    SELECT id, created_at FROM app.comments
    WHERE post_id = p.id
    ORDER BY created_at DESC, id DESC
    LIMIT 2
) c ON TRUE
ORDER BY p.id, c.created_at DESC
LIMIT 30;
```
</details>

## 5. Compute the **gap in days** between consecutive paid orders for each user.

<details><summary>Solution</summary>

```sql
SELECT user_id, id, created_at,
       (created_at - lag(created_at) OVER (PARTITION BY user_id ORDER BY created_at)) AS gap
FROM app.orders
WHERE status = 'paid'
ORDER BY user_id, created_at;
```
</details>

## 6. 30-day rolling order count per user.

<details><summary>Solution</summary>

```sql
SELECT user_id, created_at,
       count(*) OVER (PARTITION BY user_id
                      ORDER BY created_at
                      RANGE BETWEEN interval '29 days' PRECEDING AND CURRENT ROW) AS rolling_30d
FROM app.orders
ORDER BY user_id, created_at;
```
</details>

## 7. Show every comment thread with depth, sorted by ancestor chain, for `post_id = 50`.

<details><summary>Solution</summary>

```sql
WITH RECURSIVE t AS (
    SELECT id, parent_comment_id, body, 1 AS depth, ARRAY[id] AS chain
    FROM app.comments WHERE post_id = 50 AND parent_comment_id IS NULL
    UNION ALL
    SELECT c.id, c.parent_comment_id, c.body, t.depth + 1, t.chain || c.id
    FROM app.comments c JOIN t ON c.parent_comment_id = t.id
)
SELECT depth, repeat('  ', depth-1) || left(body, 80) AS preview
FROM t
ORDER BY chain;
```
</details>

## 8. Median order total for `paid` orders, by month.

<details><summary>Solution</summary>

```sql
SELECT date_trunc('month', created_at)::date AS month,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY total_cents) AS median_cents
FROM app.orders WHERE status = 'paid'
GROUP BY 1 ORDER BY 1;
```
</details>

## 9. Cross-tab the count of orders by `status` (rows) and month (columns) using conditional aggregates.

<details><summary>Solution</summary>

```sql
SELECT status,
       count(*) FILTER (WHERE date_trunc('month', created_at) = '2024-04-01') AS m_2024_04,
       count(*) FILTER (WHERE date_trunc('month', created_at) = '2024-05-01') AS m_2024_05,
       count(*) FILTER (WHERE date_trunc('month', created_at) = '2024-06-01') AS m_2024_06
FROM app.orders
GROUP BY status
ORDER BY status;
```
For dynamic crosstabs, the `tablefunc` extension provides `crosstab`.
</details>

## 10. A `WITH RECURSIVE` query is slow. What's the first thing to check?

<details><summary>Solution</summary>

1. Is the **anchor** appropriately selective? An anchor of `SELECT * FROM huge_table` will explode.
2. Is there an index supporting the **join key** between recursion step and CTE name? (`comments(parent_comment_id)`, here.)
3. Are you using `UNION` (deduplicated) when `UNION ALL` would suffice (strict tree)?
4. Run `EXPLAIN ANALYZE` — look for the `Recursive Union` node and its iteration counts.
</details>
