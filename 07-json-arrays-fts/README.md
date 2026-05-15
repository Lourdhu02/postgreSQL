# 07 — JSON, Arrays, Full-Text Search

By the end you can:
1. Query and index `jsonb` documents with `@>`, `->`, `->>`, `#>`, and the SQL/JSON path language.
2. Manipulate `text[]` and other arrays; pick between arrays and junction tables.
3. Run high-quality full-text search with `tsvector`, `tsquery`, ranking, and trigram fuzzy matching.

**Time budget:** 60 min reading + 60 min lab.

## jsonb vs json

Use **`jsonb`** for storage. It is binary, parsed once, indexable, and supports the rich operator set below. `json` preserves the original text and key order — only useful if you must round-trip exact whitespace.

```sql
-- preferred
profile jsonb NOT NULL DEFAULT '{}'::jsonb
```

## jsonb operators

| Op | Returns | Example |
|----|---------|---------|
| `->`   | `jsonb` element by key/index | `profile -> 'prefs'` |
| `->>`  | `text` element by key/index  | `profile ->> 'tier'` |
| `#>`   | `jsonb` at path (array of keys) | `profile #> '{prefs,theme}'` |
| `#>>`  | `text` at path | `profile #>> '{prefs,theme}'` |
| `@>`   | contains (left contains right) | `profile @> '{"role":"admin"}'` |
| `<@`   | contained by | |
| `?`    | key exists | `profile ? 'tier'` |
| `?\|`   | any key exists | `profile ?\| ARRAY['tier','role']` |
| `?&amp;`   | all keys exist | |
| `\|\|`   | concatenate / merge | `'{"a":1}' \|\| '{"b":2}'` |
| `-`    | delete key | `'{"a":1,"b":2}'::jsonb - 'a'` |
| `#-`   | delete at path | |

For numeric extraction, cast explicitly: `(profile->>'level')::int`.

Full list: <https://www.postgresql.org/docs/17/functions-json.html>.

### Indexing jsonb

```sql
-- jsonb_ops: supports ?, ?|, ?&, @>, jsonpath operators. Largest.
CREATE INDEX users_profile_gin_idx ON app.users USING gin (profile);

-- jsonb_path_ops: only @>. Smaller, faster. Use when you only need containment.
CREATE INDEX products_attrs_gin_idx ON app.products USING gin (attributes jsonb_path_ops);

-- Expression index for a specific scalar field
CREATE INDEX users_tier_idx ON app.users ((profile->>'tier'));
```

Rule: index the shape that matches your queries. A single GIN with `jsonb_ops` covers many queries but pays a write-time tax.

### SQL/JSON path (`@@` and `@?` with `jsonpath`)

PG 12+ introduced the `jsonpath` type. PG 17 expands the SQL/JSON conformance further. For containment-style queries, `@>` is enough; for filtered traversal of nested arrays, `jsonpath` is the right tool:

```sql
-- Products whose 'tags' array contains 'sale'
SELECT id, name
FROM app.products
WHERE attributes @? '$.tags[*] ? (@ == "sale")';

-- Same shape with @@ (predicate must be boolean)
SELECT id, name
FROM app.products
WHERE attributes @@ '$.specs.warranty_years >= 2';
```

See <https://www.postgresql.org/docs/17/functions-json.html#FUNCTIONS-SQLJSON-PATH>.

### Building &amp; mutating

```sql
-- Build a jsonb literal from columns
SELECT jsonb_build_object('id', id, 'email', email, 'tier', profile->>'tier')
FROM app.users LIMIT 3;

-- Aggregate rows into an array of objects
SELECT jsonb_agg(jsonb_build_object('id', id, 'title', title))
FROM app.posts WHERE author_id = 1;

-- Update a nested field (replaces the key at the path)
UPDATE app.users
SET profile = jsonb_set(profile, '{prefs,theme}', '"high-contrast"', true)
WHERE id = 1;

-- Remove a key
UPDATE app.users SET profile = profile - 'old_field' WHERE id = 1;
```

## Arrays

Arrays are good for **small, unordered (or order-stable) collections that always travel with the row** and that you query as a whole. They are bad for many-to-many relationships (no FK to elements, no easy join semantics).

```sql
-- declared in seed: tags text[] NOT NULL DEFAULT '{}'

-- contains
SELECT id, title FROM app.posts WHERE tags @> ARRAY['pgvector'];

-- overlaps (any element in common)
SELECT id, title FROM app.posts WHERE tags &amp;&amp; ARRAY['pgvector','rag'];

-- equals one of these elements
SELECT id FROM app.posts WHERE 'rag' = ANY (tags);

-- explode to rows
SELECT id, t FROM app.posts, unnest(tags) AS t;

-- aggregate rows back into an array
SELECT author_id, array_agg(DISTINCT t ORDER BY t)
FROM (SELECT author_id, unnest(tags) t FROM app.posts) s
GROUP BY author_id;
```

