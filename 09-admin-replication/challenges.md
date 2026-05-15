# Module 09 — Challenges

## 1. Create a read-only role that can `SELECT` only from `app.users` and nothing else.

<details><summary>Solution</summary>

```sql
CREATE ROLE users_reader NOLOGIN;
GRANT CONNECT ON DATABASE pgcourse TO users_reader;
GRANT USAGE   ON SCHEMA app TO users_reader;
GRANT SELECT  ON app.users  TO users_reader;
-- Verify
SELECT has_table_privilege('users_reader', 'app.users', 'SELECT');   -- t
SELECT has_table_privilege('users_reader', 'app.posts', 'SELECT');   -- f
```
</details>

## 2. Dump only the `app` schema (no data) for code review.

<details><summary>Solution</summary>

```powershell
pg_dump -U postgres -n app --schema-only -f schema.sql pgcourse
```
</details>

## 3. Restore a custom-format dump in parallel.

<details><summary>Solution</summary>

```powershell
pg_restore -U postgres -d pgcourse_new --create --jobs=4 pgcourse.dump
```
`--jobs` runs multiple worker processes; works only against the custom (`-Fc`) or directory (`-Fd`) formats, not plain SQL.
</details>

## 4. Find tables with > 20% dead tuples.

<details><summary>Solution</summary>

```sql
SELECT schemaname, relname,
       round(100.0 * n_dead_tup / nullif(n_live_tup + n_dead_tup, 0), 2) AS dead_pct,
       n_dead_tup, last_autovacuum
FROM pg_stat_user_tables
WHERE n_live_tup + n_dead_tup > 0
  AND n_dead_tup * 1.0 / (n_live_tup + n_dead_tup) > 0.2
ORDER BY dead_pct DESC;
```
</details>

## 5. Find queries that have run more than 1000 times with mean execution time > 100ms.

<details><summary>Solution</summary>

```sql
SELECT calls, mean_exec_time, total_exec_time, left(query, 200) AS query
FROM pg_stat_statements
WHERE calls > 1000 AND mean_exec_time > 100
ORDER BY total_exec_time DESC
LIMIT 20;
```
Requires the `pg_stat_statements` extension and `shared_preload_libraries` to include it. Check with `SHOW shared_preload_libraries;`.
</details>

## 6. Partition `lab09.events` by month and confirm the planner prunes.

<details><summary>Solution</summary>

See `lab.sql` section 8. To confirm pruning:
```sql
EXPLAIN SELECT * FROM lab09.events WHERE occurred_at = '2025-06-15';
-- Append node should reference only events_2025_06.
```
</details>

## 7. Drop the `events_2025_06` partition without affecting other partitions.

<details><summary>Solution</summary>

```sql
ALTER TABLE lab09.events DETACH PARTITION lab09.events_2025_06;
DROP TABLE lab09.events_2025_06;
-- DETACH CONCURRENTLY in PG 14+ is preferred for online operations.
```
</details>

## 8. Stream replication lag inspection. What query do you run on the primary?

<details><summary>Solution</summary>

```sql
SELECT application_name, client_addr, state, sync_state,
       pg_wal_lsn_diff(sent_lsn, replay_lsn)    AS replay_bytes_behind,
       (now() - reply_time)                     AS reply_age
FROM pg_stat_replication;
```
</details>

## 9. Streaming vs logical replication: when to pick logical?

<details><summary>Solution</summary>

Pick **logical** when you want a subset of tables/columns/rows, when you are replicating to a different major version, or when you need to keep the subscriber writable (different schema, different aggregations). Streaming is simpler and faster for whole-cluster HA where the standby is identical to the primary.
</details>

## 10. What's the difference between `pg_terminate_backend(pid)` and `pg_cancel_backend(pid)`?

<details><summary>Solution</summary>

`pg_cancel_backend` sends SIGINT — the current query is cancelled but the session stays connected. `pg_terminate_backend` sends SIGTERM — the entire backend (session) is killed. Prefer cancel; reach for terminate when a session is unresponsive or holding a problem transaction. Reference: <https://www.postgresql.org/docs/17/functions-admin.html#FUNCTIONS-ADMIN-SIGNAL>.
</details>
