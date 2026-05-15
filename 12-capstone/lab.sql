-- 12-capstone/lab.sql
-- SQL companion to lab.ipynb. The Python notebook produces embeddings and
-- loads rows; this file holds the retrieval queries you'll run interactively.
SET search_path = rag, public;

------------------------------------------------------------
-- 1. Inspect what's loaded
------------------------------------------------------------
SELECT count(*) AS documents FROM rag.documents;
SELECT count(*) AS chunks FROM rag.chunks;

------------------------------------------------------------
-- 2. Pure vector search (parameterised by a 384-d vector literal)
------------------------------------------------------------
-- WHY: replace :q with a real embedding, e.g. '[0.01, 0.02, ...]'::vector(384).
-- From Python, pass the embedding directly as a parameter.
--
-- EXPLAIN (ANALYZE, BUFFERS)
-- SELECT c.id, c.document_id, c.text,
--        1 - (c.embedding <=> :q::vector) AS similarity
-- FROM rag.chunks c
-- ORDER BY c.embedding <=> :q::vector
-- LIMIT 10;

------------------------------------------------------------
-- 3. Filtered ANN: metadata pre-filter
------------------------------------------------------------
-- SELECT c.id, c.text
-- FROM rag.chunks c
-- JOIN rag.documents d ON d.id = c.document_id
-- WHERE d.metadata @> '{"tenant":"demo"}'
-- ORDER BY c.embedding <=> :q::vector
-- LIMIT 10;

------------------------------------------------------------
-- 4. Lexical leg: FTS only
------------------------------------------------------------
-- SELECT c.id, c.text, ts_rank(c.fts, q) AS rank
-- FROM rag.chunks c, websearch_to_tsquery('english', :user_text) q
-- WHERE c.fts @@ q
-- ORDER BY rank DESC
-- LIMIT 10;

------------------------------------------------------------
-- 5. Hybrid retrieval with Reciprocal Rank Fusion (RRF)
------------------------------------------------------------
-- WITH vec AS (
--     SELECT id, row_number() OVER (ORDER BY embedding <=> :q::vector) AS r
--     FROM rag.chunks
--     ORDER BY embedding <=> :q::vector
--     LIMIT 50
-- ),
-- lex AS (
--     SELECT id, row_number() OVER (ORDER BY ts_rank(fts, q) DESC) AS r
--     FROM rag.chunks, websearch_to_tsquery('english', :user_text) q
--     WHERE fts @@ q
--     LIMIT 50
-- )
-- SELECT c.id, c.text,
--        coalesce(1.0/(60 + v.r), 0) + coalesce(1.0/(60 + l.r), 0) AS rrf
-- FROM rag.chunks c
-- LEFT JOIN vec v ON v.id = c.id
-- LEFT JOIN lex l ON l.id = c.id
-- WHERE v.id IS NOT NULL OR l.id IS NOT NULL
-- ORDER BY rrf DESC
-- LIMIT 10;

------------------------------------------------------------
-- 6. Tuning HNSW recall vs latency
------------------------------------------------------------
-- SET LOCAL hnsw.ef_search = 40;    -- low recall, fastest
-- SET LOCAL hnsw.ef_search = 200;   -- higher recall, slower
-- Run query 2 with each setting and compare actual time / row similarity.

------------------------------------------------------------
-- 7. Reset / cleanup
------------------------------------------------------------
-- TRUNCATE rag.chunks, rag.documents RESTART IDENTITY;
-- DROP SCHEMA rag CASCADE;
