-- 05-transactions-mvcc/lab.sql
-- This lab demonstrates concurrency. Run the labeled blocks in TWO psql
-- sessions in alternation. Session names: A and B.
SET search_path = app, public;

------------------------------------------------------------
-- Setup: a tiny accounts table local to this module
------------------------------------------------------------
-- (Run once in Session A.)
CREATE TABLE IF NOT EXISTS lab05_accounts (
    id      bigint PRIMARY KEY,
    balance integer NOT NULL CHECK (balance >= 0)
);
TRUNCATE lab05_accounts;
INSERT INTO lab05_accounts VALUES (1, 100), (2, 100);

------------------------------------------------------------
-- 1. Read Committed sees a moving target
------------------------------------------------------------
-- Session A:
-- BEGIN;
-- SELECT balance FROM lab05_accounts WHERE id = 1;   -- 100

-- Session B (in another psql):
-- BEGIN;
-- UPDATE lab05_accounts SET balance = 80 WHERE id = 1;
-- COMMIT;

-- Session A:
-- SELECT balance FROM lab05_accounts WHERE id = 1;   -- 80, because we're at Read Committed
-- COMMIT;

------------------------------------------------------------
-- 2. Repeatable Read sees a stable snapshot
------------------------------------------------------------
-- Reset:
-- TRUNCATE lab05_accounts;
-- INSERT INTO lab05_accounts VALUES (1, 100), (2, 100);

-- Session A:
-- BEGIN ISOLATION LEVEL REPEATABLE READ;
-- SELECT balance FROM lab05_accounts WHERE id = 1;   -- 100

-- Session B:
-- BEGIN; UPDATE lab05_accounts SET balance = 80 WHERE id = 1; COMMIT;

-- Session A:
-- SELECT balance FROM lab05_accounts WHERE id = 1;   -- still 100, snapshot held
-- COMMIT;

------------------------------------------------------------
-- 3. Lost update under Read Committed
------------------------------------------------------------
-- Reset:
-- TRUNCATE lab05_accounts;
-- INSERT INTO lab05_accounts VALUES (1, 100);

-- Both sessions read and decide based on the value, then write a final value
-- they computed locally.

-- A: BEGIN; SELECT balance FROM lab05_accounts WHERE id=1;       -- 100
-- B: BEGIN; SELECT balance FROM lab05_accounts WHERE id=1;       -- 100
-- A: UPDATE lab05_accounts SET balance = 100 - 50 WHERE id=1;    -- now 50 in A's view
-- B: UPDATE lab05_accounts SET balance = 100 - 30 WHERE id=1;    -- blocks until A commits
-- A: COMMIT;                                                     -- 50
-- B: COMMIT;                                                     -- 70   <- A's deduction is lost

-- Fix: read-modify-write under SELECT ... FOR UPDATE, or atomic SQL:
-- UPDATE lab05_accounts SET balance = balance - 50 WHERE id = 1;

------------------------------------------------------------
-- 4. Fix with SELECT ... FOR UPDATE
------------------------------------------------------------
-- A: BEGIN; SELECT balance FROM lab05_accounts WHERE id=1 FOR UPDATE;   -- locks row
-- B: BEGIN; SELECT balance FROM lab05_accounts WHERE id=1 FOR UPDATE;   -- waits on A
-- A: UPDATE ...; COMMIT;
-- B: now reads the post-A balance, then updates safely.

------------------------------------------------------------
-- 5. Serializable + retry loop
------------------------------------------------------------
-- Reset:
-- TRUNCATE lab05_accounts;
-- INSERT INTO lab05_accounts VALUES (1, 100), (2, 100);

-- A: BEGIN ISOLATION LEVEL SERIALIZABLE;
--    SELECT sum(balance) FROM lab05_accounts;          -- 200
--    INSERT INTO lab05_accounts VALUES (3, 0);         -- adds a row
--    -- intends to maintain invariant: sum >= 200
--    COMMIT;
-- B (concurrently): BEGIN ISOLATION LEVEL SERIALIZABLE;
--    SELECT sum(balance) FROM lab05_accounts;          -- also 200
--    INSERT INTO lab05_accounts VALUES (4, 0);
--    COMMIT;   -- may abort with serialization_failure (40001). Retry the whole tx.

------------------------------------------------------------
-- 6. Deadlock
------------------------------------------------------------
-- A: BEGIN; UPDATE lab05_accounts SET balance = balance - 1 WHERE id = 1;
-- B: BEGIN; UPDATE lab05_accounts SET balance = balance - 1 WHERE id = 2;
-- A: UPDATE lab05_accounts SET balance = balance - 1 WHERE id = 2;   -- waits on B
-- B: UPDATE lab05_accounts SET balance = balance - 1 WHERE id = 1;   -- waits on A
-- Postgres detects the deadlock (~1s) and aborts one with 40P01.

-- Prevention: lock rows in a consistent order. E.g. always update by ascending id.

------------------------------------------------------------
-- 7. Advisory lock for single-leader work
------------------------------------------------------------
-- A: SELECT pg_try_advisory_lock(42);   -- t
-- B: SELECT pg_try_advisory_lock(42);   -- f, someone else has it
-- A: SELECT pg_advisory_unlock(42);
-- B: SELECT pg_try_advisory_lock(42);   -- t now

------------------------------------------------------------
-- 8. Who is blocking whom?
------------------------------------------------------------
SELECT pid,
       state,
       query,
       wait_event_type,
       wait_event,
       pg_blocking_pids(pid) AS blocked_by
FROM pg_stat_activity
WHERE state != 'idle' AND datname = current_database();

------------------------------------------------------------
-- 9. Idempotent insert pattern
------------------------------------------------------------
CREATE TABLE IF NOT EXISTS lab05_jobs (
    idempotency_key uuid PRIMARY KEY,
    user_id  bigint NOT NULL,
    status   text NOT NULL CHECK (status IN ('queued','running','done','failed'))
);

-- First call: inserts row.
INSERT INTO lab05_jobs (idempotency_key, user_id, status)
VALUES ('00000000-0000-0000-0000-000000000001', 7, 'queued')
ON CONFLICT (idempotency_key) DO NOTHING
RETURNING *;

-- Retry with same key: returns nothing, but the row exists. The caller can
-- then SELECT by the key and return the same result.
INSERT INTO lab05_jobs (idempotency_key, user_id, status)
VALUES ('00000000-0000-0000-0000-000000000001', 7, 'queued')
ON CONFLICT (idempotency_key) DO NOTHING
RETURNING *;

------------------------------------------------------------
-- Cleanup (optional)
------------------------------------------------------------
-- DROP TABLE lab05_accounts;
-- DROP TABLE lab05_jobs;
