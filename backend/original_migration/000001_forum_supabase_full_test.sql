-- Comprehensive test suite for 000001_forum_supabase.up.sql
-- Run AFTER the UP migration has been applied to a local Supabase database.
-- Intended for psql / Supabase local development.
--
-- Example:
--   supabase db reset
--   psql "$DATABASE_URL" -f 000001_forum_supabase_full_test.sql
--
-- Everything in this file is wrapped in a transaction and rolled back.

\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.assert_true(p_condition boolean, p_message text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    IF COALESCE(p_condition, FALSE) IS NOT TRUE THEN
        RAISE EXCEPTION 'FAIL: %', p_message;
    END IF;

    RAISE NOTICE 'PASS: %', p_message;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.expect_error(
    p_sql text,
    p_expected_message text,
    p_message text
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_error text;
BEGIN
    BEGIN
        EXECUTE p_sql;
    EXCEPTION
        WHEN OTHERS THEN
            v_error := SQLERRM;

            IF position(p_expected_message IN v_error) = 0 THEN
                RAISE EXCEPTION
                    'FAIL: % -- expected error containing %, got: %',
                    p_message,
                    quote_literal(p_expected_message),
                    v_error;
            END IF;

            RAISE NOTICE 'PASS: %', p_message;
            RETURN;
    END;

    RAISE EXCEPTION 'FAIL: % -- statement unexpectedly succeeded', p_message;
END;
$$;

-- =========================================================
-- 1. OBJECT EXISTENCE
-- =========================================================

DO $$
DECLARE
    v_count integer;
BEGIN
    SELECT COUNT(*)
    INTO v_count
    FROM pg_proc AS p
    JOIN pg_namespace AS n
      ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = ANY (ARRAY[
          'forum_create_user_stats',
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
      ]);

    PERFORM pg_temp.assert_true(
        v_count = 15,
        format('all 15 migration functions exist (found %s)', v_count)
    );
END;
$$;

DO $$
DECLARE
    v_missing integer;
BEGIN
    WITH expected(schema_name, table_name, trigger_name) AS (
        VALUES
            ('auth',   'users',            'forum_auth_user_created'),
            ('public', 'forums',           'forums_prepare_insert'),
            ('public', 'forums',           'forums_set_updated_at'),
            ('public', 'threads',          'threads_set_updated_at'),
            ('public', 'replies',          'replies_set_updated_at'),
            ('public', 'threads',          'threads_prepare_insert'),
            ('public', 'threads',          'threads_prevent_relation_changes'),
            ('public', 'replies',          'replies_prevent_relation_changes'),
            ('public', 'replies',          'replies_validate_insert'),
            ('public', 'forums',           'forums_guard_denormalized_update'),
            ('public', 'threads',          'threads_guard_denormalized_update'),
            ('public', 'threads',          'threads_after_insert'),
            ('public', 'threads',          'threads_sync_title'),
            ('public', 'threads',          'threads_after_title_update'),
            ('public', 'replies',          'replies_after_insert'),
            ('public', 'replies',          'replies_after_delete'),
            ('public', 'threads',          'threads_after_delete')
    )
    SELECT COUNT(*)
    INTO v_missing
    FROM expected AS e
    LEFT JOIN pg_namespace AS n
      ON n.nspname = e.schema_name
    LEFT JOIN pg_class AS c
      ON c.relnamespace = n.oid
     AND c.relname = e.table_name
    LEFT JOIN pg_trigger AS t
      ON t.tgrelid = c.oid
     AND t.tgname = e.trigger_name
     AND NOT t.tgisinternal
    WHERE t.oid IS NULL;

    PERFORM pg_temp.assert_true(
        v_missing = 0,
        format('all 17 migration triggers exist (missing %s)', v_missing)
    );
END;
$$;

DO $$
DECLARE
    v_missing integer;
BEGIN
    WITH expected(index_name) AS (
        VALUES
            ('idx_forums_last_post_thread_id'),
            ('idx_threads_forum_id'),
            ('idx_threads_user_id'),
            ('idx_threads_created_at'),
            ('idx_threads_last_post_date'),
            ('idx_threads_forum_last_post_date'),
            ('idx_threads_forum_sticky_last_post'),
            ('idx_threads_notify'),
            ('idx_replies_thread_id'),
            ('idx_replies_user_id'),
            ('idx_replies_created_at'),
            ('idx_replies_thread_created_at')
    )
    SELECT COUNT(*)
    INTO v_missing
    FROM expected AS e
    WHERE NOT EXISTS (
        SELECT 1
        FROM pg_class AS c
        JOIN pg_namespace AS n
          ON n.oid = c.relnamespace
        WHERE n.nspname = 'public'
          AND c.relname = e.index_name
          AND c.relkind = 'i'
    );

    PERFORM pg_temp.assert_true(
        v_missing = 0,
        format('all 12 migration indexes exist (missing %s)', v_missing)
    );
END;
$$;

-- =========================================================
-- 2. FUNCTION / TRIGGER BEHAVIOR
-- =========================================================

DO $$
DECLARE
    v_user1 uuid := gen_random_uuid();
    v_user2 uuid := gen_random_uuid();
    v_user3 uuid := gen_random_uuid();
    v_user4 uuid := gen_random_uuid();

    v_forum1 bigint;
    v_forum2 bigint;
    v_forum3 bigint;

    v_thread1 bigint;
    v_thread2 bigint;

    v_reply1 uuid;
    v_reply2 uuid;
    v_reply3 uuid;
    v_reply4 uuid;
    v_reply5 uuid;

    v_count bigint;
    v_text text;
    v_uuid uuid;
    v_time timestamptz;
BEGIN
    -- -----------------------------------------------------
    -- forum_create_user_stats()
    -- -----------------------------------------------------

    INSERT INTO auth.users (
        id,
        aud,
        role,
        email,
        encrypted_password,
        raw_app_meta_data,
        raw_user_meta_data,
        created_at,
        updated_at
    )
    VALUES
        (
            v_user1,
            'authenticated',
            'authenticated',
            'forum-test-' || v_user1::text || '@example.invalid',
            '',
            '{"provider":"email","providers":["email"]}'::jsonb,
            '{}'::jsonb,
            clock_timestamp(),
            clock_timestamp()
        ),
        (
            v_user2,
            'authenticated',
            'authenticated',
            'forum-test-' || v_user2::text || '@example.invalid',
            '',
            '{"provider":"email","providers":["email"]}'::jsonb,
            '{}'::jsonb,
            clock_timestamp(),
            clock_timestamp()
        ),
        (
            v_user3,
            'authenticated',
            'authenticated',
            'forum-test-' || v_user3::text || '@example.invalid',
            '',
            '{"provider":"email","providers":["email"]}'::jsonb,
            '{}'::jsonb,
            clock_timestamp(),
            clock_timestamp()
        ),
        (
            v_user4,
            'authenticated',
            'authenticated',
            'forum-test-' || v_user4::text || '@example.invalid',
            '',
            '{"provider":"email","providers":["email"]}'::jsonb,
            '{}'::jsonb,
            clock_timestamp(),
            clock_timestamp()
        );

    SELECT COUNT(*)
    INTO v_count
    FROM public.forum_user_stats
    WHERE user_id IN (v_user1, v_user2, v_user3, v_user4)
      AND replies_count = 0;

    PERFORM pg_temp.assert_true(
        v_count = 4,
        'forum_create_user_stats creates zeroed stats rows for new auth users'
    );

    -- -----------------------------------------------------
    -- forum_prepare_forum_insert()
    -- forum_set_updated_at() on forums
    -- -----------------------------------------------------

    INSERT INTO public.forums (
        sort_order,
        name,
        description,
        messages_count,
        last_post_thread_id,
        last_post_title,
        last_post_author_id,
        last_post_date,
        updated_at
    )
    VALUES (
        1,
        'Test Forum 1',
        'first forum',
        999,
        987654321,
        'must be cleared',
        v_user1,
        '2030-01-01 00:00:00+00',
        '2000-01-01 00:00:00+00'
    )
    RETURNING id
    INTO v_forum1;

    SELECT messages_count
    INTO v_count
    FROM public.forums
    WHERE id = v_forum1;

    PERFORM pg_temp.assert_true(
        v_count = 0,
        'forum_prepare_forum_insert forces messages_count to zero'
    );

    SELECT last_post_title
    INTO v_text
    FROM public.forums
    WHERE id = v_forum1;

    PERFORM pg_temp.assert_true(
        v_text = '',
        'forum_prepare_forum_insert clears last_post_title'
    );

    SELECT last_post_author_id
    INTO v_uuid
    FROM public.forums
    WHERE id = v_forum1;

    PERFORM pg_temp.assert_true(
        v_uuid IS NULL,
        'forum_prepare_forum_insert clears last_post_author_id'
    );

    SELECT last_post_date
    INTO v_time
    FROM public.forums
    WHERE id = v_forum1;

    PERFORM pg_temp.assert_true(
        v_time IS NULL,
        'forum_prepare_forum_insert clears last_post_date'
    );

    PERFORM pg_temp.assert_true(
        (SELECT last_post_thread_id IS NULL FROM public.forums WHERE id = v_forum1),
        'forum_prepare_forum_insert clears last_post_thread_id before FK validation'
    );

    UPDATE public.forums
    SET description = 'updated description'
    WHERE id = v_forum1;

    SELECT updated_at
    INTO v_time
    FROM public.forums
    WHERE id = v_forum1;

    PERFORM pg_temp.assert_true(
        v_time > '2000-01-01 00:00:00+00'::timestamptz,
        'forum_set_updated_at refreshes forums.updated_at'
    );

    INSERT INTO public.forums (sort_order, name, description)
    VALUES (2, 'Test Forum 2', 'second forum')
    RETURNING id
    INTO v_forum2;

    INSERT INTO public.forums (sort_order, name, description)
    VALUES (3, 'Test Forum 3', 'user deletion forum')
    RETURNING id
    INTO v_forum3;

    -- -----------------------------------------------------
    -- forum_guard_forum_denormalized_update()
    -- -----------------------------------------------------

    PERFORM pg_temp.expect_error(
        format(
            'UPDATE public.forums SET messages_count = messages_count + 1 WHERE id = %s',
            v_forum1
        ),
        'forum message/last-post fields are trigger-maintained',
        'forum_guard_forum_denormalized_update rejects direct messages_count changes'
    );

    -- -----------------------------------------------------
    -- forum_prepare_thread_insert()
    -- forum_after_thread_insert()
    -- -----------------------------------------------------

    PERFORM pg_temp.expect_error(
        format(
            $sql$INSERT INTO public.threads (forum_id, user_id, title, content)
                 VALUES (%s, NULL, 'bad thread', 'body')$sql$,
            v_forum1
        ),
        'new thread user_id cannot be NULL',
        'forum_prepare_thread_insert rejects a NULL thread author'
    );

    INSERT INTO public.threads (
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
    VALUES (
        v_forum1,
        v_user1,
        'Thread One',
        'opening post',
        99,
        'wrong title',
        v_user2,
        '2035-01-01 00:00:00+00',
        '2026-01-01 10:00:00+00',
        '2000-01-01 00:00:00+00'
    )
    RETURNING id
    INTO v_thread1;

    PERFORM pg_temp.assert_true(
        (SELECT messages_count = 0 FROM public.threads WHERE id = v_thread1),
        'forum_prepare_thread_insert forces thread messages_count to zero'
    );

    PERFORM pg_temp.assert_true(
        (SELECT last_post_title = 'Thread One' FROM public.threads WHERE id = v_thread1),
        'forum_prepare_thread_insert initializes thread last_post_title'
    );

    PERFORM pg_temp.assert_true(
        (SELECT last_post_author_id = v_user1 FROM public.threads WHERE id = v_thread1),
        'forum_prepare_thread_insert initializes thread last_post_author_id'
    );

    PERFORM pg_temp.assert_true(
        (
            SELECT last_post_date = '2026-01-01 10:00:00+00'::timestamptz
            FROM public.threads
            WHERE id = v_thread1
        ),
        'forum_prepare_thread_insert initializes thread last_post_date from created_at'
    );

    PERFORM pg_temp.assert_true(
        (SELECT messages_count = 1 FROM public.forums WHERE id = v_forum1),
        'forum_after_thread_insert increments forum message count'
    );

    PERFORM pg_temp.assert_true(
        (
            SELECT last_post_thread_id = v_thread1
               AND last_post_title = 'Thread One'
               AND last_post_author_id = v_user1
               AND last_post_date = '2026-01-01 10:00:00+00'::timestamptz
            FROM public.forums
            WHERE id = v_forum1
        ),
        'forum_after_thread_insert sets forum last-post metadata'
    );

    PERFORM pg_temp.assert_true(
        (SELECT replies_count = 1 FROM public.forum_user_stats WHERE user_id = v_user1),
        'forum_after_thread_insert increments opening author message count'
    );

    -- -----------------------------------------------------
    -- forum_set_updated_at() on threads
    -- forum_guard_thread_denormalized_update()
    -- forum_prevent_thread_relation_changes()
    -- -----------------------------------------------------

    UPDATE public.threads
    SET content = 'opening post edited'
    WHERE id = v_thread1;

    PERFORM pg_temp.assert_true(
        (
            SELECT updated_at > '2000-01-01 00:00:00+00'::timestamptz
            FROM public.threads
            WHERE id = v_thread1
        ),
        'forum_set_updated_at refreshes threads.updated_at'
    );

    PERFORM pg_temp.expect_error(
        format(
            'UPDATE public.threads SET messages_count = messages_count + 1 WHERE id = %s',
            v_thread1
        ),
        'thread message/last-post fields are trigger-maintained',
        'forum_guard_thread_denormalized_update rejects direct messages_count changes'
    );

    PERFORM pg_temp.expect_error(
        format(
            'UPDATE public.threads SET forum_id = %s WHERE id = %s',
            v_forum2,
            v_thread1
        ),
        'thread forum_id cannot be changed',
        'forum_prevent_thread_relation_changes blocks forum_id changes'
    );

    PERFORM pg_temp.expect_error(
        format(
            'UPDATE public.threads SET user_id = %L::uuid WHERE id = %s',
            v_user2::text,
            v_thread1
        ),
        'thread user_id cannot be changed',
        'forum_prevent_thread_relation_changes blocks non-NULL user_id changes'
    );

    PERFORM pg_temp.expect_error(
        format(
            $sql$UPDATE public.threads
                 SET created_at = created_at + interval '1 second'
                 WHERE id = %s$sql$,
            v_thread1
        ),
        'thread created_at cannot be changed',
        'forum_prevent_thread_relation_changes blocks created_at changes'
    );

    -- -----------------------------------------------------
    -- forum_sync_thread_title()
    -- forum_after_thread_title_update()
    -- -----------------------------------------------------

    UPDATE public.threads
    SET title = 'Thread One Renamed'
    WHERE id = v_thread1;

    PERFORM pg_temp.assert_true(
        (SELECT last_post_title = 'Thread One Renamed' FROM public.threads WHERE id = v_thread1),
        'forum_sync_thread_title keeps thread last_post_title synchronized'
    );

    PERFORM pg_temp.assert_true(
        (SELECT last_post_title = 'Thread One Renamed' FROM public.forums WHERE id = v_forum1),
        'forum_after_thread_title_update synchronizes the latest forum title'
    );

    -- -----------------------------------------------------
    -- forum_validate_reply_insert()
    -- forum_after_reply_insert()
    -- -----------------------------------------------------

    PERFORM pg_temp.expect_error(
        format(
            $sql$INSERT INTO public.replies (thread_id, user_id, post)
                 VALUES (%s, NULL, 'bad reply')$sql$,
            v_thread1
        ),
        'new reply user_id cannot be NULL',
        'forum_validate_reply_insert rejects a NULL reply author'
    );

    INSERT INTO public.replies (
        thread_id,
        user_id,
        post,
        created_at,
        updated_at
    )
    VALUES (
        v_thread1,
        v_user2,
        'reply one',
        '2026-01-01 11:00:00+00',
        '2000-01-01 00:00:00+00'
    )
    RETURNING id
    INTO v_reply1;

    PERFORM pg_temp.assert_true(
        (
            SELECT messages_count = 1
               AND last_post_author_id = v_user2
               AND last_post_date = '2026-01-01 11:00:00+00'::timestamptz
            FROM public.threads
            WHERE id = v_thread1
        ),
        'forum_after_reply_insert updates thread reply count and latest author/date'
    );

    PERFORM pg_temp.assert_true(
        (
            SELECT messages_count = 2
               AND last_post_thread_id = v_thread1
               AND last_post_author_id = v_user2
               AND last_post_date = '2026-01-01 11:00:00+00'::timestamptz
            FROM public.forums
            WHERE id = v_forum1
        ),
        'forum_after_reply_insert updates forum count and latest activity'
    );

    PERFORM pg_temp.assert_true(
        (SELECT replies_count = 1 FROM public.forum_user_stats WHERE user_id = v_user2),
        'forum_after_reply_insert increments reply author message count'
    );

    INSERT INTO public.replies (
        thread_id,
        user_id,
        post,
        created_at
    )
    VALUES (
        v_thread1,
        v_user1,
        'reply two',
        '2026-01-01 12:00:00+00'
    )
    RETURNING id
    INTO v_reply2;

    PERFORM pg_temp.assert_true(
        (SELECT messages_count = 2 FROM public.threads WHERE id = v_thread1),
        'second reply increments thread reply count again'
    );

    PERFORM pg_temp.assert_true(
        (SELECT messages_count = 3 FROM public.forums WHERE id = v_forum1),
        'second reply increments forum total messages again'
    );

    PERFORM pg_temp.assert_true(
        (SELECT replies_count = 2 FROM public.forum_user_stats WHERE user_id = v_user1),
        'user message count includes opened thread plus authored reply'
    );

    -- -----------------------------------------------------
    -- forum_set_updated_at() on replies
    -- forum_prevent_reply_relation_changes()
    -- -----------------------------------------------------

    UPDATE public.replies
    SET post = 'reply one edited'
    WHERE id = v_reply1;

    PERFORM pg_temp.assert_true(
        (
            SELECT updated_at > '2000-01-01 00:00:00+00'::timestamptz
            FROM public.replies
            WHERE id = v_reply1
        ),
        'forum_set_updated_at refreshes replies.updated_at'
    );

    PERFORM pg_temp.expect_error(
        format(
            'UPDATE public.replies SET thread_id = 999999999 WHERE id = %L::uuid',
            v_reply1::text
        ),
        'reply thread_id cannot be changed',
        'forum_prevent_reply_relation_changes blocks thread_id changes'
    );

    PERFORM pg_temp.expect_error(
        format(
            'UPDATE public.replies SET user_id = %L::uuid WHERE id = %L::uuid',
            v_user1::text,
            v_reply1::text
        ),
        'reply user_id cannot be changed',
        'forum_prevent_reply_relation_changes blocks non-NULL user_id changes'
    );

    PERFORM pg_temp.expect_error(
        format(
            $sql$UPDATE public.replies
                 SET created_at = created_at + interval '1 second'
                 WHERE id = %L::uuid$sql$,
            v_reply1::text
        ),
        'reply created_at cannot be changed',
        'forum_prevent_reply_relation_changes blocks created_at changes'
    );

    -- -----------------------------------------------------
    -- forum_after_reply_delete()
    -- Delete latest reply: previous reply becomes latest.
    -- -----------------------------------------------------

    DELETE FROM public.replies
    WHERE id = v_reply2;

    PERFORM pg_temp.assert_true(
        (
            SELECT messages_count = 1
               AND last_post_author_id = v_user2
               AND last_post_date = '2026-01-01 11:00:00+00'::timestamptz
            FROM public.threads
            WHERE id = v_thread1
        ),
        'forum_after_reply_delete restores previous reply as thread latest post'
    );

    PERFORM pg_temp.assert_true(
        (
            SELECT messages_count = 2
               AND last_post_thread_id = v_thread1
               AND last_post_author_id = v_user2
               AND last_post_date = '2026-01-01 11:00:00+00'::timestamptz
            FROM public.forums
            WHERE id = v_forum1
        ),
        'forum_after_reply_delete recalculates forum count and latest post'
    );

    PERFORM pg_temp.assert_true(
        (SELECT replies_count = 1 FROM public.forum_user_stats WHERE user_id = v_user1),
        'forum_after_reply_delete decrements deleted reply author count'
    );

    -- Delete the final reply: opening thread becomes latest again.
    DELETE FROM public.replies
    WHERE id = v_reply1;

    PERFORM pg_temp.assert_true(
        (
            SELECT messages_count = 0
               AND last_post_author_id = v_user1
               AND last_post_date = '2026-01-01 10:00:00+00'::timestamptz
            FROM public.threads
            WHERE id = v_thread1
        ),
        'forum_after_reply_delete falls back to opening post when no replies remain'
    );

    PERFORM pg_temp.assert_true(
        (SELECT messages_count = 1 FROM public.forums WHERE id = v_forum1),
        'forum_after_reply_delete leaves only the opening thread in forum count'
    );

    PERFORM pg_temp.assert_true(
        (SELECT replies_count = 0 FROM public.forum_user_stats WHERE user_id = v_user2),
        'deleting the final user2 reply returns its message count to zero'
    );

    -- Statement-level delete with more than one reply.
    INSERT INTO public.replies (thread_id, user_id, post, created_at)
    VALUES
        (v_thread1, v_user2, 'batch reply 1', '2026-01-01 13:00:00+00'),
        (v_thread1, v_user2, 'batch reply 2', '2026-01-01 14:00:00+00');

    -- Capture the two rows deterministically after insertion.
    SELECT id
    INTO v_reply3
    FROM public.replies
    WHERE thread_id = v_thread1
      AND post = 'batch reply 1';

    SELECT id
    INTO v_reply4
    FROM public.replies
    WHERE thread_id = v_thread1
      AND post = 'batch reply 2';

    PERFORM pg_temp.assert_true(
        (SELECT replies_count = 2 FROM public.forum_user_stats WHERE user_id = v_user2),
        'two inserted replies increment user count twice'
    );

    DELETE FROM public.replies
    WHERE id IN (v_reply3, v_reply4);

    PERFORM pg_temp.assert_true(
        (SELECT messages_count = 0 FROM public.threads WHERE id = v_thread1),
        'statement-level reply delete recalculates thread once after deleting multiple replies'
    );

    PERFORM pg_temp.assert_true(
        (SELECT messages_count = 1 FROM public.forums WHERE id = v_forum1),
        'statement-level reply delete recalculates forum once after deleting multiple replies'
    );

    PERFORM pg_temp.assert_true(
        (SELECT replies_count = 0 FROM public.forum_user_stats WHERE user_id = v_user2),
        'statement-level reply delete decrements user count by all deleted replies'
    );

    -- -----------------------------------------------------
    -- forum_after_thread_delete()
    -- Include cascading reply deletes.
    -- -----------------------------------------------------

    INSERT INTO public.replies (thread_id, user_id, post, created_at)
    VALUES
        (v_thread1, v_user2, 'cascade reply 1', '2026-01-01 15:00:00+00'),
        (v_thread1, v_user2, 'cascade reply 2', '2026-01-01 16:00:00+00');

    PERFORM pg_temp.assert_true(
        (SELECT messages_count = 3 FROM public.forums WHERE id = v_forum1),
        'forum contains one thread plus two replies before thread deletion'
    );

    PERFORM pg_temp.assert_true(
        (SELECT replies_count = 1 FROM public.forum_user_stats WHERE user_id = v_user1),
        'thread author count is one before deleting thread'
    );

    PERFORM pg_temp.assert_true(
        (SELECT replies_count = 2 FROM public.forum_user_stats WHERE user_id = v_user2),
        'reply author count is two before cascading thread deletion'
    );

    DELETE FROM public.threads
    WHERE id = v_thread1;

    PERFORM pg_temp.assert_true(
        (
            SELECT messages_count = 0
               AND last_post_thread_id IS NULL
               AND last_post_title = ''
               AND last_post_author_id IS NULL
               AND last_post_date IS NULL
            FROM public.forums
            WHERE id = v_forum1
        ),
        'forum_after_thread_delete clears empty-forum aggregate and last-post state'
    );

    PERFORM pg_temp.assert_true(
        (SELECT replies_count = 0 FROM public.forum_user_stats WHERE user_id = v_user1),
        'forum_after_thread_delete decrements deleted opening-thread author count'
    );

    PERFORM pg_temp.assert_true(
        (SELECT replies_count = 0 FROM public.forum_user_stats WHERE user_id = v_user2),
        'cascading reply deletes decrement reply author count before thread delete completes'
    );

    -- -----------------------------------------------------
    -- Supabase auth.users ON DELETE behavior.
    -- Exercises permitted SET NULL paths through relation/guard triggers.
    -- -----------------------------------------------------

    INSERT INTO public.threads (
        forum_id,
        user_id,
        title,
        content,
        created_at
    )
    VALUES (
        v_forum3,
        v_user4,
        'History survives user deletion',
        'opening body',
        '2026-02-01 10:00:00+00'
    )
    RETURNING id
    INTO v_thread2;

    INSERT INTO public.replies (
        thread_id,
        user_id,
        post,
        created_at
    )
    VALUES (
        v_thread2,
        v_user3,
        'reply by user who will be deleted',
        '2026-02-01 11:00:00+00'
    )
    RETURNING id
    INTO v_reply5;

    DELETE FROM auth.users
    WHERE id = v_user3;

    PERFORM pg_temp.assert_true(
        (SELECT user_id IS NULL FROM public.replies WHERE id = v_reply5),
        'deleting an auth user preserves reply history and sets replies.user_id to NULL'
    );

    PERFORM pg_temp.assert_true(
        (SELECT last_post_author_id IS NULL FROM public.threads WHERE id = v_thread2),
        'deleting latest reply author sets thread last_post_author_id to NULL'
    );

    PERFORM pg_temp.assert_true(
        (SELECT last_post_author_id IS NULL FROM public.forums WHERE id = v_forum3),
        'deleting latest reply author sets forum last_post_author_id to NULL'
    );

    PERFORM pg_temp.assert_true(
        NOT EXISTS (
            SELECT 1
            FROM public.forum_user_stats
            WHERE user_id = v_user3
        ),
        'deleting an auth user cascades deletion of its forum_user_stats row'
    );

    DELETE FROM auth.users
    WHERE id = v_user4;

    PERFORM pg_temp.assert_true(
        (SELECT user_id IS NULL FROM public.threads WHERE id = v_thread2),
        'deleting opening author preserves thread history and sets threads.user_id to NULL'
    );

    PERFORM pg_temp.assert_true(
        EXISTS (
            SELECT 1
            FROM public.threads
            WHERE id = v_thread2
        ),
        'thread survives auth-user deletion'
    );

    PERFORM pg_temp.assert_true(
        EXISTS (
            SELECT 1
            FROM public.replies
            WHERE id = v_reply5
        ),
        'reply survives auth-user deletion'
    );

    PERFORM pg_temp.assert_true(
        NOT EXISTS (
            SELECT 1
            FROM public.forum_user_stats
            WHERE user_id = v_user4
        ),
        'opening author stats row is removed when auth user is deleted'
    );

    RAISE NOTICE '=========================================================';
    RAISE NOTICE 'ALL FORUM SUPABASE MIGRATION BEHAVIOR TESTS PASSED';
    RAISE NOTICE '=========================================================';
END;
$$;

ROLLBACK;
