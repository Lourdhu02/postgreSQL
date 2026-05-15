# Module 03 — Challenges

## 1. Pick the right type for each: a person's height in metres; a hashed API key; an IPv4 source address; a country code; an event timestamp.

<details><summary>Solution</summary>

| Column | Type | Why |
|--------|------|-----|
| height_m | `numeric(4,2)` | Exact decimal; range 0.00–99.99. |
| api_key_hash | `bytea` or `text` (hex) | Fixed-length binary; if you want length enforced use `bytea`. |
| src_ip | `inet` | First-class IP type; supports CIDR ops. |
| country_code | `char(2)` or `text` with `CHECK (length(country_code)=2)` | ISO 3166-1 alpha-2 is exactly 2 chars; `char(2)` is fine here. |
| occurred_at | `timestamptz` | Always tz-aware for moments in time. |
</details>

## 2. Add a `CHECK` constraint to `app.users` ensuring `email` contains exactly one `@`.

<details><summary>Solution</summary>

```sql
ALTER TABLE app.users
ADD CONSTRAINT users_email_has_at
CHECK (email LIKE '%@%' AND email NOT LIKE '%@%@%');
```
Full RFC validation is intractable in SQL — keep the check simple and validate at the application boundary.
</details>

## 3. Add a `FOREIGN KEY` from `app.order_items.order_id` to `app.orders(id)` with `ON DELETE CASCADE`. Verify it already exists by checking `pg_constraint`.

<details><summary>Solution</summary>

```sql
SELECT conname, pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conrelid = 'app.order_items'::regclass
  AND contype = 'f';
```
The seed already creates this FK with `ON DELETE CASCADE`. If you wanted to add it manually:
```sql
ALTER TABLE app.order_items
ADD CONSTRAINT order_items_order_fk
FOREIGN KEY (order_id) REFERENCES app.orders(id) ON DELETE CASCADE;
```
</details>

## 4. Make `app.posts.title` unique per author. Two authors can have the same title; one author cannot.

<details><summary>Solution</summary>

```sql
ALTER TABLE app.posts
ADD CONSTRAINT posts_title_per_author_unique UNIQUE (author_id, title);
```
</details>

## 5. Normalize this table to 3NF:
```
employee(id, name, dept_id, dept_name, dept_manager)
```

<details><summary>Solution</summary>

`dept_name` and `dept_manager` depend on `dept_id`, not on `id`. Split:
```sql
CREATE TABLE department (
    id      bigint PRIMARY KEY,
    name    text NOT NULL,
    manager text
);
CREATE TABLE employee (
    id      bigint PRIMARY KEY,
    name    text NOT NULL,
    dept_id bigint NOT NULL REFERENCES department(id)
);
```
</details>

## 6. Build an `EXCLUDE` constraint that prevents two `inventory` rows for the same product in the same warehouse.

<details><summary>Solution</summary>

`PRIMARY KEY (product_id, warehouse)` already enforces this in the seed. The `EXCLUDE` equivalent (for illustration):
```sql
-- Equivalent unique-by-key (not better; just illustrative)
CREATE EXTENSION IF NOT EXISTS btree_gist;
ALTER TABLE app.inventory
ADD CONSTRAINT inv_no_dup
EXCLUDE USING gist (product_id WITH =, warehouse WITH =);
```
`EXCLUDE` shines for ranges; for plain equality `UNIQUE` is preferable.
</details>

## 7. Add a stored generated column `app.products.price_dollars numeric(10,2)` derived from `price_cents`.

<details><summary>Solution</summary>

```sql
ALTER TABLE app.products
ADD COLUMN price_dollars numeric(10,2)
GENERATED ALWAYS AS (price_cents / 100.0) STORED;
```
</details>

## 8. What's wrong with this schema?
```sql
CREATE TABLE order_v0 (
    id        serial PRIMARY KEY,
    items     text   -- comma-separated SKU list
);
```

<details><summary>Solution</summary>

- `serial` should be `bigint GENERATED ALWAYS AS IDENTITY` (or `bigserial`) — 32-bit IDs run out.
- `items` is a comma-separated list: not queryable per item, no FK, no per-line quantity.
- Pull lines into `order_items(order_id, product_id, quantity)` with FKs.
</details>

## 9. Choose between `enum` and a lookup table for a column representing the country of an address.

<details><summary>Solution</summary>

Lookup table: there are ~250 countries, the list is rare-but-not-never updated, and you want to attach attributes (name, currency, calling code). ENUMs are best for small, truly fixed sets like a 4-value status field where altering requires deliberate DDL.
</details>

## 10. Why is `timestamp` (without time zone) a footgun for moments in time?

<details><summary>Solution</summary>

`timestamp` stores wall-clock time without identifying which clock. Two services in different timezones will write and read the same column value while *meaning different absolute moments*. `timestamptz` normalizes to UTC on input and renders in the session's timezone — same absolute moment, no ambiguity. Reference: <https://www.postgresql.org/docs/17/datatype-datetime.html#DATATYPE-TIMEZONES>.
</details>
