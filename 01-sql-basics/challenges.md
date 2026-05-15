# Module 01 — Challenges

Run answers in `psql -U postgres -d pgcourse`. Start with `SET search_path = app, public;`.

## 1. List the 10 most recent **published** posts with `id`, `title`, `published_at`

<details><summary>Solution</summary>

```sql
SELECT id, title, published_at
FROM posts
WHERE published_at IS NOT NULL
ORDER BY published_at DESC, id DESC
LIMIT 10;
```
</details>

## 2. Count how many orders are in each status, sorted by count descending

<details><summary>Solution</summary>

```sql
SELECT status, count(*) AS n
FROM orders
GROUP BY status
ORDER BY n DESC;
```
</details>

## 3. Show every user whose email domain is exactly `example.com`. Be careful with case.

<details><summary>Solution</summary>

```sql
SELECT id, email
FROM users
WHERE split_part(email, '@', 2) = 'example.com';
-- email is citext so case doesn't matter, but split_part returns text;
-- the comparison is case-sensitive against the literal.
```
</details>

## 4. List posts that are drafts (no `published_at`). Show how many.

<details><summary>Solution</summary>

```sql
SELECT count(*) FROM posts WHERE published_at IS NULL;
-- NOT: WHERE published_at = NULL  — that is always unknown.
```
</details>

## 5. Return the 5 most expensive products. Format the price as dollars with two decimals.

<details><summary>Solution</summary>

```sql
SELECT id, name,
       to_char(price_cents / 100.0, 'FM999990.00') AS price_dollars
FROM products
ORDER BY price_cents DESC, id
LIMIT 5;
```
</details>

## 6. For each user, show their email and a `member_tier` of `gold`, `silver`, or `bronze` based on the `tier` value inside `profile` JSONB (`enterprise` → gold, `pro` → silver, `free` → bronze).

Hint: `profile->>'tier'` extracts a JSONB value as `text`.

<details><summary>Solution</summary>

```sql
SELECT id, email,
       CASE profile->>'tier'
           WHEN 'enterprise' THEN 'gold'
           WHEN 'pro'        THEN 'silver'
           ELSE                   'bronze'
       END AS member_tier
FROM users
ORDER BY id
LIMIT 10;
```
</details>

## 7. Show pairs of users that share the same `tier`. Avoid showing `(a, b)` and `(b, a)` twice.

Hint: enforce `u1.id < u2.id`.

<details><summary>Solution</summary>

```sql
SELECT u1.email AS user_a, u2.email AS user_b, u1.profile->>'tier' AS tier
FROM users u1
JOIN users u2 ON u1.profile->>'tier' = u2.profile->>'tier'
            AND u1.id < u2.id
LIMIT 10;
```
</details>

## 8. Use `DISTINCT ON` to find the earliest comment per post.

<details><summary>Solution</summary>

```sql
SELECT DISTINCT ON (post_id)
       post_id, id AS comment_id, created_at, body
FROM comments
ORDER BY post_id, created_at ASC, id ASC
LIMIT 10;
```
</details>

## 9. Why does `SELECT 1 = NULL;` return `NULL` and not `false`? Explain in a sentence.

<details><summary>Solution</summary>

`NULL` means "unknown". The comparison `1 = NULL` cannot be evaluated to true or false because the right-hand side is unknown, so SQL returns the third boolean value, `NULL`. This is the foundation of three-valued logic in SQL.
</details>

## 10. Page 1 (`LIMIT 20 OFFSET 0`) and page 50 (`LIMIT 20 OFFSET 980`) of `posts ORDER BY published_at DESC`. Which is slower and why? Rewrite page 50 as keyset pagination.

<details><summary>Solution</summary>

Page 50 is slower because Postgres still has to scan + sort the first 980 rows just to discard them. Keyset pagination uses the last seen `(published_at, id)` and lets an index seek directly to it:

```sql
SELECT id, title, published_at
FROM posts
WHERE published_at IS NOT NULL
  AND (published_at, id) < (:last_published_at, :last_id)
ORDER BY published_at DESC, id DESC
LIMIT 20;
```
The composite index on `(published_at, id)` (or the existing `posts_published_at_idx`) supports this. Docs on indexing: <https://www.postgresql.org/docs/17/indexes-types.html>.
</details>
