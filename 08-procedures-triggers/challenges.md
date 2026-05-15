# Module 08 — Challenges

## 1. Write a function `app.discounted_price(cents int, pct numeric) RETURNS int` that returns `cents` reduced by `pct`%, rounded down, never below zero. Make it `IMMUTABLE`.

<details><summary>Solution</summary>

```sql
CREATE OR REPLACE FUNCTION app.discounted_price(cents int, pct numeric)
RETURNS int
LANGUAGE sql IMMUTABLE PARALLEL SAFE STRICT AS $$
    SELECT greatest(0, floor(cents * (1 - pct/100.0)))::int;
$$;

SELECT app.discounted_price(1999, 20);   -- 1599
```
Mark `STRICT` so NULL inputs short-circuit to NULL.
</details>

## 2. Create a trigger that maintains `posts.updated_at` only when actual columns change (not no-op `UPDATE`).

<details><summary>Solution</summary>

```sql
CREATE OR REPLACE FUNCTION app.tg_set_updated_at_distinct()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW IS DISTINCT FROM OLD THEN
        NEW.updated_at := now();
    END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS posts_set_updated_at ON app.posts;
CREATE TRIGGER posts_set_updated_at
BEFORE UPDATE ON app.posts
FOR EACH ROW EXECUTE FUNCTION app.tg_set_updated_at_distinct();
```
</details>

## 3. Audit only `UPDATE` and `DELETE` on `app.orders` into `audit_log` with `OLD`/`NEW` snapshots.

<details><summary>Solution</summary>

```sql
CREATE OR REPLACE FUNCTION app.tg_audit_orders_full()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO app.audit_log (table_name, action, row_pk, payload)
    VALUES ('orders', TG_OP,
            jsonb_build_object('id', coalesce(NEW.id, OLD.id)),
            jsonb_build_object('old', to_jsonb(OLD), 'new', to_jsonb(NEW)));
    RETURN coalesce(NEW, OLD);
END;
$$;
DROP TRIGGER IF EXISTS orders_audit_full ON app.orders;
CREATE TRIGGER orders_audit_full
AFTER UPDATE OR DELETE ON app.orders
FOR EACH ROW EXECUTE FUNCTION app.tg_audit_orders_full();
```
</details>

## 4. Convert one of the row-level audit triggers above to use **transition tables** for bulk efficiency.

<details><summary>Solution</summary>

See the `orders_log_stmt` trigger and `tg_log_order_changes` function in `lab.sql`. The key difference is `REFERENCING OLD TABLE AS o_old NEW TABLE AS o_new FOR EACH STATEMENT`.
</details>

## 5. Why is `BEGIN ... EXCEPTION WHEN OTHERS THEN ... END` expensive inside a tight loop?

<details><summary>Solution</summary>

Each exception-handling block creates a **subtransaction** with its own snapshot and rollback point. Over millions of iterations the bookkeeping (xact ids, savepoint records) becomes the dominant cost, and you can exhaust subtransaction space at depth >64. Prefer to validate up front with a single SQL statement when possible.
</details>

## 6. Build a function that **upserts** a user by email, returning the row.

<details><summary>Solution</summary>

```sql
CREATE OR REPLACE FUNCTION app.upsert_user(p_email citext, p_name text)
RETURNS app.users LANGUAGE sql AS $$
    INSERT INTO app.users (email, full_name)
    VALUES (p_email, p_name)
    ON CONFLICT (email) DO UPDATE
      SET full_name = EXCLUDED.full_name
    RETURNING *;
$$;

SELECT * FROM app.upsert_user('user1@example.com', 'User 1 renamed');
```
</details>

## 7. When would you reach for a **procedure** instead of a function?

<details><summary>Solution</summary>

When the routine must perform its own `COMMIT`/`ROLLBACK` — for example, a chunked archival job that processes 100k rows in 1k-row commits to keep the WAL bounded and avoid long-running snapshots. Functions cannot issue transaction control. See `archive_old_comments` in `lab.sql`.
</details>

## 8. Disable a trigger temporarily to bulk-load data, then re-enable it.

<details><summary>Solution</summary>

```sql
ALTER TABLE app.orders DISABLE TRIGGER orders_audit;
-- bulk insert
COPY app.orders FROM '...';
ALTER TABLE app.orders ENABLE TRIGGER orders_audit;
```
Mind invariants the trigger was enforcing; backfill manually after re-enabling.
</details>

## 9. List every trigger function used by triggers in the `app` schema.

<details><summary>Solution</summary>

```sql
SELECT DISTINCT t.tgname AS trigger_name,
       n.nspname || '.' || p.proname AS function
FROM pg_trigger t
JOIN pg_class   c ON c.oid = t.tgrelid
JOIN pg_namespace cn ON cn.oid = c.relnamespace
JOIN pg_proc    p ON p.oid = t.tgfoid
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE NOT t.tgisinternal AND cn.nspname = 'app';
```
</details>

## 10. Name three things you should NOT do with triggers.

<details><summary>Solution</summary>

1. **Maintain hot counters** (e.g. `posts.comment_count`) that serialize all writers through one row.
2. **Call out to external services / make HTTP requests.** Triggers are inside a transaction; failures cascade.
3. **Hide critical business rules** that should be visible in application code or in explicit SQL functions — debuggers will not look inside triggers first.
</details>
