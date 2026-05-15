# Cheatsheet

## psql meta-commands

| Command | Purpose |
|---------|---------|
| `\?`           | List meta-commands |
| `\h CREATE TABLE` | SQL help for a statement |
| `\l`           | List databases |
| `\c db`        | Connect to database |
| `\dn`          | List schemas |
| `\dt schema.*` | List tables |
| `\di`          | List indexes |
| `\d name`      | Describe table / view / index |
| `\d+ name`     | Describe with size and storage info |
| `\df schema.*` | List functions |
| `\dx`          | List installed extensions |
| `\du`          | List roles |
| `\dp`          | Show privileges |
| `\timing`      | Toggle query timing |
| `\x`           | Toggle expanded output |
| `\e`           | Edit last query in `$EDITOR` |
| `\i file.sql`  | Execute a file |
| `\copy ...`    | Client-side COPY (uses your local filesystem) |
| `\watch 2`     | Re-run last query every 2 seconds |
| `\set VAR val` / `:VAR` | psql variables and substitution |
| `\password user` | Set/change a password securely |
| `\q`           | Quit |

## System catalogs you'll actually use

| Catalog / view | What |
|----------------|------|
| `pg_database`               | databases |
| `pg_namespace`              | schemas |
| `pg_class`                  | tables, indexes, sequences, views |
| `pg_attribute`              | columns |
| `pg_index`                  | index definitions |
| `pg_constraint`             | constraints |
| `pg_proc`                   | functions / procedures |
| `pg_trigger`                | triggers (non-internal: `WHERE NOT tgisinternal`) |
| `pg_extension`              | installed extensions |
| `pg_roles` / `pg_authid`    | roles |
| `pg_locks`                  | currently held / waiting locks |
| `pg_stat_activity`          | live sessions |
| `pg_stat_user_tables`       | per-table counters (autovacuum, dead tuples, scans) |
| `pg_stat_user_indexes`      | per-index scan counts |
| `pg_statio_user_indexes`    | per-index buffer/I-O stats |
| `pg_stat_replication`       | replication lag per standby |
| `pg_stat_statements` (ext)  | top queries by total/mean time |
| `pg_settings`               | live values of GUCs |
| `information_schema.*`      | SQL-standard catalog views |

## Useful one-liners

```sql
-- Size of a table including indexes &amp; TOAST
SELECT pg_size_pretty(pg_total_relation_size('schema.table'));

-- All FKs in a schema
SELECT conrelid::regclass, pg_get_constraintdef(oid)
FROM pg_constraint
WHERE connamespace = 'app'::regnamespace AND contype = 'f';

-- Vacuum a single table
VACUUM (ANALYZE, VERBOSE) schema.table;

-- Reindex a single index online
REINDEX INDEX CONCURRENTLY schema.idx_name;

-- Who's blocking whom
SELECT pid, query, pg_blocking_pids(pid) AS blocked_by
FROM pg_stat_activity
WHERE state != 'idle' AND cardinality(pg_blocking_pids(pid)) > 0;

-- Kill a session politely (cancel query)
SELECT pg_cancel_backend(pid) FROM pg_stat_activity WHERE pid = 12345;

-- Force-kill a session
SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE pid = 12345;
```

## EXPLAIN starter recipe

```sql
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, FORMAT TEXT)
<your query>;
```

Read top-down. Compare `rows=` (estimated) to `actual rows=`. Big mismatch → run `ANALYZE` or add extended statistics.

## libpq env vars

Used by `psql` and most clients:

```
PGHOST, PGPORT, PGUSER, PGPASSWORD, PGDATABASE,
PGSSLMODE, PGSSLROOTCERT, PGCONNECT_TIMEOUT,
PGAPPNAME, PGSERVICE, PGSERVICEFILE, PGPASSFILE
```

## ANN search (pgvector)

```sql
-- Cosine, top 10
SELECT id FROM rag.chunks
ORDER BY embedding <=> '[...]'::vector LIMIT 10;

-- Query-time recall knob
SET LOCAL hnsw.ef_search = 100;

-- Operators
-- <->  L2     vector_l2_ops
-- <#>  -dot   vector_ip_ops
-- <=>  cosine vector_cosine_ops
```
