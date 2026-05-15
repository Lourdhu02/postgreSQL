# Module 12 — Challenges

## 1. Why use `vector_cosine_ops` for Sentence-Transformers embeddings instead of `vector_l2_ops`?

<details><summary>Solution</summary>

Sentence-Transformers (and most modern embedding models) produce vectors that are *roughly* unit-length and are trained with a cosine objective. Cosine is invariant to magnitude — L2 isn't, so it penalizes vectors whose norms differ even when their semantic direction matches. Use `vector_cosine_ops` (or normalize to unit length and use inner product) for these models.
</details>

## 2. You added an HNSW index but vector queries are slower than a sequential scan. What's the first thing to check?

<details><summary>Solution</summary>

`hnsw.ef_search` may be too high, or the table is too small (HNSW pays its construction cost for hundreds of thousands of rows). Check `EXPLAIN ANALYZE` — is the index actually used? If not, `ANALYZE rag.chunks;` so statistics are current. For tiny tables, a seq scan beats any index.
</details>

## 3. Add a metadata filter that pre-filters by `tenant_id` before the ANN.

<details><summary>Solution</summary>

```sql
SELECT c.id, c.text
FROM rag.chunks c
JOIN rag.documents d ON d.id = c.document_id
WHERE d.metadata @> jsonb_build_object('tenant', $1)
ORDER BY c.embedding <=> $2::vector
LIMIT 20;
```
The planner decides which leg to apply first. Use `EXPLAIN ANALYZE`. With a highly-selective tenant filter, the planner will likely seek by tenant first; with a non-selective filter, HNSW first.
</details>

## 4. The HNSW index returned only 30 candidates when you asked `LIMIT 50`. Why?

<details><summary>Solution</summary>

HNSW returns at most `ef_search` candidates per query (default 40 in pgvector). Raise it: `SET LOCAL hnsw.ef_search = 100;`. The trade-off is latency.
</details>

## 5. Implement the RRF merge in Python using two ranked lists.

<details><summary>Solution</summary>

```python
def rrf(*lists, k=60, limit=10):
    scores = {}
    for ranked in lists:
        for rank, doc_id in enumerate(ranked, start=1):
            scores[doc_id] = scores.get(doc_id, 0) + 1.0 / (k + rank)
    return sorted(scores.items(), key=lambda x: x[1], reverse=True)[:limit]
```
Pass `vec_ids` and `lex_ids` (each a list of document IDs in ranked order) and you get the fused list.
</details>

## 6. You ingested the same document twice and got two sets of chunks. Fix the ingestion.

<details><summary>Solution</summary>

Make ingestion idempotent with `source_uri` as the natural key and a content hash to skip unchanged docs:

```python
def upsert(conn, source_uri, title, sha, chunks_with_embeddings):
    with conn.transaction():
        row = conn.execute(
            \"\"\"INSERT INTO rag.documents (source_uri, title, content_sha)
               VALUES (%s, %s, %s)
               ON CONFLICT (source_uri) DO UPDATE
                 SET title = EXCLUDED.title,
                     content_sha = EXCLUDED.content_sha,
                     updated_at = now()
               RETURNING id, content_sha = EXCLUDED.content_sha AS unchanged\"\"\",
            (source_uri, title, sha)
        ).fetchone()
        doc_id, unchanged = row
        if unchanged:
            return doc_id
        conn.execute("DELETE FROM rag.chunks WHERE document_id = %s", (doc_id,))
        # COPY new chunks in
        ...
```
Wrap everything in a single transaction so readers never see a half-replaced doc.
</details>

## 7. Compare HNSW build time and query latency at `m=8,16,32` and `ef_construction=64,128`.

<details><summary>Solution</summary>

Build several indexes (or use `CREATE INDEX CONCURRENTLY`) and time:
```sql
\timing
DROP INDEX IF EXISTS rag.chunks_embedding_hnsw_idx;
CREATE INDEX chunks_embedding_hnsw_idx ON rag.chunks USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 64);
ANALYZE rag.chunks;
-- run benchmark queries 10x and average
```
Higher `m` and `ef_construction` improve recall and increase build time and memory. For sentence-transformer corpora, `m=16, ef_construction=64` is a strong default.
</details>

## 8. Add a `last_seen_at` timestamp and a recency boost to the hybrid score.

<details><summary>Solution</summary>

```sql
ALTER TABLE rag.chunks ADD COLUMN last_seen_at timestamptz NOT NULL DEFAULT now();

-- in the hybrid CTE, add a third signal:
,
rec AS (
    SELECT id, row_number() OVER (ORDER BY last_seen_at DESC) AS r
    FROM rag.chunks ORDER BY last_seen_at DESC LIMIT 50
)
-- and add 1.0/(60 + r.r) to the rrf sum
```
Weight the recency leg lower than vector and lexical (e.g. multiply by 0.5).
</details>

## 9. The vector column is 384 floats × 4 bytes = 1.5 KB per row. At 10M chunks that's 15 GB. What pgvector feature can shrink this?

<details><summary>Solution</summary>

pgvector 0.7 added **half-precision** (`halfvec`, 2 bytes/dim) and **binary quantization** (`bit` vectors via Hamming distance). `halfvec(384)` cuts storage in half with negligible recall loss for most embeddings. Binary quantization (1 bit/dim) is 32x smaller but trades meaningful recall — use as a coarse filter before re-ranking with full vectors.
</details>

## 10. You want chunks from documents created in the last 7 days only, scored by vector similarity. Two ways: pre-filter and post-filter. Which is better here?

<details><summary>Solution</summary>

**Pre-filter** is better when "last 7 days" is highly selective (small fraction of the corpus): Postgres uses the timestamp index, then computes distance only on matches.

**Post-filter** wins when the filter is weak (most docs are recent): the ANN index returns top-K, then a cheap filter prunes a few. Let the planner decide — make sure `documents(created_at)` is indexed and `ANALYZE`d, then check `EXPLAIN ANALYZE`. If the planner picks wrong, force the order with a CTE that explicitly does the filter first.
</details>
