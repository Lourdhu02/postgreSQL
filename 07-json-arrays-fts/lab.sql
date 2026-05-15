-- 07-json-arrays-fts/lab.sql
SET search_path = app, public;
ANALYZE;

------------------------------------------------------------
-- 1. jsonb extraction and casting
------------------------------------------------------------
-- WHY: ->> returns text; cast explicitly when you need int/numeric/bool.
SELECT id,
       profile->>'tier'                AS tier_text,
       (profile->'prefs'->>'newsletter')::boolean AS wants_newsletter
FROM users
ORDER BY id
LIMIT 10;

------------------------------------------------------------
-- 2. jsonb containment with @>
------------------------------------------------------------
-- WHY: uses products_attrs_gin_idx (jsonb_path_ops).
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, name FROM products WHERE attributes @> '{"color":"red"}';

------------------------------------------------------------
-- 3. jsonpath @@ for boolean predicates inside the document
------------------------------------------------------------
SELECT id, name
FROM products
WHERE attributes @@ '$.specs.warranty_years >= 2'
ORDER BY id
LIMIT 10;

-- Find products with 'sale' inside the nested tags array
SELECT id, name
FROM products
WHERE attributes @? '$.tags[*] ? (@ == "sale")'
ORDER BY id
LIMIT 10;

------------------------------------------------------------
-- 4. Building jsonb from rows
------------------------------------------------------------
SELECT jsonb_pretty(
    jsonb_build_object(
        'user', jsonb_build_object('id', id, 'email', email),
        'tier', profile->>'tier'
    )
)
FROM users
WHERE id <= 3;

-- Aggregate posts per author
SELECT author_id,
       jsonb_agg(jsonb_build_object('id', id, 'title', title) ORDER BY id) AS post_summaries
FROM posts
WHERE published_at IS NOT NULL
GROUP BY author_id
ORDER BY author_id
LIMIT 5;

------------------------------------------------------------
-- 5. Mutating jsonb safely
------------------------------------------------------------
-- WHY: jsonb_set creates or replaces; the 4th arg controls whether to create
-- missing paths. To delete a key use the - operator.
UPDATE users
SET profile = jsonb_set(profile, '{prefs,theme}', '"high-contrast"', true)
WHERE id = 1;

SELECT id, profile FROM users WHERE id = 1;

UPDATE users SET profile = profile - 'newsletter' WHERE id = 1;
SELECT id, profile FROM users WHERE id = 1;

------------------------------------------------------------
-- 6. Arrays: contains, overlaps, unnest, array_agg
------------------------------------------------------------
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title FROM posts WHERE tags @> ARRAY['pgvector'];      -- GIN hit

SELECT id, title FROM posts WHERE tags &amp;&amp; ARRAY['rag','ai'] LIMIT 10;

SELECT id, t FROM posts, unnest(tags) AS t WHERE id <= 5 ORDER BY id, t;

SELECT author_id, array_agg(DISTINCT t ORDER BY t) AS unique_tags
FROM (SELECT author_id, unnest(tags) AS t FROM posts) s
GROUP BY author_id
ORDER BY author_id
LIMIT 5;

------------------------------------------------------------
-- 7. Full-text search
------------------------------------------------------------
-- WHY: posts.fts is a STORED generated tsvector indexed by GIN.
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title, ts_rank(fts, q) AS rank
FROM posts, plainto_tsquery('english', 'pgvector hnsw') q
WHERE fts @@ q
ORDER BY rank DESC, published_at DESC NULLS LAST
LIMIT 10;

-- websearch_to_tsquery handles user-supplied syntax (quotes, OR, -)
SELECT id, title
FROM posts
WHERE fts @@ websearch_to_tsquery('english', '"vector search" -autovacuum')
LIMIT 10;

-- Highlighting
SELECT id,
       ts_headline('english', body, websearch_to_tsquery('english', 'vector OR hnsw'),
                   'StartSel=** , StopSel=**, MaxFragments=2') AS snippet
FROM posts
WHERE fts @@ websearch_to_tsquery('english', 'vector OR hnsw')
LIMIT 5;

------------------------------------------------------------
-- 8. Trigram fuzzy search
------------------------------------------------------------
CREATE INDEX IF NOT EXISTS posts_title_trgm_idx ON posts USING gin (title gin_trgm_ops);
ANALYZE posts;

-- '%pgvec%' is unanchored — only trigram GIN can accelerate it.
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title FROM posts WHERE title ILIKE '%pgvec%';

-- Similarity-based ranking
SELECT id, title, similarity(title, 'pgvecto') AS sim
FROM posts
WHERE title % 'pgvecto'
ORDER BY title <-> 'pgvecto'
LIMIT 10;
