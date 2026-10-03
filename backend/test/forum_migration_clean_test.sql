-- =========================================================
-- Forum migration - full integration test
-- Target: forum_user_message_count.sql
--
-- What this tests:
--   * Every trigger function created by the migration exists.
--   * Every trigger created by the migration exists.
--   * Forum insert initialization.
--   * updated_at behavior on forums, threads, and replies.
--   * Thread insert initialization and user message counting.
--   * Reply insert validation and user message counting.
--   * Immutable relation/creation-field guards.
--   * Forum/thread denormalized-field guards.
--   * Thread-title synchronization into thread/forum last-post state.
--   * Reply insert last-post/count maintenance, including out-of-order replies.
--   * Reply deletion recalculation with and without remaining replies.
--   * Statement-level bulk reply deletion.
--   * Thread deletion, including cascaded reply deletion.
--   * Forum deletion cascading through threads/replies.
--   * User replies_count semantics = opened threads + replies.
--
-- Safety:
--   * Run AFTER the UP migration.
--   * Requires at least one existing row in neon_auth."user".
--   * All test data and counter changes are wrapped in one transaction.
--   * The script ends with ROLLBACK, so no test data is kept.
-- =========================================================

BEGIN;

SET LOCAL client_min_messages = NOTICE;
SET LOCAL TIME ZONE 'UTC';

-- =========================================================
-- TEST HELPERS
-- =========================================================

