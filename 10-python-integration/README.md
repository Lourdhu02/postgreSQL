# 10 — Python Integration

By the end you can:
1. Connect to Postgres from Python with `psycopg` (sync), `asyncpg` (async), and SQLAlchemy 2.x (Core + ORM).
2. Use connection pooling correctly (in-process pool vs PgBouncer) and avoid the classic pitfalls.
3. Manage schema with Alembic migrations.

**Time budget:** 60 min reading + 75 min lab.

## The four drivers you actually need

| Library | Style | Why use it |
|---------|-------|------------|
| **psycopg 3** | sync (and asyncio) | Modern Python driver. Replaces psycopg2. Pipelining, server-side cursors, native UUID/JSON. |
| **asyncpg**   | async (no DB-API) | Highest-throughput async driver. Used directly or via SQLAlchemy. |
| **SQLAlchemy 2.x** | sync + async, Core + ORM | Declarative models, query construction, dialect-portable, async support over `asyncpg`/psycopg. |
| **Alembic**   | migrations | The de-facto migration framework for SQLAlchemy. |

Pick by use case:

| Task | Use |
|------|-----|
| Raw SQL, one-off scripts, ETL | `psycopg` (sync) |
| High-fanout async service (websockets, agents) | `asyncpg` directly, or SQLAlchemy async |
| ORM-heavy CRUD app | SQLAlchemy 2.x |
| Schema evolution (CI/CD) | Alembic |

## Setup

`.env` (from `.env.example`):
```
DATABASE_URL=postgresql+psycopg://postgres:change_me@localhost:5432/pgcourse
DATABASE_URL_ASYNC=postgresql+asyncpg://postgres:change_me@localhost:5432/pgcourse
```

```powershell
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

## psycopg 3: sync

```python
import psycopg
from psycopg.rows import dict_row

with psycopg.connect("postgresql://postgres:pw@localhost/pgcourse",
                     row_factory=dict_row,
                     autocommit=False) as conn:
    with conn.cursor() as cur:
        cur.execute(
            "SELECT id, email FROM app.users WHERE id = %s",
            (1,),                              # parameters tuple — never f-string
        )
        for row in cur:
            print(row)
    conn.commit()
```

Critical rules:
- **Always parameterize.** Never `f"... {value}"`. Always `%s` placeholders or named (`%(name)s`).
- **Context managers**: `with psycopg.connect(...) as conn` commits on exit unless an exception occurred (then rolls back) and closes the connection. `with conn.cursor() as cur` closes the cursor.
- `autocommit=False` (the default in psycopg 3) means you must `commit()`. Use `autocommit=True` for one-shot reads or DDL outside a transaction.

### Bulk inserts: `copy`

`COPY` is by far the fastest way to load rows. psycopg 3 exposes it directly:
```python
with cur.copy("COPY app.events (user_id, occurred_at, payload) FROM STDIN") as cp:
    for row in rows:                    # iterable of tuples
        cp.write_row(row)
```

For 100k+ rows this is 10–50x faster than executemany.

### Server-side cursors

For streaming millions of rows without loading them all in memory:
```python
with conn.cursor(name="big") as cur:    # named => server-side
    cur.itersize = 5_000
    cur.execute("SELECT id, body FROM app.posts")
    for row in cur:
        process(row)
```

## asyncpg

```python
import asyncpg, asyncio

async def main():
    pool = await asyncpg.create_pool("postgresql://postgres:pw@localhost/pgcourse",
                                     min_size=2, max_size=10)
    async with pool.acquire() as conn:
        rows = await conn.fetch("SELECT id, email FROM app.users WHERE id = $1", 1)
        print(rows)
    await pool.close()

asyncio.run(main())
```

Notes:
- asyncpg uses `$1, $2` placeholders (not `%s`).
- It does **not** speak the DB-API. SQLAlchemy abstracts that.
- Built-in pool — use it. Don't create a fresh connection per request.

## SQLAlchemy 2.x

Two layers:
- **Core**: SQL expression language. Tables, columns, statements.
- **ORM**: maps Python classes to tables. Uses Core internally.

### Engine and session

```python
from sqlalchemy import create_engine, select
from sqlalchemy.orm import Session, DeclarativeBase, Mapped, mapped_column
from datetime import datetime

