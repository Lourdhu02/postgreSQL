# Module 07 — Challenges

## 1. Find every user whose `profile.role = 'admin'`. Use the containment operator and verify the index is used.

<details><summary>Solution</summary>

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, email FROM app.users WHERE profile @> '{"role":"admin"}'::jsonb;
```
For this to be index-accelerated we'd need a GIN index on `users.profile` (the seed only indexed products.attributes). Add:
```sql
CREATE INDEX users_profile_gin_idx ON app.users USING gin (profile);
ANALYZE app.users;
```
</details>

## 2. Add a key `signed_up_via='seed'` to every user's `profile`.

<details><summary>Solution</summary>

```sql
UPDATE app.users
SET profile = profile || '{"signed_up_via":"seed"}'::jsonb;
```
`||` merges at the top level; `jsonb_set` is for nested paths.
</details>

## 3. Find every post that has both `postgres` and `pgvector` in `tags`.

<details><summary>Solution</summary>

```sql
SELECT id, title FROM app.posts
WHERE tags @> ARRAY['postgres','pgvector'];
```
</details>

## 4. List every distinct tag across all posts, with how many posts use it.

<details><summary>Solution</summary>

```sql
SELECT t, count(*) AS n
FROM app.posts, unnest(tags) AS t
GROUP BY t
ORDER BY n DESC, t;
```
</details>

## 5. Run a full-text search for the phrase `"query plan"` ranked by ts_rank.

<details><summary>Solution</summary>

```sql
SELECT id, title,
       ts_rank(fts, q) AS rank
FROM app.posts, phraseto_tsquery('english', 'query plan') q
WHERE fts @@ q
ORDER BY rank DESC
LIMIT 10;
```
</details>

## 6. Combine FTS and trigram in a hybrid score: FTS rank if it matches, else similarity.

<details><summary>Solution</summary>

```sql
SELECT id, title,
       coalesce(ts_rank(fts, q), 0)              AS fts_rank,
       similarity(title, :query::text)           AS trgm_sim,
       (coalesce(ts_rank(fts, q), 0) * 5)
         + similarity(title, :query::text)       AS hybrid
FROM app.posts, websearch_to_tsquery('english', :query) q
WHERE fts @@ q OR title % :query
ORDER BY hybrid DESC
LIMIT 10;
```
The weight `5` is a tuning knob; pick it empirically.
</details>

## 7. Build a GIN index on `app.users.profile` for `?` key-existence queries, then query users that have a `prefs.theme` set.

<details><summary>Solution</summary>

```sql
CREATE INDEX users_profile_gin_idx ON app.users USING gin (profile);
SELECT id FROM app.users WHERE profile #> '{prefs}' ? 'theme';
```
`jsonb_ops` (the default) supports `?`, `?|`, `?&` and `@>`. `jsonb_path_ops` does **not** support `?`.
</details>

## 8. Find products tagged `'sale'` using `jsonpath`.

<details><summary>Solution</summary>

```sql
SELECT id, name FROM app.products
WHERE attributes @? '$.tags[*] ? (@ == "sale")';
```
</details>

## 9. Why does this query NOT use `products_attrs_gin_idx`?
```sql
SELECT id FROM app.products WHERE attributes ? 'color';
```

<details><summary>Solution</summary>

`products_attrs_gin_idx` uses `jsonb_path_ops`, which only supports `@>`. The `?` operator needs `jsonb_ops`. Add a second index, or use a containment query if appropriate.
</details>

## 10. Postgres FTS is fast but lacks semantic understanding (synonyms, paraphrase). What is the canonical way to add it in Postgres?

<details><summary>Solution</summary>

Vector search with **pgvector**: store embeddings of documents, search by cosine distance with an HNSW or IVFFlat index. Module 12 builds this end-to-end. For best results, combine FTS (precision on exact tokens) with vector search (semantic recall) — hybrid retrieval.
</details>
