# Module 02 — Challenges

Set `SET search_path = app, public;` first.

## 1. List each product with its total quantity sold (sum of `order_items.quantity`). Include products that have never been ordered.

<details><summary>Solution</summary>

```sql
SELECT p.id, p.name, coalesce(sum(oi.quantity), 0) AS units_sold
FROM products p
LEFT JOIN order_items oi ON oi.product_id = p.id
GROUP BY p.id, p.name
ORDER BY units_sold DESC, p.id;
```
</details>

## 2. Products that have never been ordered

<details><summary>Solution</summary>

```sql
SELECT p.id, p.sku, p.name
FROM products p
WHERE NOT EXISTS (
    SELECT 1 FROM order_items oi WHERE oi.product_id = p.id
)
ORDER BY p.id;
```
</details>

## 3. For each post, return the latest comment's body and timestamp, or `NULL` if none. One row per post.

<details><summary>Solution</summary>

```sql
SELECT p.id AS post_id, c.body AS latest_comment, c.created_at
FROM posts p
LEFT JOIN LATERAL (
    SELECT body, created_at
    FROM comments
    WHERE post_id = p.id
    ORDER BY created_at DESC
    LIMIT 1
) c ON TRUE
ORDER BY p.id
LIMIT 10;
```
</details>

## 4. Revenue per `category.name` (sum of `quantity * unit_price_cents` joined through `posts`? No — that doesn't make sense. Through `products`? Products don't have categories. Compute revenue per `posts` category by treating each `posts` author's orders as attributable to all categories the author has posted in.

This question is intentionally awkward — explain in one sentence why the question is ambiguous, then propose a clean version and answer it.

<details><summary>Solution</summary>

Categories in the schema attach to **posts**, not products or orders. There is no defined relationship between `categories` and `orders`. Pick a sharper question: "Revenue per order status." That is well defined:

```sql
SELECT status, sum(total_cents) AS revenue_cents
FROM orders
GROUP BY status
ORDER BY revenue_cents DESC;
```
</details>

## 5. Find every `(author_id, post_id)` pair where the author has commented on **their own** post.

<details><summary>Solution</summary>

```sql
SELECT DISTINCT c.author_id, c.post_id
FROM comments c
JOIN posts p ON p.id = c.post_id
WHERE p.author_id = c.author_id
ORDER BY c.author_id, c.post_id
LIMIT 20;
```
</details>

## 6. Compute the 25th, 50th, 75th, 95th percentile of `total_cents` for **paid** orders, in a single row.

<details><summary>Solution</summary>

```sql
SELECT
    percentile_cont(0.25) WITHIN GROUP (ORDER BY total_cents) AS p25,
    percentile_cont(0.5)  WITHIN GROUP (ORDER BY total_cents) AS p50,
    percentile_cont(0.75) WITHIN GROUP (ORDER BY total_cents) AS p75,
    percentile_cont(0.95) WITHIN GROUP (ORDER BY total_cents) AS p95
FROM orders
WHERE status = 'paid';
```
</details>

## 7. Using `UNION ALL` and `GROUP BY`, list the most frequently used tag across both `posts.tags` and `products.attributes->'tags'`.

<details><summary>Solution</summary>

```sql
WITH all_tags AS (
    SELECT unnest(tags) AS tag FROM posts
    UNION ALL
    SELECT jsonb_array_elements_text(attributes->'tags') FROM products
)
SELECT tag, count(*) AS n
FROM all_tags
GROUP BY tag
ORDER BY n DESC, tag
LIMIT 10;
```
</details>

## 8. Why does this query return fewer rows than you might expect?
```sql
SELECT * FROM users u
WHERE u.id NOT IN (SELECT author_id FROM posts);
```

<details><summary>Solution</summary>

If `posts.author_id` were nullable and contained any NULL, `NOT IN` would return zero rows because `id <> NULL` is unknown. Use `NOT EXISTS` for NULL safety:

```sql
SELECT * FROM users u
WHERE NOT EXISTS (SELECT 1 FROM posts WHERE author_id = u.id);
```
In this schema `author_id` is `NOT NULL`, so the queries return the same result here, but the `NOT EXISTS` pattern is the habit to build.
</details>

## 9. Find pairs of products `(a, b)` where `a.id < b.id` that share the same `attributes->>'color'`. Show first 10.

<details><summary>Solution</summary>

```sql
SELECT a.id AS a, b.id AS b, a.attributes->>'color' AS color
FROM products a
JOIN products b
  ON a.attributes->>'color' = b.attributes->>'color'
 AND a.id < b.id
ORDER BY color, a.id, b.id
LIMIT 10;
```
</details>

## 10. Monthly revenue from paid orders, plus a grand total row.

<details><summary>Solution</summary>

```sql
SELECT
    date_trunc('month', created_at)::date AS month,
    sum(total_cents) AS revenue_cents
FROM orders
WHERE status = 'paid'
GROUP BY ROLLUP (date_trunc('month', created_at))
ORDER BY month NULLS LAST;
```
The row where `month IS NULL` is the grand total.
</details>
