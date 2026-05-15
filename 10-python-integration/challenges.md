# Module 10 — Challenges

## 1. Why is f-string SQL building dangerous? Give the safe equivalent.

<details><summary>Solution</summary>

```python
# UNSAFE — SQL injection
cur.execute(f"SELECT * FROM app.users WHERE email = '{email}'")

# SAFE — parameters are sent separately and never interpolated into the query string
cur.execute("SELECT * FROM app.users WHERE email = %s", (email,))
```
Identifiers (table/column names) can't be parameterized. For trusted identifiers use `psycopg.sql.Identifier`, never user input.
</details>

## 2. Use psycopg 3 `COPY` to bulk-load 10000 rows into a temp table.

<details><summary>Solution</summary>

```python
with psycopg.connect(dsn) as conn:
    with conn.cursor() as cur:
        cur.execute("CREATE TEMP TABLE bulk_demo (id int, v text)")
        with cur.copy("COPY bulk_demo (id, v) FROM STDIN") as cp:
            for i in range(10000):
                cp.write_row((i, f"row-{i}"))
        cur.execute("SELECT count(*) FROM bulk_demo")
        print(cur.fetchone())
    conn.commit()
```
</details>

## 3. Convert this SQLAlchemy 1.x style to 2.x:
```python
session.query(User).filter(User.id == 1).first()
```

<details><summary>Solution</summary>

```python
from sqlalchemy import select
session.scalars(select(User).where(User.id == 1)).first()
```
2.x `select(...)` works for both ORM and Core and is the recommended idiom.
</details>

## 4. Configure an asyncpg pool with `min_size=2`, `max_size=10`, statement-cache disabled, and execute one query.

<details><summary>Solution</summary>

```python
import asyncpg, asyncio

async def main():
    pool = await asyncpg.create_pool(
        dsn="postgresql://postgres:pw@localhost/pgcourse",
        min_size=2, max_size=10,
        statement_cache_size=0,        # required behind PgBouncer transaction mode
    )
    async with pool.acquire() as conn:
        print(await conn.fetchval("SELECT version()"))
    await pool.close()

asyncio.run(main())
```
</details>

## 5. Why disable the asyncpg statement cache when running behind PgBouncer in transaction mode?

<details><summary>Solution</summary>

PgBouncer in transaction mode multiplexes many client sessions onto a small number of Postgres backends. Prepared statements are tied to a backend's session state; a client preparing a statement and then reusing it via a different backend will get `prepared statement "__asyncpg_stmt_X__" does not exist`. Disabling the cache avoids that. Alternatives: PgBouncer 1.21+ supports server-side prepared statements with `server_reset_query_always = 0`.
</details>

## 6. Write an Alembic migration that adds a `published_count` column to `app.users` defaulting to `0`.

<details><summary>Solution</summary>

```python
def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column("published_count", sa.Integer, nullable=False, server_default="0"),
        schema="app",
    )

def downgrade() -> None:
    op.drop_column("users", "published_count", schema="app")
```
`server_default="0"` lets Postgres handle the default during the migration so existing rows are filled without an `UPDATE`.
</details>

## 7. Pool sizing: you have 4 worker processes, each with an in-process pool of size 25. PgBouncer in front. How many physical Postgres connections do you actually need?

<details><summary>Solution</summary>

In-process pools open `4 * 25 = 100` client connections to PgBouncer. PgBouncer in transaction mode then multiplexes them onto its **default_pool_size** physical Postgres connections. A reasonable budget is `2 * CPU cores` of physical connections (often 16–32), regardless of how many client connections PgBouncer fronts.
</details>

## 8. The ORM raises `DetachedInstanceError` when accessing `user.posts` after the session closed. Two fixes.

<details><summary>Solution</summary>

1. Eager-load while the session is open: `session.scalars(select(User).options(selectinload(User.posts)).where(...))`.
2. Open the session for the lifetime of the work (per-request session) and access lazy attrs before leaving its scope.
</details>

## 9. What does `Session.expire_on_commit=False` change?

<details><summary>Solution</summary>

After `commit()`, SQLAlchemy by default marks every loaded attribute as expired so the next access triggers a refresh from the DB (avoiding stale reads). `expire_on_commit=False` keeps the in-memory values, which is what you want when the session is short-lived and you're about to return objects to the caller.
</details>

## 10. Streaming a million rows from Python without OOM: which feature?

<details><summary>Solution</summary>

A **server-side cursor** in psycopg (named cursor) or `SELECT ... FETCH ... CURSOR FOR` directly. SQLAlchemy exposes this via `stream_results=True` execution option (uses a server-side cursor under the hood). Don't `cur.fetchall()` a million-row result set.
</details>