GIN on `text[]` (with the default `array_ops` operator class) supports `@>`, `<@`, `&amp;&amp;`, `=`.

## Full-text search

Postgres FTS lives in three types:

- `tsvector` — a normalized document (lexemes + positions + weights).
- `tsquery` — a normalized query.
- `regconfig` — a text-search configuration (controls language stemming/stopwords). Common values: `'english'`, `'simple'`.

```sql
SELECT to_tsvector('english', 'PostgreSQL ships with full-text search.');
-- 'full-text':4 'postgresql':1 'search':5 'ship':2

SELECT to_tsquery('english', 'postgres &amp; (search | index)');
-- 'postgr' &amp; ( 'search' | 'index' )
```

### Storing and indexing

In the seed, `posts.fts` is a generated `tsvector` weighted A (title) and B (body), indexed by GIN. That is the production pattern: pre-compute the `tsvector`, store it, index it.

```sql
posts.fts tsvector GENERATED ALWAYS AS (
    setweight(to_tsvector('english', coalesce(title, '')), 'A') ||
    setweight(to_tsvector('english', coalesce(body,  '')), 'B')
) STORED;

CREATE INDEX posts_fts_idx ON app.posts USING gin (fts);
```

### Querying

```sql
SELECT id, title,
       ts_rank(fts, plainto_tsquery('english', 'pgvector hnsw')) AS rank
FROM app.posts
WHERE fts @@ plainto_tsquery('english', 'pgvector hnsw')
ORDER BY rank DESC, published_at DESC NULLS LAST
LIMIT 10;
```

Query parsers:

| Parser | Purpose |
|--------|---------|
| `plainto_tsquery`   | AND all words. `'cat dog'` → `'cat' &amp; 'dog'`. |
| `phraseto_tsquery`  | Phrase distance. `'cat dog'` → `'cat' <-> 'dog'`. |
| `websearch_to_tsquery` | Google-like syntax: quoted phrases, `OR`, `-` for negation. Recommended for user input. |
| `to_tsquery`        | Hand-build operators. Reject untrusted input. |

`ts_rank` and `ts_rank_cd` rank by frequency / cover density. They are heuristics — many teams add a tiebreaker on freshness or popularity.

### Highlighting

```sql
SELECT id, ts_headline('english', body, websearch_to_tsquery('english', '"vector search"'))
FROM app.posts
WHERE fts @@ websearch_to_tsquery('english', '"vector search"');
```

### Multiple languages

If the body language varies, store the language in a column and use the dynamic form:
```sql
to_tsvector(posts.lang::regconfig, posts.body)
```

## Trigram (fuzzy) search

`pg_trgm` powers similarity, typo tolerance, and `LIKE '%foo%'` acceleration.

```sql
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Substring/contains search accelerated by GIN
CREATE INDEX posts_title_trgm_idx ON app.posts USING gin (title gin_trgm_ops);
SELECT id, title FROM app.posts WHERE title ILIKE '%pgvec%';

-- Similarity
SELECT id, title, similarity(title, 'pgvecto')
FROM app.posts
WHERE title % 'pgvecto'           -- '%' is the similarity operator
ORDER BY title <-> 'pgvecto'      -- distance for ranking
LIMIT 10;
```

Combine FTS and trigram: use FTS as the primary signal and trigram as a fallback when the user mistypes.

## When to use what

| Need | Tool |
|------|------|
| Schema-rigid attributes | columns + indexes |
| Flexible per-row attributes | `jsonb` + GIN |
| Small in-row collections | `text[]` |
| Many-to-many with attributes | junction table (`post_categories`) |
| English / language-aware search | `tsvector` + GIN |
| Substring or typo-tolerant search | `pg_trgm` + GIN |
| Semantic search (embeddings) | `pgvector` (module 12) |

## Run the lab

```powershell
psql -U postgres -d pgcourse -f 07-json-arrays-fts/lab.sql
```

## References

- JSON functions / operators: <https://www.postgresql.org/docs/17/functions-json.html>
- Array functions: <https://www.postgresql.org/docs/17/functions-array.html>
- Full-text search: <https://www.postgresql.org/docs/17/textsearch.html>
- `pg_trgm`: <https://www.postgresql.org/docs/17/pgtrgm.html>

## Next

[Module 08 — Procedures &amp; Triggers →](../08-procedures-triggers/)
