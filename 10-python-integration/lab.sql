-- 10-python-integration/lab.sql
-- The bulk of this module lives in lab.ipynb. This file holds the SQL that
-- the notebook's cells refer to, for users who prefer copy/paste from psql.

SET search_path = app, public;

-- 1. Parameterized SELECT (from Python this is %s or $1)
SELECT id, email FROM users WHERE id = 1;

-- 2. Insert returning the new row's id (used by Alembic-managed inserts)
INSERT INTO users (email, full_name)
VALUES ('python-demo@example.com', 'Python Demo')
RETURNING id;

-- 3. UPSERT (used in lab to demonstrate ON CONFLICT in Python)
INSERT INTO users (email, full_name)
VALUES ('python-demo@example.com', 'Python Demo 2')
ON CONFLICT (email) DO UPDATE SET full_name = EXCLUDED.full_name
RETURNING *;

-- 4. Server-side cursor candidate (when streaming millions of rows)
-- SELECT id, body FROM posts;  -- in Python: cursor(name='...')

-- 5. COPY: fastest bulk load. In Python: cur.copy('COPY ... FROM STDIN').
-- COPY users (email, full_name) FROM STDIN WITH (FORMAT csv);

-- Cleanup
DELETE FROM users WHERE email = 'python-demo@example.com';
