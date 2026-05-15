-- 03-schema-design/lab.sql
-- This lab creates a sandbox schema 'lab03' so it doesn't touch the course
-- 'app' schema. Drop and recreate freely.

DROP SCHEMA IF EXISTS lab03 CASCADE;
CREATE SCHEMA lab03;
SET search_path = lab03, public;

------------------------------------------------------------
-- 1. Identity vs serial
------------------------------------------------------------
-- WHY: GENERATED ALWAYS AS IDENTITY is ANSI SQL since Postgres 10 and
-- prevents accidental client-supplied IDs.
CREATE TABLE customer (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email       citext NOT NULL UNIQUE,
    full_name   text   NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now()
);

INSERT INTO customer (email, full_name) VALUES
    ('alice@example.com', 'Alice'),
    ('bob@example.com',   'Bob');

-- WHY: this fails because the column is GENERATED ALWAYS. Run it to see the
-- error, then use OVERRIDING SYSTEM VALUE if you really need a manual id.
-- INSERT INTO customer (id, email, full_name) VALUES (99, 'c@e.com', 'C');

------------------------------------------------------------
-- 2. CHECK constraints with names
------------------------------------------------------------
CREATE TABLE invoice (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id  bigint NOT NULL REFERENCES customer(id) ON DELETE RESTRICT,
    period_start date NOT NULL,
    period_end   date NOT NULL,
    amount_cents integer NOT NULL,
    status       text NOT NULL,
    CONSTRAINT invoice_amount_non_negative CHECK (amount_cents >= 0),
    CONSTRAINT invoice_status_valid        CHECK (status IN ('draft','issued','paid','void')),
    CONSTRAINT invoice_period_valid        CHECK (period_end > period_start),
    CONSTRAINT invoice_period_unique       UNIQUE (customer_id, period_start, period_end)
);

INSERT INTO invoice (customer_id, period_start, period_end, amount_cents, status)
VALUES (1, '2025-01-01', '2025-02-01', 12500, 'issued');

-- WHY: these violate named constraints. Comment them out to keep running.
-- INSERT INTO invoice (customer_id, period_start, period_end, amount_cents, status)
--   VALUES (1, '2025-01-01', '2025-02-01', 12500, 'issued');  -- invoice_period_unique
-- INSERT INTO invoice (customer_id, period_start, period_end, amount_cents, status)
--   VALUES (1, '2025-03-01', '2025-02-01', 12500, 'issued');  -- invoice_period_valid
-- INSERT INTO invoice (customer_id, period_start, period_end, amount_cents, status)
--   VALUES (1, '2025-02-01', '2025-03-01', -1, 'issued');     -- invoice_amount_non_negative

------------------------------------------------------------
-- 3. Foreign key actions
------------------------------------------------------------
-- WHY: ON DELETE behaviour is part of your schema's behavior contract.
-- Show both CASCADE and RESTRICT in action.
CREATE TABLE author (
    id   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name text NOT NULL
);

CREATE TABLE book (
    id        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    author_id bigint NOT NULL REFERENCES author(id) ON DELETE CASCADE,
    title     text NOT NULL
);

INSERT INTO author (name) VALUES ('Ursula'), ('Kazuo');
INSERT INTO book (author_id, title) VALUES (1, 'A Wizard of Earthsea'), (2, 'Klara and the Sun');

DELETE FROM author WHERE id = 1;
-- WHY: book by Ursula is gone too because of ON DELETE CASCADE.
SELECT * FROM book;

------------------------------------------------------------
-- 4. Exclusion constraints
------------------------------------------------------------
-- WHY: prevent overlapping reservations on the same room. Uses gist + btree_gist
-- for the equality piece on room.
CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE TABLE reservation (
    id        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    room      text NOT NULL,
    during    tstzrange NOT NULL,
    EXCLUDE USING gist (room WITH =, during WITH &amp;&amp;)
);

INSERT INTO reservation (room, during) VALUES
    ('A', tstzrange('2025-06-01 09:00+00', '2025-06-01 10:00+00')),
    ('A', tstzrange('2025-06-01 10:00+00', '2025-06-01 11:00+00'));
-- WHY: this overlaps the first row and will fail.
-- INSERT INTO reservation (room, during) VALUES
--     ('A', tstzrange('2025-06-01 09:30+00', '2025-06-01 10:30+00'));

------------------------------------------------------------
-- 5. Generated columns
------------------------------------------------------------
CREATE TABLE shipment (
    id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    weight_grams    integer NOT NULL CHECK (weight_grams > 0),
    weight_kg       numeric GENERATED ALWAYS AS (weight_grams / 1000.0) STORED
);

INSERT INTO shipment (weight_grams) VALUES (1500), (250);
SELECT * FROM shipment;

------------------------------------------------------------
-- 6. Normalization: a denormalized order table and its fixed form
------------------------------------------------------------
-- BAD: repeating product columns; duplicates customer info.
CREATE TABLE bad_order (
    order_id      bigint PRIMARY KEY,
    customer_name text,
    customer_email text,
    item1_sku   text, item1_qty int, item1_price int,
    item2_sku   text, item2_qty int, item2_price int,
    item3_sku   text, item3_qty int, item3_price int
);
COMMENT ON TABLE bad_order IS 'Denormalized example. Do not copy.';

-- GOOD: see the course's existing app.orders + app.order_items in the seed.
-- The fix is straightforward: pull repeating groups into a child table.

------------------------------------------------------------
-- 7. Enum-like: lookup table vs CREATE TYPE ... ENUM
------------------------------------------------------------
-- WHY: ENUMs are fast and concise but altering them requires DDL (and locks);
-- a lookup table is flexible and reportable.
CREATE TYPE order_status_enum AS ENUM ('pending','paid','shipped','cancelled');

CREATE TABLE order_with_enum (
    id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    status order_status_enum NOT NULL
);
INSERT INTO order_with_enum (status) VALUES ('paid'), ('pending');

CREATE TABLE order_status_lookup (
    code  text PRIMARY KEY,
    label text NOT NULL
);
INSERT INTO order_status_lookup VALUES
    ('pending','Pending'),('paid','Paid'),('shipped','Shipped'),('cancelled','Cancelled');

CREATE TABLE order_with_lookup (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    status_code text NOT NULL REFERENCES order_status_lookup(code)
);
INSERT INTO order_with_lookup (status_code) VALUES ('paid'), ('pending');

-- Cleanup is optional: DROP SCHEMA lab03 CASCADE;
