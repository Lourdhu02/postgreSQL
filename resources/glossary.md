# Glossary

| Term | Meaning |
|------|---------|
| **ACID**          | Atomicity, Consistency, Isolation, Durability — the four guarantees of a transactional DB. |
| **ANN**           | Approximate Nearest Neighbour. Sub-linear similarity search; the basis of pgvector retrieval. |
| **autovacuum**    | Background workers that reclaim dead-tuple space and refresh planner statistics. |
| **BRIN**          | Block Range Index — a compact summary index for very large, ordered tables. |
| **btree**         | Balanced tree index. The default Postgres index type; supports `=`, `<`, range, ORDER BY. |
| **CTE**           | Common Table Expression. A named subquery introduced with `WITH`. |
| **EXPLAIN**       | Shows the planner's chosen query plan. `EXPLAIN ANALYZE` actually runs the query and measures it. |
| **FK**            | Foreign Key. A referential-integrity constraint pointing to another row's PK. |
| **FTS**           | Full-Text Search. Uses `tsvector` and `tsquery`, accelerated by GIN. |
| **GIN**           | Generalized Inverted Index. For columns with many values per row (jsonb, arrays, tsvector). |
| **GiST**          | Generalized Search Tree. Framework for indexing custom data; supports kNN. |
| **HNSW**          | Hierarchical Navigable Small World — a graph ANN index in pgvector. |
| **idempotency**   | Property that repeating an operation produces the same final state. Critical for retries. |
| **isolation level** | Defines what concurrency anomalies are forbidden. Postgres: Read Committed, Repeatable Read, Serializable. |
| **JSONB**         | Binary JSON storage with rich operators and GIN indexing. |
| **LATERAL**       | A join modifier letting the right side reference left-row columns. |
| **MVCC**          | Multi-Version Concurrency Control. Readers see a snapshot; writers create new row versions. |
| **OID**           | Object Identifier — internal numeric handle for catalog objects. |
| **partition pruning** | Planner skipping partitions that can't match the query's predicates. |
| **pg_hba.conf**   | Host-Based Authentication. Decides who can connect and how. |
| **pgvector**      | Extension adding the `vector` type and ANN indexes. |
| **PgBouncer**     | Lightweight connection pooler that multiplexes clients onto a small pool of physical connections. |
| **PITR**          | Point-In-Time Recovery: restore from a base backup + WAL replayed to a chosen moment. |
| **planner**       | Cost-based optimizer that chooses among possible execution plans. |
| **prepared statement** | Parse + plan once, execute many. Can break across PgBouncer transaction-mode server swaps. |
| **psql**          | Postgres's command-line client. |
| **RLS**           | Row-Level Security: per-row visibility/modifiability policies attached to a table. |
| **RPO / RTO**     | Recovery Point / Recovery Time Objective — backup &amp; restore SLAs. |
| **RRF**           | Reciprocal Rank Fusion — robust merge for ranked retrieval lists. |
| **sargable**      | A predicate the optimizer can use an index for. |
| **schema**        | A namespace for tables and other objects within a database. Default is `public`. |
| **search_path**   | Order of schemas Postgres consults to resolve unqualified names. |
| **SSI**           | Serializable Snapshot Isolation — how Postgres implements SERIALIZABLE. |
| **tablespace**    | Physical storage location for objects. Most clusters use the default. |
| **tsvector / tsquery** | Lexeme bag and query expression used by Postgres FTS. |
| **VACUUM**        | Reclaims storage from dead tuples. Plain VACUUM is online; VACUUM FULL rewrites. |
| **WAL**           | Write-Ahead Log. Every change goes to the log before the data files. |
| **window function** | Aggregate over a window of related rows without collapsing rows like `GROUP BY` does. |