engine = create_engine(os.environ["DATABASE_URL"], pool_size=5, max_overflow=10)

class Base(DeclarativeBase): pass

class User(Base):
    __tablename__ = "users"
    __table_args__ = {"schema": "app"}
    id: Mapped[int] = mapped_column(primary_key=True)
    email: Mapped[str]
    full_name: Mapped[str]
    created_at: Mapped[datetime]

with Session(engine) as session:
    stmt = select(User).where(User.id == 1)
    user = session.scalars(stmt).one()
    print(user.email)
```

### Async

```python
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession

engine = create_async_engine(os.environ["DATABASE_URL_ASYNC"])
async with AsyncSession(engine) as session:
    result = await session.scalars(select(User).where(User.id == 1))
    print(result.one().email)
```

### Pitfalls

| Trap | Fix |
|------|-----|
| Lazy loading inside a closed session (`DetachedInstanceError`) | Use `selectinload`/`joinedload`, or load attributes before leaving the session. |
| Inserting many rows one-by-one | `session.execute(insert(User), [{"email": ...}, ...])` or use `COPY` via psycopg. |
| Long transactions | Don't hold a session open across HTTP requests. Use a per-request session. |
| ORM identity map confusion | After `session.commit()`, attributes are expired; re-access triggers a refresh. Set `expire_on_commit=False` if you really need to keep stale values. |

## Connection pooling

A new TCP + auth handshake to Postgres takes a few ms. At scale that dominates request latency.

```mermaid
flowchart LR
    A[App workers] -- many short-lived ops --> B[(In-process pool)]
    B -- N persistent conns --> PG[(Postgres)]
    A2[Many app workers] -- transactional ops --> P[(PgBouncer transaction-pooling)]
    P -- small N --> PG
```

Two layers:

1. **In-process pool** (SQLAlchemy `pool_size`, `asyncpg.create_pool`, `psycopg_pool`). Keeps connections warm in the worker.
2. **PgBouncer** (external, transaction-pooled by default). Lets you scale `N_workers * pool_size` clients onto a small physical-connection budget. See module 11.

### Common pitfalls

- **Don't share connections across coroutines / threads.** Acquire from the pool.
- **PgBouncer in transaction mode disables session-scoped features** — prepared statements (default in asyncpg), `LISTEN/NOTIFY`, advisory locks, `SET LOCAL` outside a tx, temp tables. Work around with `statement_cache_size=0` (asyncpg) or `prepare_threshold=None` (psycopg) for `transaction` mode.
- **Pool sizing**: start at `min(2 * CPUs, 50)` and watch `pg_stat_activity`. Too many connections degrade Postgres performance.

## Alembic migrations

Alembic generates and applies versioned migration scripts. Wire it to your SQLAlchemy metadata so `--autogenerate` can diff your code against the live DB.

```
alembic.ini
migrations/
  env.py
  versions/
    20260101_120000_initial.py
```

```python
# migrations/versions/20260101_120000_initial.py
def upgrade() -> None:
    op.create_table("users",
        sa.Column("id", sa.BigInteger, primary_key=True),
        sa.Column("email", sa.Text, nullable=False, unique=True),
        schema="app",
    )

def downgrade() -> None:
    op.drop_table("users", schema="app")
```

```powershell
alembic init migrations
alembic revision --autogenerate -m "initial"
alembic upgrade head
```

Rules of the road:
- **Always review** auto-generated migrations. Alembic can miss CHECK constraints, partial indexes, generated columns.
- Migrations must be **idempotent in spirit**: a failed deploy must be safe to re-run.
- For zero-downtime in production, follow expand-contract: add nullable, backfill, swap reads, then drop old. See module 11.

## Run the lab

`10-python-integration/lab.ipynb` walks through all four drivers end-to-end.

```powershell
jupyter lab
```

## References

- psycopg 3: <https://www.psycopg.org/psycopg3/docs/>
- asyncpg: <https://magicstack.github.io/asyncpg/current/>
- SQLAlchemy 2.x: <https://docs.sqlalchemy.org/en/20/>
- Alembic: <https://alembic.sqlalchemy.org/en/latest/>
- PgBouncer caveats: <https://www.pgbouncer.org/features.html>

## Next

[Module 11 — Production →](../11-production/)
