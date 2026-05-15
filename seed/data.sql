-- seed/data.sql
-- ~1k rows of synthetic data for the labs. Deterministic (no random()) so that
-- EXPLAIN plans and counts are stable across runs.
--
-- Conventions:
--   * Dates are spread across 2024-2026 to demo window functions and partitioning.
--   * JSONB attributes use a small set of shapes so module 07 can index them.

SET search_path = app, public;

------------------------------------------------------------
-- users (50)
------------------------------------------------------------
INSERT INTO app.users (email, full_name, profile, created_at)
SELECT
    'user' || g || '@example.com',
    'User ' || g,
    jsonb_build_object(
        'role', CASE WHEN g % 10 = 0 THEN 'admin' ELSE 'member' END,
        'tier', CASE (g % 3) WHEN 0 THEN 'free' WHEN 1 THEN 'pro' ELSE 'enterprise' END,
        'prefs', jsonb_build_object('newsletter', (g % 2 = 0), 'theme', CASE WHEN g % 2 = 0 THEN 'dark' ELSE 'light' END)
    ),
    timestamptz '2024-01-01' + (g * interval '8 days')
FROM generate_series(1, 50) AS g;

------------------------------------------------------------
-- categories (12, with two-level hierarchy)
------------------------------------------------------------
INSERT INTO app.categories (name) VALUES
    ('Engineering'), ('Data'), ('Product'), ('Ops');

INSERT INTO app.categories (name, parent_id) VALUES
    ('Backend',    (SELECT id FROM app.categories WHERE name='Engineering')),
    ('Frontend',   (SELECT id FROM app.categories WHERE name='Engineering')),
    ('SQL',        (SELECT id FROM app.categories WHERE name='Data')),
    ('ML',         (SELECT id FROM app.categories WHERE name='Data')),
    ('Roadmap',    (SELECT id FROM app.categories WHERE name='Product')),
    ('Research',   (SELECT id FROM app.categories WHERE name='Product')),
    ('SRE',        (SELECT id FROM app.categories WHERE name='Ops')),
    ('Security',   (SELECT id FROM app.categories WHERE name='Ops'));

------------------------------------------------------------
-- posts (~400)
------------------------------------------------------------
INSERT INTO app.posts (author_id, title, body, tags, published_at, created_at)
SELECT
    ((g - 1) % 50) + 1                                AS author_id,
    'Post ' || g || ': '
        || CASE (g % 5)
            WHEN 0 THEN 'Indexing strategies'
            WHEN 1 THEN 'Tuning autovacuum'
            WHEN 2 THEN 'Query plans explained'
            WHEN 3 THEN 'Schema migrations'
            ELSE        'Vector search with pgvector'
           END                                        AS title,
    'This is the body of post ' || g
        || '. It discusses '
        || CASE (g % 5)
            WHEN 0 THEN 'btree, GIN, GiST and BRIN indexes in PostgreSQL.'
            WHEN 1 THEN 'autovacuum thresholds and bloat in PostgreSQL.'
            WHEN 2 THEN 'EXPLAIN ANALYZE output and the cost model in PostgreSQL.'
            WHEN 3 THEN 'safe online migrations and lock contention in PostgreSQL.'
            ELSE        'pgvector, HNSW indexes and hybrid retrieval for RAG.'
           END                                        AS body,
    CASE (g % 5)
        WHEN 0 THEN ARRAY['postgres','indexes','performance']
        WHEN 1 THEN ARRAY['postgres','autovacuum','ops']
        WHEN 2 THEN ARRAY['postgres','explain','performance']
        WHEN 3 THEN ARRAY['postgres','migrations','ops']
        ELSE        ARRAY['postgres','pgvector','ai','rag']
    END                                               AS tags,
    -- Some posts are drafts (NULL published_at)
    CASE WHEN g % 7 = 0 THEN NULL
         ELSE timestamptz '2024-02-01' + (g * interval '36 hours') END AS published_at,
    timestamptz '2024-02-01' + (g * interval '36 hours' - interval '4 hours') AS created_at
FROM generate_series(1, 400) AS g;

------------------------------------------------------------
-- post_categories (each post in 1-2 categories deterministically)
------------------------------------------------------------
INSERT INTO app.post_categories (post_id, category_id)
SELECT p.id,
       ((p.id - 1) % (SELECT count(*) FROM app.categories) + 1)
FROM app.posts p;

INSERT INTO app.post_categories (post_id, category_id)
SELECT p.id,
       ((p.id) % (SELECT count(*) FROM app.categories) + 1)
FROM app.posts p
WHERE p.id % 3 = 0
ON CONFLICT DO NOTHING;

