
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
    5,
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