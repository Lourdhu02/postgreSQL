# Module 05 — Challenges

## 1. What isolation level is the session running at right now?

<details><summary>Solution</summary>

```sql
SHOW default_transaction_isolation;          -- session default
SELECT current_setting('transaction_isolation'); -- current transaction
```
</details>

## 2. Write a money-transfer transaction that is safe under Read Committed.

<details><summary>Solution</summary>

```sql
BEGIN;
UPDATE lab05_accounts SET balance = balance - 50 WHERE id = 1;
UPDATE lab05_accounts SET balance = balance + 50 WHERE id = 2;
COMMIT;
```
Both arithmetic and the `CHECK (balance >= 0)` are atomic. Don't read-then-decide in the app — let SQL do the math.
</details>

## 3. Explain the difference between `FOR UPDATE` and `FOR NO KEY UPDATE` in a sentence.

<details><summary>Solution</summary>

`FOR UPDATE` blocks anyone wanting to modify the row's key columns (including FK references). `FOR NO KEY UPDATE` only blocks updates to non-key columns; FK-referencing inserts on child tables can proceed. Prefer `FOR NO KEY UPDATE` when you won't change the PK.
</details>

## 4. Why can `SERIALIZABLE` cause your app to receive a `40001` error, and what should the app do?

<details><summary>Solution</summary>

SSI detects that committing all running serializable transactions would violate serializability and aborts one. The app should catch SQLSTATE `40001`, sleep a short jittered backoff (e.g. 20–100 ms), and retry the entire transaction (not just the failing statement). All side-effects must live inside the transaction so retries are safe.
</details>

## 5. Spot the deadlock-prone pattern below and fix it.
```sql
-- Worker 1
BEGIN;
UPDATE x SET v = v + 1 WHERE id = 1;
UPDATE x SET v = v + 1 WHERE id = 2;
COMMIT;
-- Worker 2
BEGIN;
UPDATE x SET v = v + 1 WHERE id = 2;
UPDATE x SET v = v + 1 WHERE id = 1;
COMMIT;
```

<details><summary>Solution</summary>

The two workers lock the same two rows in opposite orders. Establish a single ordering rule: always update by ascending `id`. Both workers become:
```sql
BEGIN;
UPDATE x SET v = v + 1 WHERE id = 1;
UPDATE x SET v = v + 1 WHERE id = 2;
COMMIT;
```
</details>

## 6. Hold an advisory lock for the duration of one transaction only.

<details><summary>Solution</summary>

```sql
BEGIN;
SELECT pg_advisory_xact_lock(42);
-- ... single-leader work ...
COMMIT;   -- lock auto-released
```
</details>

## 7. Show every relation lock currently granted in the `app` schema.

<details><summary>Solution</summary>

```sql
SELECT l.locktype, l.mode, c.relname, l.granted, a.pid, a.query
FROM pg_locks l
LEFT JOIN pg_class c ON c.oid = l.relation
LEFT JOIN pg_stat_activity a ON a.pid = l.pid
WHERE c.relnamespace = 'app'::regnamespace
ORDER BY granted, c.relname;
```
</details>

## 8. Why does `CREATE INDEX CONCURRENTLY` matter in production?

<details><summary>Solution</summary>

Plain `CREATE INDEX` takes a `SHARE` lock on the table for its duration — readers continue but writers are blocked. `CREATE INDEX CONCURRENTLY` only takes a `SHARE UPDATE EXCLUSIVE` lock, allowing reads and writes throughout. The trade-offs: it cannot be wrapped in a transaction, may fail and leave an invalid index that must be `DROPPED INDEX CONCURRENTLY`, and is slower. Reference: <https://www.postgresql.org/docs/17/sql-createindex.html#SQL-CREATEINDEX-CONCURRENTLY>.
</details>

## 9. Write an idempotent insert for a payment intent keyed by `idempotency_key`. If the row exists, return the existing one.

<details><summary>Solution</summary>

```sql
INSERT INTO payment_intents (idempotency_key, user_id, amount_cents, state)
VALUES (:key, :user, :amount, 'pending')
ON CONFLICT (idempotency_key) DO UPDATE
  SET idempotency_key = EXCLUDED.idempotency_key   -- no-op, lets RETURNING work
RETURNING *;
```
Some teams prefer `ON CONFLICT DO NOTHING` plus a follow-up `SELECT`; both are correct. The `DO UPDATE` form returns the row in one round-trip but writes a new tuple version, which costs vacuum work.
</details>

## 10. You see `wait_event = 'transactionid'` in `pg_stat_activity` for many sessions. What does that mean and how do you investigate?

<details><summary>Solution</summary>

`transactionid` wait means a session is waiting on the commit/rollback of another transaction to settle a row lock or visibility. Investigate by joining `pg_stat_activity` with `pg_blocking_pids()`:
```sql
SELECT pid, query, pg_blocking_pids(pid) AS blocked_by
FROM pg_stat_activity
WHERE wait_event = 'transactionid';
```
A long-held transaction at the root of the chain is the culprit. Kill it with `SELECT pg_terminate_backend(pid)` only after you understand what it is doing.
</details>
