-- 09-admin-replication/lab.sql
-- Most of this module is conceptual + operational. The SQL below shows the
-- inspection queries you'll reach for in production. The CREATE PUBLICATION
-- / SUBSCRIPTION blocks are illustrative; run them only if you have a real
-- second cluster.
SET search_path = app, public;

------------------------------------------------------------
-- 1. Inspect roles and privileges
------------------------------------------------------------
SELECT rolname, rolcanlogin, rolsuper, rolcreatedb, rolcreaterole
FROM pg_roles
ORDER BY rolname;

SELECT table_schema, table_name, grantee, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'app' AND grantee NOT IN ('postgres')
ORDER BY table_name, grantee;

------------------------------------------------------------
-- 2. Create least-privilege roles for the course (idempotent)
------------------------------------------------------------
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_ro') THEN
        CREATE ROLE app_ro NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_rw') THEN
        CREATE ROLE app_rw NOLOGIN;
    END IF;
END $$;

GRANT CONNECT ON DATABASE pgcourse TO app_ro, app_rw;
GRANT USAGE   ON SCHEMA   app      TO app_ro, app_rw;
GRANT SELECT                         ON ALL TABLES    IN SCHEMA app TO app_ro;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES    IN SCHEMA app TO app_rw;
GRANT USAGE, SELECT                  ON ALL SEQUENCES IN SCHEMA app TO app_rw;

ALTER DEFAULT PRIVILEGES IN SCHEMA app
    GRANT SELECT ON TABLES TO app_ro;
ALTER DEFAULT PRIVILEGES IN SCHEMA app
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_rw;

------------------------------------------------------------
-- 3. Live cluster health: who is connected and what are they doing
------------------------------------------------------------
SELECT pid, datname, usename, application_name, client_addr,
       state, wait_event_type, wait_event,
       (now() - xact_start) AS xact_age,
       left(query, 80) AS query
FROM pg_stat_activity
WHERE datname = current_database();

------------------------------------------------------------
-- 4. Database / table sizes
------------------------------------------------------------
SELECT pg_size_pretty(pg_database_size(current_database())) AS db_size;

SELECT relname, pg_size_pretty(pg_total_relation_size(c.oid)) AS total,
       pg_size_pretty(pg_relation_size(c.oid))                AS heap
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'app' AND c.relkind = 'r'
ORDER BY pg_total_relation_size(c.oid) DESC;

------------------------------------------------------------
-- 5. Autovacuum health on app tables
------------------------------------------------------------
SELECT relname,
       n_live_tup, n_dead_tup,
       round(100.0 * n_dead_tup / nullif(n_live_tup + n_dead_tup, 0), 2) AS dead_pct,
       last_autovacuum, last_autoanalyze
FROM pg_stat_user_tables
WHERE schemaname = 'app'
ORDER BY dead_pct DESC NULLS LAST;

------------------------------------------------------------
-- 6. Index hit ratio
------------------------------------------------------------
SELECT relname,
       sum(idx_blks_hit)::bigint   AS hit,
       sum(idx_blks_read)::bigint  AS read,
       round(sum(idx_blks_hit)::numeric / nullif(sum(idx_blks_hit + idx_blks_read), 0), 4) AS hit_ratio
FROM pg_statio_user_indexes
WHERE schemaname = 'app'
GROUP BY relname
ORDER BY hit_ratio NULLS LAST;

------------------------------------------------------------
-- 7. pg_stat_statements (extension)
------------------------------------------------------------
-- WHY: top queries by total time. Requires shared_preload_libraries='pg_stat_statements'
-- in postgresql.conf and a server restart. Once installed:
-- CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
--
-- SELECT calls, mean_exec_time, total_exec_time, query
-- FROM pg_stat_statements
-- ORDER BY total_exec_time DESC
-- LIMIT 10;

------------------------------------------------------------
-- 8. Partitioning demo (sandbox table)
------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS lab09;

CREATE TABLE IF NOT EXISTS lab09.events (
    id bigserial,
    user_id bigint NOT NULL,
    occurred_at timestamptz NOT NULL,
    payload jsonb NOT NULL,
    PRIMARY KEY (id, occurred_at)
) PARTITION BY RANGE (occurred_at);

CREATE TABLE IF NOT EXISTS lab09.events_2025_06 PARTITION OF lab09.events
    FOR VALUES FROM ('2025-06-01') TO ('2025-07-01');
CREATE TABLE IF NOT EXISTS lab09.events_2025_07 PARTITION OF lab09.events
    FOR VALUES FROM ('2025-07-01') TO ('2025-08-01');

INSERT INTO lab09.events (user_id, occurred_at, payload) VALUES
    (1, '2025-06-15', '{"k":"click"}'),
    (1, '2025-07-02', '{"k":"view"}');

-- Verify partition pruning
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM lab09.events
WHERE occurred_at >= '2025-06-10' AND occurred_at < '2025-06-20';
-- Look for "Append" + only the matching child being scanned.

------------------------------------------------------------
-- 9. Logical replication objects (illustrative — do not run unless you have a subscriber)
------------------------------------------------------------
-- -- On publisher:
-- CREATE PUBLICATION app_pub FOR TABLE app.orders, app.order_items;
-- -- On subscriber (matching schema must already exist):
-- CREATE SUBSCRIPTION app_sub
--     CONNECTION 'host=primary user=replicator password=... dbname=pgcourse'
--     PUBLICATION app_pub;

------------------------------------------------------------
-- 10. Force a manual VACUUM + ANALYZE (illustrative)
------------------------------------------------------------
-- VACUUM (ANALYZE, VERBOSE) app.posts;
