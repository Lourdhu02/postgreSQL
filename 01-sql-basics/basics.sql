-- Active: 1777459469237@@127.0.0.1@5432@postgres@app
SELECT * FROM users LIMIT 10;


SELECT id, title, published_at from posts
where published_at IS NOT NULL
ORDER BY published_at DESC, id DESC
LIMIT 10;

SELECT * FROM orders

SELECT status, count(*) AS n
FROM orders
GROUP BY status
ORDER BY n DESC


SELECT * FROM users;

SELECT id, email from users
WHERE split_part(email, '@', 2) = 'example.com'


select * from posts

select count(*) from posts
where published_at IS NULL

select * from products


SELECT id, name , to_char(price_cents/100.0, 'FM999990.00') AS price_dollars from products
ORDER BY price_cents DESC,id
LIMIT 5
