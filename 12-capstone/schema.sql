-- 12-capstone/schema.sql
-- The RAG schema. Run once. Re-run is safe (idempotent objects).
-- Requires pgvector: CREATE EXTENSION vector; must succeed.

CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE SCHEMA IF NOT EXISTS rag;
SET search_path = rag, public;

------------------------------------------------------------
-- documents: one row per source document
------------------------------------------------------------
CREATE TABLE IF NOT EXISTS rag.documents (
    id          bigserial PRIMARY KEY,
    source_uri  text   NOT NULL UNIQUE,
    title       text   NOT NULL,
    metadata    jsonb  NOT NULL DEFAULT '{}'::jsonb,
    content_sha bytea  NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS documents_metadata_gin_idx
    ON rag.documents USING gin (metadata jsonb_path_ops);

CREATE INDEX IF NOT EXISTS documents_title_trgm_idx
    ON rag.documents USING gin (title gin_trgm_ops);

------------------------------------------------------------
-- chunks: one row per ~200-300 token slice
------------------------------------------------------------
-- vector(384) matches all-MiniLM-L6-v2. Change to vector(1536) for OpenAI
-- text-embedding-3-small, vector(3072) for text-embedding-3-large, etc.
CREATE TABLE IF NOT EXISTS rag.chunks (
    id           bigserial PRIMARY KEY,
    document_id  bigint NOT NULL REFERENCES rag.documents(id) ON DELETE CASCADE,
    ordinal      integer NOT NULL,
    text         text   NOT NULL,
    token_count  integer,
    embedding    vector(384) NOT NULL,
    fts          tsvector GENERATED ALWAYS AS (to_tsvector('english', text)) STORED,
    UNIQUE (document_id, ordinal)
);

CREATE INDEX IF NOT EXISTS chunks_fts_idx
    ON rag.chunks USING gin (fts);

-- HNSW index for cosine similarity. m and ef_construction are build-time knobs.
-- Search-time knob: SET LOCAL hnsw.ef_search = 100;
-- Build this AFTER bulk-loading rows for best memory layout in real workloads.
CREATE INDEX IF NOT EXISTS chunks_embedding_hnsw_idx
    ON rag.chunks USING hnsw (embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 64);

ANALYZE rag.documents;
ANALYZE rag.chunks;