CREATE OR REPLACE FUNCTION pg_temp.assert_true(
    p_condition BOOLEAN,
    p_label TEXT
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    IF COALESCE(p_condition, FALSE) IS NOT TRUE THEN
        RAISE EXCEPTION 'FAIL: %', p_label;
    END IF;

    RAISE NOTICE 'PASS: %', p_label;
END;
$$;


CREATE OR REPLACE FUNCTION pg_temp.expect_error(
    p_sql TEXT,
    p_expected_message TEXT,
    p_label TEXT
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_failed BOOLEAN := FALSE;
    v_message TEXT;
BEGIN
    BEGIN
        EXECUTE p_sql;
    EXCEPTION
        WHEN OTHERS THEN
            v_failed := TRUE;
            v_message := SQLERRM;

            IF position(p_expected_message IN v_message) = 0 THEN
                RAISE EXCEPTION
                    'FAIL: % -- expected error containing %, got %',
                    p_label,
                    p_expected_message,
                    v_message;
            END IF;
    END;

    IF NOT v_failed THEN
        RAISE EXCEPTION
            'FAIL: % -- statement succeeded but an error containing % was expected',
            p_label,
            p_expected_message;
    END IF;

    RAISE NOTICE 'PASS: %', p_label;
END;
$$;


-- =========================================================
-- TEST CONTEXT
-- Use one existing auth user and compare all counter changes against
-- that user's original replies_count.
-- =========================================================

CREATE TEMP TABLE _forum_migration_test_ctx (
    user_id UUID NOT NULL,
    baseline_user_count BIGINT NOT NULL,

    forum_id BIGINT,
    thread_a BIGINT,
    thread_b BIGINT,
    reply_latest UUID,
    reply_old UUID,

    cascade_forum_id BIGINT,
    cascade_thread_1 BIGINT,
    cascade_thread_2 BIGINT,
    cascade_reply_1 UUID,
    cascade_reply_2 UUID
) ON COMMIT DROP;

INSERT INTO _forum_migration_test_ctx (
    user_id,
    baseline_user_count
)
SELECT
    id,
    replies_count
FROM neon_auth."user"
LIMIT 1;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM _forum_migration_test_ctx) THEN
        RAISE EXCEPTION
            'TEST PRECONDITION FAILED: neon_auth."user" must contain at least one user';
    END IF;
END;
$$;

DO $$
BEGIN
    RAISE NOTICE 'Using an existing auth user; all changes will be rolled back.';
END;
$$;

-- =========================================================
-- 1. VERIFY ALL MIGRATION FUNCTIONS EXIST
-- =========================================================

DO $$
DECLARE
    v_name TEXT;
BEGIN
    FOREACH v_name IN ARRAY ARRAY[
        'forum_prepare_forum_insert',
        'forum_set_updated_at',
        'forum_prepare_thread_insert',
        'forum_prevent_thread_relation_changes',
        'forum_prevent_reply_relation_changes',
        'forum_validate_reply_insert',
        'forum_guard_forum_denormalized_update',
        'forum_guard_thread_denormalized_update',
        'forum_after_thread_insert',
        'forum_sync_thread_title',
        'forum_after_thread_title_update',
        'forum_after_reply_insert',
        'forum_after_reply_delete',
        'forum_after_thread_delete'
    ]
    LOOP
        IF to_regprocedure(v_name || '()') IS NULL THEN
            RAISE EXCEPTION 'FAIL: required function %() does not exist', v_name;
        END IF;
    END LOOP;

    RAISE NOTICE 'PASS: all 14 migration trigger functions exist';
END;
$$;


-- =========================================================
-- 2. VERIFY ALL MIGRATION TRIGGERS EXIST
-- =========================================================

DO $$
DECLARE
    v RECORD;
BEGIN
    FOR v IN
        SELECT *
        FROM (
            VALUES
                ('forums',  'forums_prepare_insert'),
                ('forums',  'forums_set_updated_at'),
                ('threads', 'threads_set_updated_at'),
                ('replies', 'replies_set_updated_at'),
                ('threads', 'threads_prepare_insert'),
                ('threads', 'threads_prevent_relation_changes'),
                ('replies', 'replies_prevent_relation_changes'),
                ('replies', 'replies_validate_insert'),
                ('forums',  'forums_guard_denormalized_update'),
                ('threads', 'threads_guard_denormalized_update'),
                ('threads', 'threads_after_insert'),
                ('threads', 'threads_sync_title'),
                ('threads', 'threads_after_title_update'),
                ('replies', 'replies_after_insert'),
                ('replies', 'replies_after_delete'),
                ('threads', 'threads_after_delete')
        ) AS x(table_name, trigger_name)
    LOOP
        IF NOT EXISTS (
            SELECT 1
            FROM pg_trigger AS t
            WHERE t.tgrelid = to_regclass(v.table_name)
              AND t.tgname = v.trigger_name
              AND NOT t.tgisinternal
        ) THEN
            RAISE EXCEPTION
                'FAIL: trigger % on table % does not exist',
                v.trigger_name,
                v.table_name;
        END IF;
    END LOOP;

    RAISE NOTICE 'PASS: all 16 migration triggers exist';
END;
$$;


-- =========================================================
-- 3. forum_prepare_forum_insert()
-- Trigger-maintained values supplied by the caller must be discarded.
-- =========================================================

WITH inserted AS (
    INSERT INTO forums (
        sort_order,
        name,
        description,
        messages_count,
        last_post_thread_id,
        last_post_title,
        last_post_author_id,
        last_post_date,
        created_at,
        updated_at
    )
    SELECT
        900001,
        '__forum_migration_test__',
        'initial description',
        999,
        9223372036854775000,
        'SHOULD BE CLEARED',
        c.user_id,
        TIMESTAMPTZ '2099-12-31 23:59:59+00',
        TIMESTAMPTZ '2099-01-01 00:00:00+00',
        TIMESTAMPTZ '2000-01-01 00:00:00+00'
    FROM _forum_migration_test_ctx AS c
    RETURNING id
)
UPDATE _forum_migration_test_ctx AS c
SET forum_id = inserted.id
FROM inserted;

SELECT pg_temp.assert_true(
    (
        SELECT f.messages_count = 0
        FROM forums AS f
        JOIN _forum_migration_test_ctx AS c ON c.forum_id = f.id
    ),
    'forum insert forces messages_count = 0'
);

SELECT pg_temp.assert_true(
    (
        SELECT
            f.last_post_thread_id IS NULL
            AND f.last_post_title = ''
            AND f.last_post_author_id IS NULL
            AND f.last_post_date IS NULL
        FROM forums AS f
        JOIN _forum_migration_test_ctx AS c ON c.forum_id = f.id
    ),
    'forum insert clears all caller-supplied last-post fields'
);


-- =========================================================
-- 4. forum_set_updated_at() on forums
-- =========================================================

UPDATE forums
SET description = 'updated description'
WHERE id = (SELECT forum_id FROM _forum_migration_test_ctx);

SELECT pg_temp.assert_true(
    (
        SELECT f.updated_at > TIMESTAMPTZ '2000-01-01 00:00:00+00'
        FROM forums AS f
        JOIN _forum_migration_test_ctx AS c ON c.forum_id = f.id
    ),
    'forum update refreshes updated_at'
);


-- =========================================================
-- 5. forum_guard_forum_denormalized_update()
-- =========================================================

SELECT pg_temp.expect_error(
    'UPDATE forums
     SET messages_count = messages_count + 1
     WHERE id = (SELECT forum_id FROM _forum_migration_test_ctx)',
    'forum message/last-post fields are trigger-maintained',
    'direct forum messages_count update is rejected'
);

SELECT pg_temp.expect_error(
    'UPDATE forums
     SET last_post_title = ''ILLEGAL''
     WHERE id = (SELECT forum_id FROM _forum_migration_test_ctx)',
    'forum message/last-post fields are trigger-maintained',
    'direct forum last_post_title update is rejected'
);

SELECT pg_temp.expect_error(
    'UPDATE forums
     SET last_post_date = clock_timestamp()
     WHERE id = (SELECT forum_id FROM _forum_migration_test_ctx)',
    'forum message/last-post fields are trigger-maintained',
    'direct forum last_post_date update is rejected'
);

SELECT pg_temp.expect_error(
    'UPDATE forums
     SET last_post_thread_id = 9223372036854775000
     WHERE id = (SELECT forum_id FROM _forum_migration_test_ctx)',
    'forum message/last-post fields are trigger-maintained',
    'direct non-NULL forum last_post_thread_id update is rejected'
);

SELECT pg_temp.expect_error(
    'UPDATE forums
     SET last_post_author_id = gen_random_uuid()
     WHERE id = (SELECT forum_id FROM _forum_migration_test_ctx)',
    'forum message/last-post fields are trigger-maintained',
    'direct non-NULL forum last_post_author_id update is rejected'
);


-- =========================================================
-- 6. forum_prepare_thread_insert(): reject NULL user_id
-- =========================================================

SELECT pg_temp.expect_error(
    'INSERT INTO threads (forum_id, user_id, title, content)
     SELECT forum_id, NULL, ''NULL USER THREAD'', ''body''
     FROM _forum_migration_test_ctx',
    'new thread user_id cannot be NULL',
    'new thread requires user_id'
);


-- =========================================================
-- 7. forum_prepare_thread_insert() + forum_after_thread_insert()
-- Also verifies user replies_count includes opened threads.
-- =========================================================

WITH inserted AS (
    INSERT INTO threads (
        forum_id,
        user_id,
        title,
        content,
        messages_count,
        last_post_title,
        last_post_author_id,
        last_post_date,
        created_at,
        updated_at
    )
    SELECT
        c.forum_id,
        c.user_id,
        'Thread A',
        'Thread A body',
        777,
        'SHOULD BE REPLACED',
        NULL,
        TIMESTAMPTZ '1999-01-01 00:00:00+00',
        TIMESTAMPTZ '2099-01-01 00:00:00+00',
        TIMESTAMPTZ '2000-01-01 00:00:00+00'
    FROM _forum_migration_test_ctx AS c
    RETURNING id
)
UPDATE _forum_migration_test_ctx AS c
SET thread_a = inserted.id
FROM inserted;

SELECT pg_temp.assert_true(
    (
        SELECT
            t.messages_count = 0
            AND t.last_post_title = t.title
            AND t.last_post_author_id = c.user_id
            AND t.last_post_date = t.created_at
        FROM threads AS t
        JOIN _forum_migration_test_ctx AS c ON c.thread_a = t.id
    ),
    'thread insert initializes reply count and last-post fields from opening post'
);

SELECT pg_temp.assert_true(
    (
        SELECT
            f.messages_count = 1
            AND f.last_post_thread_id = c.thread_a
            AND f.last_post_title = 'Thread A'
            AND f.last_post_author_id = c.user_id
            AND f.last_post_date = TIMESTAMPTZ '2099-01-01 00:00:00+00'
        FROM forums AS f
        JOIN _forum_migration_test_ctx AS c ON c.forum_id = f.id
    ),
    'thread insert updates forum count and last-post state'
);

SELECT pg_temp.assert_true(
    (
        SELECT u.replies_count = c.baseline_user_count + 1
        FROM neon_auth."user" AS u
        JOIN _forum_migration_test_ctx AS c ON c.user_id = u.id
    ),
    'opening a thread increments user replies_count by 1'
);


-- =========================================================
-- 8. forum_set_updated_at() on threads
-- =========================================================

UPDATE threads
SET content = 'Thread A body updated'
WHERE id = (SELECT thread_a FROM _forum_migration_test_ctx);

SELECT pg_temp.assert_true(
    (
        SELECT t.updated_at > TIMESTAMPTZ '2000-01-01 00:00:00+00'
        FROM threads AS t
        JOIN _forum_migration_test_ctx AS c ON c.thread_a = t.id
    ),
    'thread update refreshes updated_at'
);


-- =========================================================
-- 9. forum_prevent_thread_relation_changes()
-- =========================================================

SELECT pg_temp.expect_error(
    'UPDATE threads
     SET forum_id = forum_id + 900000000
     WHERE id = (SELECT thread_a FROM _forum_migration_test_ctx)',
    'thread forum_id cannot be changed',
    'thread forum_id is immutable'
);

SELECT pg_temp.expect_error(
    'UPDATE threads
     SET user_id = gen_random_uuid()
     WHERE id = (SELECT thread_a FROM _forum_migration_test_ctx)',
    'thread user_id cannot be changed',
    'thread non-NULL user_id is immutable'
);

SELECT pg_temp.expect_error(
    'UPDATE threads
     SET created_at = created_at + INTERVAL ''1 second''
     WHERE id = (SELECT thread_a FROM _forum_migration_test_ctx)',
    'thread created_at cannot be changed',
    'thread created_at is immutable'
);


-- =========================================================
-- 10. forum_guard_thread_denormalized_update()
-- =========================================================

SELECT pg_temp.expect_error(
    'UPDATE threads
     SET messages_count = messages_count + 1
     WHERE id = (SELECT thread_a FROM _forum_migration_test_ctx)',
    'thread message/last-post fields are trigger-maintained',
    'direct thread messages_count update is rejected'
);

SELECT pg_temp.expect_error(
    'UPDATE threads
     SET last_post_title = ''ILLEGAL''
     WHERE id = (SELECT thread_a FROM _forum_migration_test_ctx)',
    'thread message/last-post fields are trigger-maintained',
    'direct thread last_post_title update is rejected'
);

SELECT pg_temp.expect_error(
    'UPDATE threads
     SET last_post_date = last_post_date + INTERVAL ''1 second''
     WHERE id = (SELECT thread_a FROM _forum_migration_test_ctx)',
    'thread message/last-post fields are trigger-maintained',
    'direct thread last_post_date update is rejected'
);

SELECT pg_temp.expect_error(
    'UPDATE threads
     SET last_post_author_id = gen_random_uuid()
     WHERE id = (SELECT thread_a FROM _forum_migration_test_ctx)',
    'thread message/last-post fields are trigger-maintained',
    'direct non-NULL thread last_post_author_id update is rejected'
);


-- =========================================================
-- 11. forum_sync_thread_title() + forum_after_thread_title_update()
-- Latest thread title must synchronize into both thread and forum.
-- =========================================================

UPDATE threads
SET title = 'Thread A renamed'
WHERE id = (SELECT thread_a FROM _forum_migration_test_ctx);

SELECT pg_temp.assert_true(
    (
        SELECT t.last_post_title = 'Thread A renamed'
        FROM threads AS t
        JOIN _forum_migration_test_ctx AS c ON c.thread_a = t.id
    ),
    'thread title update synchronizes thread.last_post_title'
);

SELECT pg_temp.assert_true(
    (
        SELECT f.last_post_title = 'Thread A renamed'
        FROM forums AS f
        JOIN _forum_migration_test_ctx AS c ON c.forum_id = f.id
    ),
    'latest thread title update synchronizes forum.last_post_title'
);


-- =========================================================
-- 12. forum_validate_reply_insert(): reject NULL user_id
-- =========================================================

SELECT pg_temp.expect_error(
    'INSERT INTO replies (thread_id, user_id, post)
     SELECT thread_a, NULL, ''NULL USER REPLY''
     FROM _forum_migration_test_ctx',
    'new reply user_id cannot be NULL',
    'new reply requires user_id'
);


-- =========================================================
-- 13. forum_after_reply_insert()
-- Insert newest reply first.
-- =========================================================

WITH inserted AS (
    INSERT INTO replies (
        thread_id,
        user_id,
        post,
        created_at,
        updated_at
    )
    SELECT
        c.thread_a,
        c.user_id,
        'Newest reply',
        TIMESTAMPTZ '2099-01-01 02:00:00+00',
        TIMESTAMPTZ '2000-01-01 00:00:00+00'
    FROM _forum_migration_test_ctx AS c
    RETURNING id
)
UPDATE _forum_migration_test_ctx AS c
SET reply_latest = inserted.id
FROM inserted;

SELECT pg_temp.assert_true(
    (
        SELECT
            t.messages_count = 1
            AND t.last_post_date = TIMESTAMPTZ '2099-01-01 02:00:00+00'
            AND t.last_post_author_id = c.user_id
        FROM threads AS t
        JOIN _forum_migration_test_ctx AS c ON c.thread_a = t.id
    ),
    'reply insert increments thread reply count and advances thread last-post state'
);

SELECT pg_temp.assert_true(
    (
        SELECT
            f.messages_count = 2
            AND f.last_post_thread_id = c.thread_a
            AND f.last_post_date = TIMESTAMPTZ '2099-01-01 02:00:00+00'
        FROM forums AS f
        JOIN _forum_migration_test_ctx AS c ON c.forum_id = f.id
    ),
    'reply insert increments forum total message count and advances forum last-post state'
);

SELECT pg_temp.assert_true(
    (
        SELECT u.replies_count = c.baseline_user_count + 2
        FROM neon_auth."user" AS u
        JOIN _forum_migration_test_ctx AS c ON c.user_id = u.id
    ),
    'reply insert increments user replies_count'
);


-- =========================================================
-- 14. Out-of-order reply insert
-- Count must increase, but an older reply must not replace last-post state.
-- =========================================================

WITH inserted AS (
    INSERT INTO replies (
        thread_id,
        user_id,
        post,
        created_at,
        updated_at
    )
    SELECT
        c.thread_a,
        c.user_id,
        'Older reply inserted later',
        TIMESTAMPTZ '2099-01-01 01:00:00+00',
        TIMESTAMPTZ '2000-01-01 00:00:00+00'
    FROM _forum_migration_test_ctx AS c
    RETURNING id
)
UPDATE _forum_migration_test_ctx AS c
SET reply_old = inserted.id
FROM inserted;

SELECT pg_temp.assert_true(
    (
        SELECT
            t.messages_count = 2
            AND t.last_post_date = TIMESTAMPTZ '2099-01-01 02:00:00+00'
        FROM threads AS t
        JOIN _forum_migration_test_ctx AS c ON c.thread_a = t.id
    ),
    'older out-of-order reply increments count without replacing thread last-post date'
);

SELECT pg_temp.assert_true(
    (
        SELECT
            f.messages_count = 3
            AND f.last_post_date = TIMESTAMPTZ '2099-01-01 02:00:00+00'
        FROM forums AS f
        JOIN _forum_migration_test_ctx AS c ON c.forum_id = f.id
    ),
    'older out-of-order reply increments forum count without replacing forum last-post date'
);

SELECT pg_temp.assert_true(
    (
        SELECT u.replies_count = c.baseline_user_count + 3
        FROM neon_auth."user" AS u
        JOIN _forum_migration_test_ctx AS c ON c.user_id = u.id
    ),
    'user count equals one opened thread plus two replies'
);


-- =========================================================
-- 15. forum_set_updated_at() on replies
-- =========================================================

UPDATE replies
SET post = 'Older reply edited'
WHERE id = (SELECT reply_old FROM _forum_migration_test_ctx);

SELECT pg_temp.assert_true(
    (
        SELECT r.updated_at > TIMESTAMPTZ '2000-01-01 00:00:00+00'
        FROM replies AS r
        JOIN _forum_migration_test_ctx AS c ON c.reply_old = r.id
    ),
    'reply update refreshes updated_at'
);


-- =========================================================
-- 16. forum_prevent_reply_relation_changes()
-- =========================================================

SELECT pg_temp.expect_error(
    'UPDATE replies
     SET thread_id = thread_id + 900000000
     WHERE id = (SELECT reply_old FROM _forum_migration_test_ctx)',
    'reply thread_id cannot be changed',
    'reply thread_id is immutable'
);

SELECT pg_temp.expect_error(
    'UPDATE replies
     SET user_id = gen_random_uuid()
     WHERE id = (SELECT reply_old FROM _forum_migration_test_ctx)',
    'reply user_id cannot be changed',
    'reply non-NULL user_id is immutable'
);

SELECT pg_temp.expect_error(
    'UPDATE replies
     SET created_at = created_at + INTERVAL ''1 second''
     WHERE id = (SELECT reply_old FROM _forum_migration_test_ctx)',
    'reply created_at cannot be changed',
    'reply created_at is immutable'
);


-- =========================================================
-- 17. forum_after_reply_delete(): delete latest reply
-- Remaining older reply must become the last reply.
-- =========================================================

DELETE FROM replies
WHERE id = (SELECT reply_latest FROM _forum_migration_test_ctx);

SELECT pg_temp.assert_true(
    (
        SELECT
            t.messages_count = 1
            AND t.last_post_date = TIMESTAMPTZ '2099-01-01 01:00:00+00'
        FROM threads AS t
        JOIN _forum_migration_test_ctx AS c ON c.thread_a = t.id
    ),
    'deleting latest reply recalculates thread to remaining latest reply'
);

SELECT pg_temp.assert_true(
    (
        SELECT
            f.messages_count = 2
            AND f.last_post_thread_id = c.thread_a
            AND f.last_post_date = TIMESTAMPTZ '2099-01-01 01:00:00+00'
        FROM forums AS f
        JOIN _forum_migration_test_ctx AS c ON c.forum_id = f.id
    ),
    'deleting latest reply recalculates forum last-post state'
);

SELECT pg_temp.assert_true(
    (
        SELECT u.replies_count = c.baseline_user_count + 2
        FROM neon_auth."user" AS u
        JOIN _forum_migration_test_ctx AS c ON c.user_id = u.id
    ),
    'deleting one reply decrements user replies_count by 1'
);


-- =========================================================
-- 18. forum_after_reply_delete(): delete final reply
-- Thread/forum must fall back to the opening post.
-- =========================================================

DELETE FROM replies
WHERE id = (SELECT reply_old FROM _forum_migration_test_ctx);

SELECT pg_temp.assert_true(
    (
        SELECT
            t.messages_count = 0
            AND t.last_post_author_id = c.user_id
            AND t.last_post_date = TIMESTAMPTZ '2099-01-01 00:00:00+00'
        FROM threads AS t
        JOIN _forum_migration_test_ctx AS c ON c.thread_a = t.id
    ),
    'deleting final reply restores thread last-post state to opening post'
);

SELECT pg_temp.assert_true(
    (
        SELECT
            f.messages_count = 1
            AND f.last_post_thread_id = c.thread_a
            AND f.last_post_author_id = c.user_id
            AND f.last_post_date = TIMESTAMPTZ '2099-01-01 00:00:00+00'
        FROM forums AS f
        JOIN _forum_migration_test_ctx AS c ON c.forum_id = f.id
    ),
    'deleting final reply restores forum last-post state to opening thread'
);

SELECT pg_temp.assert_true(
    (
        SELECT u.replies_count = c.baseline_user_count + 1
        FROM neon_auth."user" AS u
        JOIN _forum_migration_test_ctx AS c ON c.user_id = u.id
    ),
    'after deleting all replies user count still includes opened thread'
);


-- =========================================================
-- 19. Statement-level bulk reply delete
-- Reinsert two replies, then delete both in one DELETE statement.
-- =========================================================

INSERT INTO replies (thread_id, user_id, post, created_at)
SELECT thread_a, user_id, 'Bulk reply 1', TIMESTAMPTZ '2099-01-01 03:00:00+00'
FROM _forum_migration_test_ctx;

INSERT INTO replies (thread_id, user_id, post, created_at)
SELECT thread_a, user_id, 'Bulk reply 2', TIMESTAMPTZ '2099-01-01 04:00:00+00'
FROM _forum_migration_test_ctx;

SELECT pg_temp.assert_true(
    (
        SELECT u.replies_count = c.baseline_user_count + 3
        FROM neon_auth."user" AS u
        JOIN _forum_migration_test_ctx AS c ON c.user_id = u.id
    ),
    'two reinserted replies are included in user count'
);

DELETE FROM replies
WHERE thread_id = (SELECT thread_a FROM _forum_migration_test_ctx);

SELECT pg_temp.assert_true(
    (
        SELECT
            t.messages_count = 0
            AND t.last_post_date = t.created_at
        FROM threads AS t
        JOIN _forum_migration_test_ctx AS c ON c.thread_a = t.id
    ),
    'bulk reply delete recalculates thread exactly once to zero replies'
);

SELECT pg_temp.assert_true(
    (
        SELECT u.replies_count = c.baseline_user_count + 1
        FROM neon_auth."user" AS u
        JOIN _forum_migration_test_ctx AS c ON c.user_id = u.id
    ),
    'bulk reply delete decrements user count by number of deleted replies'
);


-- =========================================================
-- 20. Prepare Thread A for cascade-delete test: add two replies.
-- =========================================================

INSERT INTO replies (thread_id, user_id, post, created_at)
SELECT thread_a, user_id, 'Cascade reply A1', TIMESTAMPTZ '2099-01-01 05:00:00+00'
FROM _forum_migration_test_ctx;

INSERT INTO replies (thread_id, user_id, post, created_at)
SELECT thread_a, user_id, 'Cascade reply A2', TIMESTAMPTZ '2099-01-01 06:00:00+00'
FROM _forum_migration_test_ctx;


-- =========================================================
-- 21. Create newer Thread B.
-- =========================================================

WITH inserted AS (
    INSERT INTO threads (
        forum_id,
        user_id,
        title,
        content,
        created_at
    )
    SELECT
        c.forum_id,
        c.user_id,
        'Thread B',
        'Thread B body',
        TIMESTAMPTZ '2099-01-02 00:00:00+00'
    FROM _forum_migration_test_ctx AS c
    RETURNING id
)
UPDATE _forum_migration_test_ctx AS c
SET thread_b = inserted.id
FROM inserted;

SELECT pg_temp.assert_true(
    (
        SELECT
            f.messages_count = 4
            AND f.last_post_thread_id = c.thread_b
            AND f.last_post_title = 'Thread B'
        FROM forums AS f
        JOIN _forum_migration_test_ctx AS c ON c.forum_id = f.id
    ),
    'newer thread becomes forum last post while total includes both threads and two replies'
);

SELECT pg_temp.assert_true(
    (
        SELECT u.replies_count = c.baseline_user_count + 4
        FROM neon_auth."user" AS u
        JOIN _forum_migration_test_ctx AS c ON c.user_id = u.id
    ),
    'user count includes Thread A + two replies + Thread B'
);


-- =========================================================
-- 22. Title update on NON-latest thread
-- Thread title must sync locally, but forum title must remain Thread B.
-- =========================================================

UPDATE threads
SET title = 'Thread A renamed again'
WHERE id = (SELECT thread_a FROM _forum_migration_test_ctx);

SELECT pg_temp.assert_true(
    (
        SELECT t.last_post_title = 'Thread A renamed again'
        FROM threads AS t
        JOIN _forum_migration_test_ctx AS c ON c.thread_a = t.id
    ),
    'non-latest thread title still synchronizes thread.last_post_title'
);

SELECT pg_temp.assert_true(
    (
        SELECT
            f.last_post_thread_id = c.thread_b
            AND f.last_post_title = 'Thread B'
        FROM forums AS f
        JOIN _forum_migration_test_ctx AS c ON c.forum_id = f.id
    ),
    'renaming non-latest thread does not overwrite forum last-post title'
);


-- =========================================================
-- 23. forum_after_thread_delete()
-- Delete Thread A. Its two replies cascade-delete first/alongside it.
-- User count must lose 3 messages total: 1 thread + 2 replies.
-- =========================================================

DELETE FROM threads
WHERE id = (SELECT thread_a FROM _forum_migration_test_ctx);

SELECT pg_temp.assert_true(
    NOT EXISTS (
        SELECT 1
        FROM threads AS t
        JOIN _forum_migration_test_ctx AS c ON c.thread_a = t.id
    ),
    'Thread A is deleted'
);

SELECT pg_temp.assert_true(
    (
        SELECT
            f.messages_count = 1
            AND f.last_post_thread_id = c.thread_b
            AND f.last_post_title = 'Thread B'
        FROM forums AS f
        JOIN _forum_migration_test_ctx AS c ON c.forum_id = f.id
    ),
    'thread delete recalculates surviving forum totals and latest thread'
);

SELECT pg_temp.assert_true(
    (
        SELECT u.replies_count = c.baseline_user_count + 1
        FROM neon_auth."user" AS u
        JOIN _forum_migration_test_ctx AS c ON c.user_id = u.id
    ),
    'deleting a thread with two replies subtracts thread + both replies from user count'
);


-- =========================================================
-- 24. Delete final thread in forum
-- Forum aggregates must reset completely.
-- =========================================================

DELETE FROM threads
WHERE id = (SELECT thread_b FROM _forum_migration_test_ctx);

SELECT pg_temp.assert_true(
    (
        SELECT
            f.messages_count = 0
            AND f.last_post_thread_id IS NULL
            AND f.last_post_title = ''
            AND f.last_post_author_id IS NULL
            AND f.last_post_date IS NULL
        FROM forums AS f
        JOIN _forum_migration_test_ctx AS c ON c.forum_id = f.id
    ),
    'deleting final thread resets forum aggregate/last-post fields'
);

SELECT pg_temp.assert_true(
    (
        SELECT u.replies_count = c.baseline_user_count
        FROM neon_auth."user" AS u
        JOIN _forum_migration_test_ctx AS c ON c.user_id = u.id
    ),
    'deleting final thread returns user count to original baseline'
);


-- =========================================================
-- 25. Full forum ON DELETE CASCADE test
-- Create a second forum with two threads and two replies, then delete forum.
-- This exercises the delete triggers while the parent forum is already gone.
-- =========================================================

WITH inserted AS (
    INSERT INTO forums (sort_order, name, description)
    VALUES (900002, '__forum_migration_cascade_test__', 'cascade test')
    RETURNING id
)
UPDATE _forum_migration_test_ctx AS c
SET cascade_forum_id = inserted.id
FROM inserted;

WITH inserted AS (
    INSERT INTO threads (forum_id, user_id, title, content, created_at)
    SELECT
        c.cascade_forum_id,
        c.user_id,
        'Cascade Thread 1',
        'body',
        TIMESTAMPTZ '2099-02-01 00:00:00+00'
    FROM _forum_migration_test_ctx AS c
    RETURNING id
)
UPDATE _forum_migration_test_ctx AS c
SET cascade_thread_1 = inserted.id
FROM inserted;

WITH inserted AS (
    INSERT INTO threads (forum_id, user_id, title, content, created_at)
    SELECT
        c.cascade_forum_id,
        c.user_id,
        'Cascade Thread 2',
        'body',
        TIMESTAMPTZ '2099-02-02 00:00:00+00'
    FROM _forum_migration_test_ctx AS c
    RETURNING id
)
UPDATE _forum_migration_test_ctx AS c
SET cascade_thread_2 = inserted.id
FROM inserted;

WITH inserted AS (
    INSERT INTO replies (thread_id, user_id, post, created_at)
    SELECT
        c.cascade_thread_1,
        c.user_id,
        'Cascade reply 1',
        TIMESTAMPTZ '2099-02-01 01:00:00+00'
    FROM _forum_migration_test_ctx AS c
    RETURNING id
)
UPDATE _forum_migration_test_ctx AS c
SET cascade_reply_1 = inserted.id
FROM inserted;

WITH inserted AS (
    INSERT INTO replies (thread_id, user_id, post, created_at)
    SELECT
        c.cascade_thread_2,
        c.user_id,
        'Cascade reply 2',
        TIMESTAMPTZ '2099-02-02 01:00:00+00'
    FROM _forum_migration_test_ctx AS c
    RETURNING id
)
UPDATE _forum_migration_test_ctx AS c
SET cascade_reply_2 = inserted.id
FROM inserted;

SELECT pg_temp.assert_true(
    (
        SELECT u.replies_count = c.baseline_user_count + 4
        FROM neon_auth."user" AS u
        JOIN _forum_migration_test_ctx AS c ON c.user_id = u.id
    ),
    'cascade fixture adds two opened threads plus two replies to user count'
);

DELETE FROM forums
WHERE id = (SELECT cascade_forum_id FROM _forum_migration_test_ctx);

SELECT pg_temp.assert_true(
    NOT EXISTS (
        SELECT 1
        FROM forums AS f
        JOIN _forum_migration_test_ctx AS c ON c.cascade_forum_id = f.id
    ),
    'forum cascade fixture forum is deleted'
);

SELECT pg_temp.assert_true(
    NOT EXISTS (
        SELECT 1
        FROM threads AS t
        JOIN _forum_migration_test_ctx AS c
          ON t.id IN (c.cascade_thread_1, c.cascade_thread_2)
    ),
    'forum delete cascades to both threads'
);

SELECT pg_temp.assert_true(
    NOT EXISTS (
        SELECT 1
        FROM replies AS r
        JOIN _forum_migration_test_ctx AS c
          ON r.id IN (c.cascade_reply_1, c.cascade_reply_2)
    ),
    'forum delete cascades through threads to replies'
);

SELECT pg_temp.assert_true(
    (
        SELECT u.replies_count = c.baseline_user_count
        FROM neon_auth."user" AS u
        JOIN _forum_migration_test_ctx AS c ON c.user_id = u.id
    ),
    'forum cascade delete returns user message count to baseline'
);


-- =========================================================
-- 26. FINAL CONSISTENCY CHECKS
-- Main test forum still exists but is empty.
-- No test-created child rows remain.
-- User count is exactly back to baseline before rollback.
-- =========================================================

SELECT pg_temp.assert_true(
    (
        SELECT
            f.messages_count =
                (
                    SELECT COUNT(*)::BIGINT
                    FROM threads AS t
                    WHERE t.forum_id = f.id
                )
                +
                (
                    SELECT COUNT(*)::BIGINT
                    FROM replies AS r
                    JOIN threads AS t ON t.id = r.thread_id
                    WHERE t.forum_id = f.id
                )
        FROM forums AS f
        JOIN _forum_migration_test_ctx AS c ON c.forum_id = f.id
    ),
    'forum.messages_count equals threads + replies at end of test'
);

SELECT pg_temp.assert_true(
    (
        SELECT u.replies_count = c.baseline_user_count
        FROM neon_auth."user" AS u
        JOIN _forum_migration_test_ctx AS c ON c.user_id = u.id
    ),
    'final user replies_count exactly matches original baseline'
);

DO $$
BEGIN
    RAISE NOTICE '=========================================================';
    RAISE NOTICE 'ALL FORUM MIGRATION TESTS PASSED';
    RAISE NOTICE 'Transaction will now be rolled back; database unchanged.';
    RAISE NOTICE '=========================================================';
END;
$$;

ROLLBACK;
