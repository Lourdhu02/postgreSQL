# Module 00 — Challenges

Run answers in `psql -U postgres -d pgcourse`. Set `SET search_path = app, public;` first.

## 1. Find your server's data directory

Hint: there is a `SHOW` command for server settings.

<details><summary>Solution</summary>

```sql
SHOW data_directory;
SHOW config_file;
```
</details>

## 2. List every schema in the current database except the system ones

Hint: `pg_catalog` and `information_schema` are system schemas.

<details><summary>Solution</summary>

```sql
SELECT schema_name
FROM information_schema.schemata
WHERE schema_name NOT IN ('pg_catalog','information_schema')
  AND schema_name NOT LIKE 'pg_%';
```
</details>

## 3. Show the size of the `pgcourse` database and the size of the `app.posts` table

<details><summary>Solution</summary>

```sql
SELECT pg_size_pretty(pg_database_size('pgcourse')) AS db_size;
SELECT pg_size_pretty(pg_total_relation_size('app.posts')) AS posts_total;
```
</details>

## 4. What is the difference between `pg_relation_size` and `pg_total_relation_size`?

<details><summary>Solution</summary>

`pg_relation_size` returns only the size of the main fork (the heap) of a table. `pg_total_relation_size` includes the heap, all indexes, and TOAST data. Docs: <https://www.postgresql.org/docs/17/functions-admin.html#FUNCTIONS-ADMIN-DBOBJECT>.
</details>

## 5. List the five most recently created users by `created_at`

<details><summary>Solution</summary>

```sql
SELECT id, email, created_at
FROM app.users
ORDER BY created_at DESC
LIMIT 5;
```
</details>

## 6. Connect with `psql` using a `service` file instead of typing the password

Hint: see <https://www.postgresql.org/docs/17/libpq-pgservice.html>.

<details><summary>Solution</summary>

Create `~/.pg_service.conf` (or `%APPDATA%\postgresql\.pg_service.conf` on Windows):
```ini
[pgcourse]
host=localhost
port=5432
user=postgres
dbname=pgcourse
```
Then connect with `psql service=pgcourse`. Password can go in `~/.pgpass` (mode 600).
</details>

## 7. Show the list of all currently connected sessions

<details><summary>Solution</summary>

```sql
SELECT pid, usename, datname, application_name, client_addr, state
FROM pg_stat_activity
WHERE datname = current_database();
```
</details>