------------------------------------------------------------
-- comments (~600, some nested)
------------------------------------------------------------
INSERT INTO app.comments (post_id, author_id, body, created_at)
SELECT
    ((g - 1) % 400) + 1                                AS post_id,
    ((g * 7 - 1) % 50) + 1                             AS author_id,
    'Comment ' || g || ' on post ' || (((g - 1) % 400) + 1)
        || ': '
        || CASE g % 4 WHEN 0 THEN 'Great write-up.'
                      WHEN 1 THEN 'Could you clarify the indexing choice?'
                      WHEN 2 THEN 'I disagree with the locking analysis.'
                      ELSE        'Thanks for the EXPLAIN output.' END,
    timestamptz '2024-03-01' + (g * interval '6 hours')
FROM generate_series(1, 600) AS g;

-- Add a few nested replies to demo recursive CTEs in module 06.
INSERT INTO app.comments (post_id, author_id, parent_comment_id, body, created_at)
SELECT c.post_id,
       ((c.id * 11 - 1) % 50) + 1,
       c.id,
       'Reply to comment ' || c.id,
       c.created_at + interval '2 hours'
FROM app.comments c
WHERE c.id % 25 = 0;

------------------------------------------------------------
-- products (60)
------------------------------------------------------------
INSERT INTO app.products (sku, name, attributes, price_cents, created_at)
SELECT
    'SKU-' || lpad(g::text, 4, '0'),
    CASE g % 4 WHEN 0 THEN 'Widget '
               WHEN 1 THEN 'Gadget '
               WHEN 2 THEN 'Sprocket '
               ELSE        'Gizmo ' END || g,
    jsonb_build_object(
        'color', CASE g % 5 WHEN 0 THEN 'red' WHEN 1 THEN 'blue' WHEN 2 THEN 'green' WHEN 3 THEN 'black' ELSE 'white' END,
        'size',  CASE g % 3 WHEN 0 THEN 'S' WHEN 1 THEN 'M' ELSE 'L' END,
        'tags',  CASE g % 4 WHEN 0 THEN to_jsonb(ARRAY['sale','featured'])
                            WHEN 1 THEN to_jsonb(ARRAY['new'])
                            WHEN 2 THEN to_jsonb(ARRAY['clearance'])
                            ELSE        to_jsonb(ARRAY['standard']) END,
        'specs', jsonb_build_object('weight_g', 100 + g, 'warranty_years', (g % 3) + 1)
    ),
    ((g % 20) + 1) * 1000,
    timestamptz '2024-01-15' + (g * interval '7 days')
FROM generate_series(1, 60) AS g;

------------------------------------------------------------
-- orders (~200) and order_items
------------------------------------------------------------
INSERT INTO app.orders (user_id, status, total_cents, created_at)
SELECT
    ((g - 1) % 50) + 1                                AS user_id,
    CASE g % 8 WHEN 0 THEN 'cancelled'
               WHEN 1 THEN 'pending'
               WHEN 2 THEN 'shipped'
               ELSE        'paid' END                AS status,
    0,                                               -- backfilled below
    timestamptz '2024-04-01' + (g * interval '18 hours')
FROM generate_series(1, 200) AS g;

INSERT INTO app.order_items (order_id, product_id, quantity, unit_price_cents)
SELECT
    o.id,
    ((o.id - 1) % 60) + 1                            AS product_id,
    ((o.id % 3) + 1)                                 AS quantity,
    p.price_cents
FROM app.orders o
JOIN app.products p ON p.id = ((o.id - 1) % 60) + 1;

-- A second line for every third order so joins and aggregates have variety.
INSERT INTO app.order_items (order_id, product_id, quantity, unit_price_cents)
SELECT
    o.id,
    ((o.id) % 60) + 1                                AS product_id,
    1                                                AS quantity,
    p.price_cents
FROM app.orders o
JOIN app.products p ON p.id = ((o.id) % 60) + 1
WHERE o.id % 3 = 0
ON CONFLICT DO NOTHING;

-- Backfill orders.total_cents from order_items.
UPDATE app.orders o
SET total_cents = sub.total
FROM (
    SELECT order_id, sum(quantity * unit_price_cents) AS total
    FROM app.order_items
    GROUP BY order_id
) sub
WHERE sub.order_id = o.id;

------------------------------------------------------------
-- inventory
------------------------------------------------------------
INSERT INTO app.inventory (product_id, warehouse, qty)
SELECT p.id, w, ((p.id * 13) % 50) + 5
FROM app.products p
CROSS JOIN (VALUES ('US-EAST'), ('US-WEST'), ('EU-CENTRAL')) AS wh(w);

------------------------------------------------------------
-- Sanity counts (run this block manually to verify the seed)
------------------------------------------------------------
-- SELECT 'users' AS t, count(*) FROM app.users
-- UNION ALL SELECT 'posts',       count(*) FROM app.posts
-- UNION ALL SELECT 'comments',    count(*) FROM app.comments
-- UNION ALL SELECT 'products',    count(*) FROM app.products
-- UNION ALL SELECT 'orders',      count(*) FROM app.orders
-- UNION ALL SELECT 'order_items', count(*) FROM app.order_items
-- UNION ALL SELECT 'inventory',   count(*) FROM app.inventory;

ANALYZE;
