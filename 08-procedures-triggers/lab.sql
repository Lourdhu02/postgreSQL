-- 08-procedures-triggers/lab.sql
SET search_path = app, public;

------------------------------------------------------------
-- 1. Simple PL/pgSQL function
------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.user_order_total(uid bigint)
RETURNS bigint
LANGUAGE plpgsql
STABLE
PARALLEL SAFE
AS $$
DECLARE total bigint;
BEGIN
    SELECT coalesce(sum(total_cents), 0)
      INTO total
    FROM app.orders
    WHERE user_id = uid AND status = 'paid';
    RETURN total;
END;
$$;

SELECT id, email, app.user_order_total(id) AS paid_revenue_cents
FROM users
ORDER BY paid_revenue_cents DESC
LIMIT 5;

------------------------------------------------------------
-- 2. SQL function (faster, fewer surprises when the body is one query)
------------------------------------------------------------
-- WHY: pure SQL functions can be inlined by the planner.
CREATE OR REPLACE FUNCTION app.user_order_total_sql(uid bigint)
RETURNS bigint
LANGUAGE sql
STABLE
PARALLEL SAFE
AS $$
    SELECT coalesce(sum(total_cents), 0)
    FROM app.orders WHERE user_id = uid AND status = 'paid';
$$;

------------------------------------------------------------
-- 3. Procedure with COMMIT (PG 11+)
------------------------------------------------------------
-- WHY: long batch jobs commit periodically so they don't bloat the WAL.
CREATE OR REPLACE PROCEDURE app.archive_old_comments(cutoff timestamptz, batch int DEFAULT 100)
LANGUAGE plpgsql AS $$
DECLARE
    deleted_n int;
BEGIN
    LOOP
        WITH del AS (
            DELETE FROM comments
            WHERE id IN (
                SELECT id FROM comments
                WHERE created_at < cutoff
                ORDER BY id
                LIMIT batch
                FOR UPDATE SKIP LOCKED
            )
            RETURNING 1
        )
        SELECT count(*) INTO deleted_n FROM del;
        COMMIT;
        EXIT WHEN deleted_n = 0;
    END LOOP;
END;
$$;

-- CALL app.archive_old_comments(timestamptz '2024-04-15');

------------------------------------------------------------
-- 4. BEFORE UPDATE trigger: maintain updated_at
------------------------------------------------------------
ALTER TABLE posts ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

CREATE OR REPLACE FUNCTION app.tg_set_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS posts_set_updated_at ON posts;
CREATE TRIGGER posts_set_updated_at
BEFORE UPDATE ON posts
FOR EACH ROW EXECUTE FUNCTION app.tg_set_updated_at();

UPDATE posts SET title = title WHERE id = 1;  -- no-op update; trigger still fires
SELECT id, updated_at FROM posts WHERE id = 1;

------------------------------------------------------------
-- 5. AFTER INSERT trigger: audit table
------------------------------------------------------------
CREATE TABLE IF NOT EXISTS app.audit_log (
    id          bigserial PRIMARY KEY,
    table_name  text NOT NULL,
    action      text NOT NULL,
    row_pk      jsonb NOT NULL,
    payload     jsonb,
    actor       text DEFAULT current_user,
    happened_at timestamptz DEFAULT now()
);

CREATE OR REPLACE FUNCTION app.tg_audit_orders()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO app.audit_log (table_name, action, row_pk, payload)
    VALUES ('orders', TG_OP,
            jsonb_build_object('id', NEW.id),
            to_jsonb(NEW));
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS orders_audit ON orders;
CREATE TRIGGER orders_audit
AFTER INSERT ON orders
FOR EACH ROW EXECUTE FUNCTION app.tg_audit_orders();

INSERT INTO orders (user_id, status, total_cents) VALUES (1, 'pending', 4200);
SELECT * FROM app.audit_log ORDER BY id DESC LIMIT 1;

------------------------------------------------------------
-- 6. AFTER STATEMENT trigger with transition tables
------------------------------------------------------------
-- WHY: cheaper than per-row triggers when bulk updates touch many rows.
CREATE OR REPLACE FUNCTION app.tg_log_order_changes()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO app.audit_log (table_name, action, row_pk, payload)
    SELECT 'orders', 'BULK_UPDATE',
           jsonb_build_object('id', n.id),
           jsonb_build_object('old', to_jsonb(o), 'new', to_jsonb(n))
    FROM o_old o JOIN o_new n ON n.id = o.id
    WHERE o IS DISTINCT FROM n;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS orders_log_stmt ON orders;
CREATE TRIGGER orders_log_stmt
AFTER UPDATE ON orders
REFERENCING OLD TABLE AS o_old NEW TABLE AS o_new
FOR EACH STATEMENT EXECUTE FUNCTION app.tg_log_order_changes();

UPDATE orders SET status = 'shipped' WHERE status = 'paid' AND id <= 10;
SELECT count(*) FROM app.audit_log WHERE action = 'BULK_UPDATE';

------------------------------------------------------------
-- 7. RAISE EXCEPTION to enforce a complex invariant
------------------------------------------------------------
-- WHY: a CHECK constraint can't reference another row; a trigger can.
CREATE OR REPLACE FUNCTION app.tg_no_self_reply()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE parent_author bigint;
BEGIN
    IF NEW.parent_comment_id IS NULL THEN
        RETURN NEW;
    END IF;
    SELECT author_id INTO parent_author
    FROM comments WHERE id = NEW.parent_comment_id;
    IF parent_author = NEW.author_id THEN
        RAISE EXCEPTION 'authors may not reply to themselves'
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS comments_no_self_reply ON comments;
CREATE TRIGGER comments_no_self_reply
BEFORE INSERT ON comments
FOR EACH ROW EXECUTE FUNCTION app.tg_no_self_reply();

-- The next insert is a self-reply: the trigger raises and the row is rejected.
DO $$
BEGIN
    INSERT INTO comments (post_id, author_id, parent_comment_id, body)
    VALUES (1,
            (SELECT author_id FROM comments WHERE id = 1),
            1,
            'self-reply, should fail');
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'expected rejection: %', SQLERRM;
END $$;

------------------------------------------------------------
-- 8. Listing triggers and functions
------------------------------------------------------------
SELECT event_object_table AS table_name, trigger_name, event_manipulation, action_timing
FROM information_schema.triggers
WHERE trigger_schema = 'app'
ORDER BY table_name, trigger_name;

SELECT n.nspname AS schema, p.proname AS function_name, l.lanname AS language
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
JOIN pg_language  l ON l.oid = p.prolang
WHERE n.nspname = 'app'
ORDER BY function_name;
