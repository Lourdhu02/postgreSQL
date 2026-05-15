-- 11-production/lab.sql
SET search_path = app, public;

------------------------------------------------------------
-- 1. Row-Level Security on app.posts
------------------------------------------------------------
-- WHY: every user can only see/modify their own posts when policies are on.
ALTER TABLE posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE posts FORCE ROW LEVEL SECURITY;   -- applies to the table owner too

DROP POLICY IF EXISTS posts_owner_select ON posts;
CREATE POLICY posts_owner_select ON posts
    FOR SELECT
    USING (author_id = current_setting('app.user_id', true)::bigint);

DROP POLICY IF EXISTS posts_owner_modify ON posts;
CREATE POLICY posts_owner_modify ON posts
    FOR ALL
    USING      (author_id = current_setting('app.user_id', true)::bigint)
    WITH CHECK (author_id = current_setting('app.user_id', true)::bigint);

-- Try it: act as user 7 inside one transaction.
BEGIN;
    SET LOCAL app.user_id = '7';
    SELECT id, author_id, title FROM posts ORDER BY id LIMIT 5;  -- only author 7's rows
COMMIT;

-- Without setting app.user_id, current_setting returns '' and the cast errors.
-- Disable to continue the rest of the lab unhindered:
ALTER TABLE posts DISABLE ROW LEVEL SECURITY;

------------------------------------------------------------
-- 2. Configuration introspection
------------------------------------------------------------
SELECT name, setting, unit, source, context
FROM pg_settings
WHERE name IN (
    'shared_buffers','effective_cache_size','work_mem','maintenance_work_mem',
    'max_connections','random_page_cost','effective_io_concurrency',
    'wal_compression','checkpoint_completion_target','autovacuum_vacuum_scale_factor'
)
ORDER BY name;

------------------------------------------------------------
-- 3. Slow / heavy queries via pg_stat_statements (if installed)
------------------------------------------------------------
-- SELECT
--     round(total_exec_time::numeric / 1000, 2) AS total_s,
--     calls,
--     round(mean_exec_time::numeric, 2)        AS mean_ms,
--     round((100*total_exec_time / sum(total_exec_time) OVER ())::numeric, 2) AS pct,
--     left(query, 200) AS query
-- FROM pg_stat_statements
-- ORDER BY total_exec_time DESC
-- LIMIT 20;

------------------------------------------------------------
-- 4. WAL position and replication lag (run on primary)
------------------------------------------------------------
SELECT pg_current_wal_lsn() AS current_lsn;

-- SELECT application_name, state, sync_state,
--        pg_wal_lsn_diff(sent_lsn, replay_lsn) AS replay_bytes_behind,
--        (now() - reply_time) AS reply_age
-- FROM pg_stat_replication;

------------------------------------------------------------
-- 5. Long-running transactions (a frequent prod incident root cause)
------------------------------------------------------------
SELECT pid, now() - xact_start AS xact_age, state, left(query, 200) AS query
FROM pg_stat_activity
WHERE state != 'idle' AND xact_start IS NOT NULL
  AND now() - xact_start > interval '5 minutes'
ORDER BY xact_age DESC;

------------------------------------------------------------
-- 6. Bloat-ish quick check on the heaviest table
------------------------------------------------------------
SELECT relname,
       n_live_tup, n_dead_tup,
       round(100.0*n_dead_tup / nullif(n_live_tup + n_dead_tup, 0), 2) AS dead_pct,
       pg_size_pretty(pg_total_relation_size(format('%I.%I', schemaname, relname)::regclass)) AS total
FROM pg_stat_user_tables
WHERE schemaname = 'app'
ORDER BY dead_pct DESC NULLS LAST
LIMIT 5;
