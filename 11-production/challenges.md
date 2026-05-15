# Module 11 — Challenges

## 1. Pool sizing: 8 app workers, each opening up to 25 in-process connections. What `default_pool_size` and `max_client_conn` would you set on PgBouncer for a primary with 8 vCPUs?

<details><summary>Solution</summary>

- Physical Postgres connections: `default_pool_size ≈ 2 * CPU = 16`. Add a small `reserve_pool_size`.
- Client side: `max_client_conn = 8 * 25 = 200` minimum; round up to 400 to leave headroom.
PgBouncer queues clients beyond `default_pool_size`. Watch `SHOW POOLS;` for `cl_waiting`.
</details>

## 2. Why does `prepare_threshold=None` matter for psycopg behind PgBouncer transaction mode?

<details><summary>Solution</summary>

In transaction mode, server connections rotate per transaction. A prepared statement created on server A may not exist on server B, raising `prepared statement does not exist`. Disabling prepare avoids the issue. Newer PgBouncer (1.21+) tracks prepared statements server-side; once you're on it you can re-enable client prepares.
</details>

## 3. Write an RLS policy that lets users see their own posts AND any post in the `'Engineering'` category.

<details><summary>Solution</summary>

```sql
CREATE POLICY posts_owner_or_eng ON app.posts
    FOR SELECT
    USING (
        author_id = current_setting('app.user_id', true)::bigint
        OR EXISTS (
            SELECT 1
            FROM app.post_categories pc
            JOIN app.categories c ON c.id = pc.category_id
            WHERE pc.post_id = posts.id AND c.name = 'Engineering'
        )
    );
```
The `EXISTS` form is index-friendly. Verify the policy fires with `EXPLAIN` while running as a non-superuser.
</details>

## 4. The planner runs Seq Scan on a 100GB table for a selective predicate. The disk is NVMe. Which config setting most often fixes this?

<details><summary>Solution</summary>

`random_page_cost`. Default 4.0 reflects spinning disks; NVMe makes random reads cheap, so set `random_page_cost = 1.1` (or even 1.0 on truly fast storage). This stops the planner from preferring sequential scans whenever an index seek requires random I/O.
</details>

## 5. Sketch a zero-downtime migration to add a `NOT NULL` `tier text` column to `app.users` that defaults to `'free'`.

<details><summary>Solution</summary>

1. `ALTER TABLE app.users ADD COLUMN tier text;` — nullable, no rewrite.
2. Backfill in chunks: `UPDATE app.users SET tier='free' WHERE tier IS NULL AND id BETWEEN ... AND ...;` looped.
3. `ALTER TABLE app.users ALTER COLUMN tier SET DEFAULT 'free';` — new rows default.
4. `ALTER TABLE app.users ADD CONSTRAINT users_tier_not_null CHECK (tier IS NOT NULL) NOT VALID;` then `VALIDATE CONSTRAINT users_tier_not_null;` (cheap second pass, no rewrite).
5. `ALTER TABLE app.users ALTER COLUMN tier SET NOT NULL;` — fast because the validated CHECK guarantees no NULLs.
6. Drop the CHECK if you want a clean `NOT NULL`.

Old hack of `ADD COLUMN tier text NOT NULL DEFAULT 'free'` rewrites the entire table in older PG versions. PG 11+ avoids the rewrite for *constant* defaults, but the `NOT NULL` step still requires a table scan; the expand-contract pattern above keeps every step short.
</details>

## 6. Build the alert query: any session in a transaction longer than 10 minutes.

<details><summary>Solution</summary>

```sql
SELECT pid, usename, datname, state, xact_start, now() - xact_start AS age, query
FROM pg_stat_activity
WHERE xact_start IS NOT NULL
  AND now() - xact_start > interval '10 minutes';
```
Wire this into Prometheus/Grafana via `postgres_exporter`'s custom queries.
</details>

## 7. Sync replication: pros and cons in one sentence each.

<details><summary>Solution</summary>

Pros: zero data loss to confirmed commits. Cons: every commit's latency depends on the standby's replay; lose the standby and the primary either blocks or you have to manually disable sync, both of which cost availability.
</details>

## 8. List three things you should never do in transaction-pooling PgBouncer mode.

<details><summary>Solution</summary>

1. `LISTEN`/`NOTIFY` — session feature, not preserved across server swaps.
2. Session-scoped advisory locks (`pg_advisory_lock`) — use `pg_advisory_xact_lock` instead.
3. Temp tables that outlive a transaction. `SET` outside a transaction (`SET LOCAL` inside one is fine).
</details>

## 9. How would you detect that autovacuum is falling behind on `app.orders`?

<details><summary>Solution</summary>

```sql
SELECT n_live_tup, n_dead_tup,
       round(100.0*n_dead_tup / nullif(n_live_tup + n_dead_tup, 0), 2) AS dead_pct,
       last_autovacuum, autovacuum_count
FROM pg_stat_user_tables
WHERE schemaname='app' AND relname='orders';
```
Watch `dead_pct` rising past 20% and `last_autovacuum` falling behind. Reduce `autovacuum_vacuum_scale_factor` on that table.
</details>

## 10. Compare physical streaming replication vs logical replication for a major-version upgrade (17 → 18).

<details><summary>Solution</summary>

Streaming replication is **same major version only** — you cannot stream-WAL across majors. Logical replication can replicate from 17 to 18: stand up an 18 cluster, create a publication on 17, subscribe on 18, wait for catchup, switch traffic. This is the lowest-downtime upgrade path for clusters that can't take a `pg_upgrade` outage window.
</details>
