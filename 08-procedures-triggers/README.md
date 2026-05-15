# 08 — Procedures &amp; Triggers

By the end you can:
1. Write PL/pgSQL functions with arguments, return types, and exception handling.
2. Distinguish a **function** from a **procedure**, and know when each applies.
3. Use triggers (BEFORE/AFTER, ROW/STATEMENT) for auditing and invariant enforcement — and recognize anti-patterns.

**Time budget:** 45 min reading + 45 min lab.

## Functions vs procedures

| | Function | Procedure |
|---|---|---|
| Created with | `CREATE FUNCTION` | `CREATE PROCEDURE` (PG 11+) |
| Called via   | `SELECT fn(...)` | `CALL proc(...)` |
| Returns value | yes | no (only `OUT` params) |
| Can issue `COMMIT` / `ROLLBACK` | **no** | **yes** (PG 11+) |
| Used in expressions | yes | no |
| Typical use | derived values, helpers, trigger bodies | batch jobs that need explicit tx control |

Picking: default to functions. Reach for procedures when you need to run a long job with multiple transactional checkpoints.

## PL/pgSQL: the language

PL/pgSQL is Postgres's procedural language: a SQL-aware language with variables, control flow, and exceptions. There are other PLs (`plpython3u`, `plv8`, `plpgsql_check`) but PL/pgSQL is the lingua franca.

```sql
CREATE OR REPLACE FUNCTION app.user_order_total(uid bigint)
RETURNS bigint
LANGUAGE plpgsql
STABLE                                    -- declared volatility (see below)
AS $$
DECLARE
    total bigint;
BEGIN
    SELECT coalesce(sum(total_cents), 0)
      INTO total
    FROM app.orders
    WHERE user_id = uid AND status = 'paid';

    IF total IS NULL THEN
        RAISE EXCEPTION 'unexpected NULL for user %', uid;
    END IF;

    RETURN total;
END;
$$;

SELECT app.user_order_total(1);
```

### Volatility categories

| Category | Meaning | Index expressions, planner caching |
|----------|---------|------------------------------------|
| `VOLATILE` (default) | Result may differ between calls within a query | No |
| `STABLE`  | Same result within a single statement | Yes |
| `IMMUTABLE` | Same result for the same inputs forever | Yes (required for expression indexes) |

Always declare the strictest category that is truthful — the planner uses it.

### Parallel safety

Functions that touch session-local state or write data should be `PARALLEL UNSAFE`. Read-only deterministic logic can be `PARALLEL SAFE`. Default is unsafe. See <https://www.postgresql.org/docs/17/parallel-safety.html>.

### Strictness

`STRICT` means: if any argument is NULL, return NULL without entering the body. Cheap, frequently right.

### Exception handling

```sql
BEGIN
    INSERT INTO t(id) VALUES (1);
EXCEPTION
    WHEN unique_violation THEN
        RAISE NOTICE 'already exists';
    WHEN OTHERS THEN
        RAISE;            -- re-raise
END;
```

A `BEGIN ... EXCEPTION ... END` block creates an internal **subtransaction (SAVEPOINT)**. Cheap individually, expensive in tight loops over millions of rows — avoid as a flow-control idiom.

## Triggers

A trigger is a function attached to a table that fires on `INSERT` / `UPDATE` / `DELETE` / `TRUNCATE`. Fire timing and granularity:

| Timing × Level | What you can do |
|----------------|-----------------|
| `BEFORE` `ROW`    | Modify `NEW`, skip the row (`RETURN NULL`), validate. |
| `AFTER`  `ROW`    | React to a row's final state (logging, side tables). |
| `BEFORE` `STATEMENT` | Pre-flight checks once per statement (no `OLD/NEW`). |
| `AFTER`  `STATEMENT` | Bulk reactions (use transition tables, PG 10+). |

```sql
-- BEFORE UPDATE trigger to maintain updated_at
CREATE OR REPLACE FUNCTION app.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

ALTER TABLE app.posts ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

CREATE TRIGGER posts_set_updated_at
BEFORE UPDATE ON app.posts
FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();
```

### Transition tables (PG 10+)

```sql
CREATE TRIGGER orders_audit_stmt
AFTER UPDATE ON app.orders
REFERENCING OLD TABLE AS o_old NEW TABLE AS o_new
FOR EACH STATEMENT
EXECUTE FUNCTION app.log_order_changes();
```

Inside `log_order_changes()`, `o_old` and `o_new` are queryable as tables — much faster than `FOR EACH ROW` for bulk updates.

### Event triggers

A separate kind: fire on DDL events (`ddl_command_start`, `sql_drop`, etc.). Use for schema-wide policies (e.g. forbid `DROP TABLE` outside maintenance windows). Module 11 references them.

## When NOT to use triggers

Triggers are powerful and easy to misuse. Reach for them last.

| Tempting use case | Better solution |
|-------------------|-----------------|
| Maintain a counter (e.g. `posts.comment_count`) | Materialized view + scheduled refresh, or compute on read. Triggers serialize writes through a hot row. |
| Enforce simple invariants                       | `CHECK` / `EXCLUDE` constraints, FKs. |
| Cross-table denormalization                     | View, materialized view, or application-level aggregation. |
| Audit logs                                      | Triggers are acceptable, but consider `pg_audit`/logical decoding for low-overhead capture. |
| Cascading state machines                        | Application code, plus database constraints for the invariants. |

**The triggers test**: if the same table has more than two triggers, the schema is probably trying to enforce business logic that should live in the application or in a SQL function called explicitly.

## Trigger example: enforce inventory invariants

This is a defensible use of triggers: maintain a cached aggregate that the application reads cheaply.

```sql
ALTER TABLE app.products ADD COLUMN IF NOT EXISTS stock_total integer NOT NULL DEFAULT 0;

CREATE OR REPLACE FUNCTION app.refresh_product_stock()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    UPDATE app.products p
       SET stock_total = sub.total
    FROM (
        SELECT product_id, sum(qty) AS total
        FROM app.inventory
        WHERE product_id = coalesce(NEW.product_id, OLD.product_id)
        GROUP BY product_id
    ) sub
    WHERE p.id = sub.product_id;
    RETURN coalesce(NEW, OLD);
END;
$$;

CREATE TRIGGER inventory_refresh_stock
AFTER INSERT OR UPDATE OR DELETE ON app.inventory
FOR EACH ROW EXECUTE FUNCTION app.refresh_product_stock();
```

Why this is OK: the aggregate is small (per product), the table is rarely updated, and the trigger is dead simple. Why this could become a problem: under heavy concurrent updates to the same product the trigger serializes writers on the `products` row. For real workloads, defer the rollup or use an event-sourced log.

## Run the lab

```powershell
psql -U postgres -d pgcourse -f 08-procedures-triggers/lab.sql
```

## References

- PL/pgSQL: <https://www.postgresql.org/docs/17/plpgsql.html>
- Triggers: <https://www.postgresql.org/docs/17/triggers.html>
- Transition tables: <https://www.postgresql.org/docs/17/sql-createtrigger.html#SQL-CREATETRIGGER-TRANSITION-TABLES>

## Next

[Module 09 — Admin &amp; Replication →](../09-admin-replication/)
