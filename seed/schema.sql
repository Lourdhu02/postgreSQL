-- seed/schema.sql
-- Baseline schema used across every module. Run this once after creating the
-- database. Idempotent: drops the schema first so reseeding is safe.
--
-- Why a unified schema: every module's lab.sql references the same tables so
-- you can compose ideas across modules (e.g. transactions on orders, FTS on
-- posts) without juggling schemas. The shape is small enough to read in one
-- sitting but rich enough to exercise every Postgres feature in the course.

DROP SCHEMA IF EXISTS app CASCADE;
CREATE SCHEMA app;
SET search_path = app, public;

-- Extensions available out of the box in core Postgres 17.
-- pg_trgm: trigram similarity for fuzzy search (used in module 07).
-- citext:  case-insensitive text for emails (used in users.email).
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS citext;

------------------------------------------------------------
-- Core tables
------------------------------------------------------------

CREATE TABLE app.users (
    id          bigserial PRIMARY KEY,
    email       citext      NOT NULL UNIQUE,
    full_name   text        NOT NULL,
    profile     jsonb       NOT NULL DEFAULT '{}'::jsonb,
    created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE app.categories (
    id         bigserial PRIMARY KEY,
    name       text NOT NULL,
    parent_id  bigint REFERENCES app.categories(id) ON DELETE SET NULL,
    UNIQUE (parent_id, name)
);

CREATE TABLE app.posts (
    id           bigserial PRIMARY KEY,
    author_id    bigint NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
    title        text   NOT NULL,
    body         text   NOT NULL,
    tags         text[] NOT NULL DEFAULT '{}',
    published_at timestamptz,
    created_at   timestamptz NOT NULL DEFAULT now(),
    -- Generated tsvector for full-text search (module 07). Stored, so a GIN
    -- index on it is allowed and stays in sync automatically.
    fts          tsvector
        GENERATED ALWAYS AS (
            setweight(to_tsvector('english', coalesce(title, '')), 'A') ||
            setweight(to_tsvector('english', coalesce(body,  '')), 'B')
        ) STORED
);

CREATE TABLE app.post_categories (
    post_id     bigint NOT NULL REFERENCES app.posts(id)      ON DELETE CASCADE,
    category_id bigint NOT NULL REFERENCES app.categories(id) ON DELETE CASCADE,
    PRIMARY KEY (post_id, category_id)
);

CREATE TABLE app.comments (
    id                bigserial PRIMARY KEY,
    post_id           bigint NOT NULL REFERENCES app.posts(id)    ON DELETE CASCADE,
    author_id         bigint NOT NULL REFERENCES app.users(id)    ON DELETE CASCADE,
    parent_comment_id bigint REFERENCES app.comments(id)          ON DELETE CASCADE,
    body              text   NOT NULL,
    created_at        timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE app.products (
    id          bigserial PRIMARY KEY,
    sku         text   NOT NULL UNIQUE,
    name        text   NOT NULL,
    attributes  jsonb  NOT NULL DEFAULT '{}'::jsonb,
    price_cents integer NOT NULL CHECK (price_cents >= 0),
    created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE app.orders (
    id         bigserial PRIMARY KEY,
    user_id    bigint NOT NULL REFERENCES app.users(id),
    status     text   NOT NULL CHECK (status IN ('pending','paid','shipped','cancelled')),
    total_cents integer NOT NULL CHECK (total_cents >= 0),
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE app.order_items (
    order_id        bigint NOT NULL REFERENCES app.orders(id)    ON DELETE CASCADE,
    product_id      bigint NOT NULL REFERENCES app.products(id),
    quantity        integer NOT NULL CHECK (quantity > 0),
    unit_price_cents integer NOT NULL CHECK (unit_price_cents >= 0),
    PRIMARY KEY (order_id, product_id)
);

CREATE TABLE app.inventory (
    product_id bigint NOT NULL REFERENCES app.products(id),
    warehouse  text   NOT NULL,
    qty        integer NOT NULL CHECK (qty >= 0),
    PRIMARY KEY (product_id, warehouse)
);

------------------------------------------------------------
-- Indexes used in later modules
------------------------------------------------------------
-- These indexes exist from day one so EXPLAIN plans are realistic.
-- Module 04 covers when to create each kind and how to read EXPLAIN.

CREATE INDEX posts_author_created_idx ON app.posts (author_id, created_at DESC);
CREATE INDEX posts_published_at_idx   ON app.posts (published_at) WHERE published_at IS NOT NULL;
CREATE INDEX posts_fts_idx            ON app.posts USING gin (fts);
CREATE INDEX posts_tags_gin_idx       ON app.posts USING gin (tags);

CREATE INDEX comments_post_idx        ON app.comments (post_id, created_at);
CREATE INDEX orders_user_idx          ON app.orders (user_id, created_at DESC);
CREATE INDEX products_attrs_gin_idx   ON app.products USING gin (attributes jsonb_path_ops);
