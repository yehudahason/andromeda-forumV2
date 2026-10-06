-- Change these two values to existing IDs:
-- forum_id = 9
-- user_id  = your existing Neon Auth user UUID

INSERT INTO threads (
    forum_id,
    user_id,
    title,
    content,
    notify,
    sticky,
    created_at,
    updated_at
)
SELECT
    1 AS forum_id,
    '92088acc-8c08-4dfc-80f7-21d9290d5d6d'::uuid AS user_id,
    'Dummy Thread ' || n AS title,
    '<p>This is dummy content for thread ' || n || '.</p>' AS content,
    FALSE AS notify,
    FALSE AS sticky,
    NOW() - ((100 - n) * INTERVAL '1 minute') AS created_at,
    NOW() - ((100 - n) * INTERVAL '1 minute') AS updated_at
FROM generate_series(1, 100) AS n;


INSERT INTO replies (
    id,
    thread_id,
    user_id,
    post,
    created_at,
    updated_at
)
SELECT
    gen_random_uuid(),
    1,
    (
        SELECT id
        FROM auth."users"
        ORDER BY random()
        LIMIT 1
    ),
    
    '<p>This is dummy reply number ' || gs || '.</p>',
    NOW() - (gs || ' minutes')::interval,
    NOW() - (gs || ' minutes')::interval
FROM generate_series(1, 100) AS gs;