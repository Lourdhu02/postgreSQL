-- 00-foundations/lab.sql
-- Run this after seed/schema.sql and seed/data.sql have loaded.
-- Usage:  psql -U postgres -d pgcourse -f 00-foundations/lab.sql

-- WHY: confirm we are connected to the right database before touching anything.
SELECT current_database(), current_user, version();

-- WHY: the seed lives in schema 'app'. Setting search_path saves typing in labs.
SET search_path = app, public;

-- WHY: confirm seed counts. If any of these are zero, re-run data.sql.
SELECT 'users'       AS table_name, count(*) FROM users
UNION ALL SELECT 'posts',       count(*) FROM posts
UNION ALL SELECT 'comments',    count(*) FROM comments
UNION ALL SELECT 'products',    count(*) FROM products
UNION ALL SELECT 'orders',      count(*) FROM orders
UNION ALL SELECT 'order_items', count(*) FROM order_items
UNION ALL SELECT 'inventory',   count(*) FROM inventory;

-- WHY: peek at one row of every table to confirm shapes match what later
-- modules assume. \x in psql makes wide rows readable.
SELECT * FROM users    LIMIT 1;
SELECT * FROM posts    LIMIT 1;
SELECT * FROM products LIMIT 1;

-- WHY: extensions installed by schema.sql should be visible here.
SELECT extname, extversion
FROM pg_extension
WHERE extname IN ('pg_trgm','citext');
