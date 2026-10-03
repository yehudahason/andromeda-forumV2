-- Overall integration test for the forum schema/functions/triggers.
-- Run AFTER applying the forum UP migration.
--
-- The whole test runs inside one transaction and ends with ROLLBACK.
-- It requires at least two existing rows in neon_auth."user".
--
-- Recommended:
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f 000001_forum_overall_test.sql

BEGIN;

DO $test$
DECLARE
    v_user1 UUID;
    v_user2 UUID;

    v_user1_replies_before BIGINT;
    v_user2_replies_before BIGINT;

    v_forum_id BIGINT;
    v_forum2_id BIGINT;
    v_thread_a BIGINT;
    v_thread_b BIGINT;

    v_reply_b1 UUID;
    v_reply_a1 UUID;
    v_reply_a2 UUID;

    v_old_updated_at TIMESTAMPTZ;

    v_count BIGINT;
    v_thread_id BIGINT;
    v_title TEXT;
    v_author UUID;
    v_date TIMESTAMPTZ;
BEGIN
    ---------------------------------------------------------------------------
    -- PRECONDITIONS
    ---------------------------------------------------------------------------

    SELECT id, replies_count
    INTO v_user1, v_user1_replies_before
    FROM neon_auth."user"
    ORDER BY id
    LIMIT 1;

    IF v_user1 IS NULL THEN
        RAISE EXCEPTION 'TEST SETUP FAILED: neon_auth."user" has no users';
    END IF;

    SELECT id, replies_count
    INTO v_user2, v_user2_replies_before
    FROM neon_auth."user"
    WHERE id <> v_user1
    ORDER BY id
    LIMIT 1;

    IF v_user2 IS NULL THEN
        RAISE EXCEPTION 'TEST SETUP FAILED: at least two auth users are required';
    END IF;

    RAISE NOTICE 'Using test users % and %', v_user1, v_user2;

    ---------------------------------------------------------------------------
    -- 1. FORUM INSERT PREPARATION
    -- forum_prepare_forum_insert()
    -- forums_prepare_insert
    ---------------------------------------------------------------------------

    INSERT INTO forums (
        name,
        description,
        messages_count,
        last_post_title,
        last_post_author_id,
        last_post_date
    )
    VALUES (
        '__forum_trigger_test__',
        'temporary integration test forum',
        999,
        'must be reset',
        v_user1,
        TIMESTAMPTZ '2030-01-01 00:00:00+00'
    )
    RETURNING id INTO v_forum_id;

    SELECT
        messages_count,
        last_post_thread_id,
        last_post_title,
        last_post_author_id,
        last_post_date
    INTO
        v_count,
        v_thread_id,
        v_title,
        v_author,
        v_date
    FROM forums
    WHERE id = v_forum_id;

    IF v_count <> 0
       OR v_thread_id IS NOT NULL
       OR v_title <> ''
       OR v_author IS NOT NULL
       OR v_date IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL forum_prepare_forum_insert: aggregate state was not reset';
    END IF;

    RAISE NOTICE 'PASS forum_prepare_forum_insert';

    -- Second forum is used only for immutable-relation tests.
    INSERT INTO forums (name, description)
    VALUES ('__forum_trigger_test_2__', 'temporary relation target')
    RETURNING id INTO v_forum2_id;

    ---------------------------------------------------------------------------
    -- 2. FORUM updated_at
    -- forum_set_updated_at()
    -- forums_set_updated_at
    ---------------------------------------------------------------------------

    SELECT updated_at INTO v_old_updated_at
    FROM forums
    WHERE id = v_forum_id;

    PERFORM pg_sleep(0.01);

    UPDATE forums
    SET description = 'updated description'
    WHERE id = v_forum_id;

    IF (SELECT updated_at FROM forums WHERE id = v_forum_id) <= v_old_updated_at THEN
        RAISE EXCEPTION 'FAIL forums_set_updated_at';
    END IF;

    RAISE NOTICE 'PASS forums_set_updated_at';

    ---------------------------------------------------------------------------
    -- 3. THREAD INSERT VALIDATION/PREPARATION + AFTER INSERT
    -- forum_prepare_thread_insert()
    -- threads_prepare_insert
    -- forum_after_thread_insert()
    -- threads_after_insert
    ---------------------------------------------------------------------------

    BEGIN
        INSERT INTO threads (forum_id, user_id, title, content)
        VALUES (v_forum_id, NULL, 'invalid', 'invalid');

        RAISE EXCEPTION 'FAIL threads_prepare_insert: NULL user_id was accepted';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM = 'FAIL threads_prepare_insert: NULL user_id was accepted' THEN
                RAISE;
            END IF;
    END;

    INSERT INTO threads (
        forum_id,
        user_id,
        title,
        content,
        messages_count,
        last_post_title,
        last_post_author_id,
        last_post_date,
        created_at
    )
    VALUES (
        v_forum_id,
        v_user1,
        'Thread A',
        'Opening A',
        777,
        'bad title',
        v_user2,
        TIMESTAMPTZ '2030-01-01 00:00:00+00',
        TIMESTAMPTZ '2026-01-01 10:00:00+00'
    )
    RETURNING id INTO v_thread_a;

    SELECT messages_count, last_post_title, last_post_author_id, last_post_date
    INTO v_count, v_title, v_author, v_date
    FROM threads
    WHERE id = v_thread_a;

    IF v_count <> 0
       OR v_title <> 'Thread A'
       OR v_author IS DISTINCT FROM v_user1
       OR v_date IS DISTINCT FROM TIMESTAMPTZ '2026-01-01 10:00:00+00' THEN
        RAISE EXCEPTION 'FAIL threads_prepare_insert: initial thread state is wrong';
    END IF;

    SELECT messages_count, last_post_thread_id, last_post_title,
           last_post_author_id, last_post_date
    INTO v_count, v_thread_id, v_title, v_author, v_date
    FROM forums
    WHERE id = v_forum_id;

    IF v_count <> 1
       OR v_thread_id <> v_thread_a
       OR v_title <> 'Thread A'
       OR v_author IS DISTINCT FROM v_user1
       OR v_date IS DISTINCT FROM TIMESTAMPTZ '2026-01-01 10:00:00+00' THEN
        RAISE EXCEPTION 'FAIL threads_after_insert after Thread A';
    END IF;

    -- Older thread must increase the forum count but must not replace latest.
    INSERT INTO threads (
        forum_id, user_id, title, content, created_at
    )
    VALUES (
        v_forum_id,
        v_user2,
        'Thread B',
        'Opening B',
        TIMESTAMPTZ '2026-01-01 09:00:00+00'
    )
    RETURNING id INTO v_thread_b;

    SELECT messages_count, last_post_thread_id, last_post_title,
           last_post_author_id, last_post_date
    INTO v_count, v_thread_id, v_title, v_author, v_date
    FROM forums
    WHERE id = v_forum_id;

    IF v_count <> 2
       OR v_thread_id <> v_thread_a
       OR v_title <> 'Thread A'
       OR v_author IS DISTINCT FROM v_user1
       OR v_date IS DISTINCT FROM TIMESTAMPTZ '2026-01-01 10:00:00+00' THEN
        RAISE EXCEPTION 'FAIL threads_after_insert: older thread incorrectly became latest';
    END IF;

    RAISE NOTICE 'PASS thread prepare/insert triggers';

    ---------------------------------------------------------------------------
    -- 4. THREAD updated_at
    ---------------------------------------------------------------------------

    SELECT updated_at INTO v_old_updated_at
    FROM threads
    WHERE id = v_thread_a;

    PERFORM pg_sleep(0.01);

    UPDATE threads
    SET content = 'Opening A edited'
    WHERE id = v_thread_a;

    IF (SELECT updated_at FROM threads WHERE id = v_thread_a) <= v_old_updated_at THEN
        RAISE EXCEPTION 'FAIL threads_set_updated_at';
    END IF;

    RAISE NOTICE 'PASS threads_set_updated_at';

    ---------------------------------------------------------------------------
    -- 5. IMMUTABLE THREAD RELATION FIELDS
    -- forum_prevent_thread_relation_changes()
    ---------------------------------------------------------------------------

    BEGIN
        UPDATE threads
        SET forum_id = v_forum2_id
        WHERE id = v_thread_a;

        RAISE EXCEPTION 'FAIL threads_prevent_relation_changes: forum_id changed';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM = 'FAIL threads_prevent_relation_changes: forum_id changed' THEN
                RAISE;
            END IF;
    END;

    BEGIN
        UPDATE threads
        SET user_id = v_user2
        WHERE id = v_thread_a;

        RAISE EXCEPTION 'FAIL threads_prevent_relation_changes: user_id changed';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM = 'FAIL threads_prevent_relation_changes: user_id changed' THEN
                RAISE;
            END IF;
    END;

    BEGIN
        UPDATE threads
        SET created_at = TIMESTAMPTZ '2025-01-01 00:00:00+00'
        WHERE id = v_thread_a;

        RAISE EXCEPTION 'FAIL threads_prevent_relation_changes: created_at changed';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM = 'FAIL threads_prevent_relation_changes: created_at changed' THEN
                RAISE;
            END IF;
    END;

    RAISE NOTICE 'PASS thread immutable-field trigger';

    ---------------------------------------------------------------------------
    -- 6. DENORMALIZED FIELD GUARDS
    ---------------------------------------------------------------------------

    BEGIN
        UPDATE forums
        SET messages_count = 999
        WHERE id = v_forum_id;

        RAISE EXCEPTION 'FAIL forums_guard_denormalized_update: direct count write accepted';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM = 'FAIL forums_guard_denormalized_update: direct count write accepted' THEN
                RAISE;
            END IF;
    END;

    BEGIN
        UPDATE forums
        SET last_post_thread_id = v_thread_b
        WHERE id = v_forum_id;

        RAISE EXCEPTION 'FAIL forums_guard_denormalized_update: direct latest thread write accepted';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM = 'FAIL forums_guard_denormalized_update: direct latest thread write accepted' THEN
                RAISE;
            END IF;
    END;

    BEGIN
        UPDATE threads
        SET messages_count = 999
        WHERE id = v_thread_a;

        RAISE EXCEPTION 'FAIL threads_guard_denormalized_update: direct count write accepted';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM = 'FAIL threads_guard_denormalized_update: direct count write accepted' THEN
                RAISE;
            END IF;
    END;

    RAISE NOTICE 'PASS denormalized-field guards';

    ---------------------------------------------------------------------------
    -- 7. THREAD TITLE SYNCHRONIZATION
    -- forum_sync_thread_title()
    -- forum_after_thread_title_update()
    ---------------------------------------------------------------------------

    -- Rename non-latest thread B. Its own copy changes, forum title must not.
    UPDATE threads
    SET title = 'Thread B renamed'
    WHERE id = v_thread_b;

    IF (SELECT last_post_title FROM threads WHERE id = v_thread_b)
       <> 'Thread B renamed' THEN
        RAISE EXCEPTION 'FAIL threads_sync_title on Thread B';
    END IF;

    IF (SELECT last_post_title FROM forums WHERE id = v_forum_id)
       <> 'Thread A' THEN
        RAISE EXCEPTION 'FAIL thread title update: non-latest thread changed forum title';
    END IF;

    -- Rename latest thread A. Forum title must follow.
    UPDATE threads
    SET title = 'Thread A renamed'
    WHERE id = v_thread_a;

    IF (SELECT last_post_title FROM threads WHERE id = v_thread_a)
       <> 'Thread A renamed' THEN
        RAISE EXCEPTION 'FAIL threads_sync_title on Thread A';
    END IF;

    IF (SELECT last_post_title FROM forums WHERE id = v_forum_id)
       <> 'Thread A renamed' THEN
        RAISE EXCEPTION 'FAIL forum_after_thread_title_update';
    END IF;

    RAISE NOTICE 'PASS title synchronization triggers';

    ---------------------------------------------------------------------------
    -- 8. REPLY INSERT VALIDATION
    -- forum_validate_reply_insert()
    ---------------------------------------------------------------------------

    BEGIN
        INSERT INTO replies (thread_id, user_id, post)
        VALUES (v_thread_a, NULL, 'invalid reply');

        RAISE EXCEPTION 'FAIL replies_validate_insert: NULL user_id was accepted';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM = 'FAIL replies_validate_insert: NULL user_id was accepted' THEN
                RAISE;
            END IF;
    END;

    RAISE NOTICE 'PASS reply insert validation';

    ---------------------------------------------------------------------------
    -- 9. REPLY INSERT + COUNTERS + LATEST ACTIVITY
    -- forum_after_reply_insert()
    -- replies_after_insert
    ---------------------------------------------------------------------------

    INSERT INTO replies (thread_id, user_id, post, created_at)
    VALUES (
        v_thread_b,
        v_user2,
        'Reply B1',
        TIMESTAMPTZ '2026-01-01 11:00:00+00'
    )
    RETURNING id INTO v_reply_b1;

    IF (SELECT messages_count FROM threads WHERE id = v_thread_b) <> 1 THEN
        RAISE EXCEPTION 'FAIL reply insert: Thread B reply count';
    END IF;

    SELECT messages_count, last_post_thread_id, last_post_title,
           last_post_author_id, last_post_date
    INTO v_count, v_thread_id, v_title, v_author, v_date
    FROM forums
    WHERE id = v_forum_id;

    IF v_count <> 3
       OR v_thread_id <> v_thread_b
       OR v_title <> 'Thread B renamed'
       OR v_author IS DISTINCT FROM v_user2
       OR v_date IS DISTINCT FROM TIMESTAMPTZ '2026-01-01 11:00:00+00' THEN
        RAISE EXCEPTION 'FAIL reply insert: forum state after Reply B1';
    END IF;

    IF (SELECT replies_count FROM neon_auth."user" WHERE id = v_user2)
       <> v_user2_replies_before + 1 THEN
        RAISE EXCEPTION 'FAIL reply insert: user2 replies_count after Reply B1';
    END IF;

    INSERT INTO replies (thread_id, user_id, post, created_at)
    VALUES (
        v_thread_a,
        v_user1,
        'Reply A1',
        TIMESTAMPTZ '2026-01-01 12:00:00+00'
    )
    RETURNING id INTO v_reply_a1;

    INSERT INTO replies (thread_id, user_id, post, created_at)
    VALUES (
        v_thread_a,
        v_user2,
        'Reply A2',
        TIMESTAMPTZ '2026-01-01 13:00:00+00'
    )
    RETURNING id INTO v_reply_a2;

    IF (SELECT messages_count FROM threads WHERE id = v_thread_a) <> 2 THEN
        RAISE EXCEPTION 'FAIL reply insert: Thread A reply count should be 2';
    END IF;

    SELECT messages_count, last_post_thread_id, last_post_title,
           last_post_author_id, last_post_date
    INTO v_count, v_thread_id, v_title, v_author, v_date
    FROM forums
    WHERE id = v_forum_id;

    IF v_count <> 5
       OR v_thread_id <> v_thread_a
       OR v_title <> 'Thread A renamed'
       OR v_author IS DISTINCT FROM v_user2
       OR v_date IS DISTINCT FROM TIMESTAMPTZ '2026-01-01 13:00:00+00' THEN
        RAISE EXCEPTION 'FAIL reply insert: forum state after A replies';
    END IF;

    IF (SELECT replies_count FROM neon_auth."user" WHERE id = v_user1)
       <> v_user1_replies_before + 1 THEN
        RAISE EXCEPTION 'FAIL reply insert: user1 replies_count';
    END IF;

    IF (SELECT replies_count FROM neon_auth."user" WHERE id = v_user2)
       <> v_user2_replies_before + 2 THEN
        RAISE EXCEPTION 'FAIL reply insert: user2 replies_count after A2';
    END IF;

    RAISE NOTICE 'PASS reply insert/counter/latest triggers';

    ---------------------------------------------------------------------------
    -- 10. REPLY updated_at
    ---------------------------------------------------------------------------

    SELECT updated_at INTO v_old_updated_at
    FROM replies
    WHERE id = v_reply_b1;

    PERFORM pg_sleep(0.01);

    UPDATE replies
    SET post = 'Reply B1 edited'
    WHERE id = v_reply_b1;

    IF (SELECT updated_at FROM replies WHERE id = v_reply_b1) <= v_old_updated_at THEN
        RAISE EXCEPTION 'FAIL replies_set_updated_at';
    END IF;

    RAISE NOTICE 'PASS replies_set_updated_at';

    ---------------------------------------------------------------------------
    -- 11. IMMUTABLE REPLY RELATION FIELDS
    -- forum_prevent_reply_relation_changes()
    ---------------------------------------------------------------------------

    BEGIN
        UPDATE replies
        SET thread_id = v_thread_b
        WHERE id = v_reply_a1;

        RAISE EXCEPTION 'FAIL replies_prevent_relation_changes: thread_id changed';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM = 'FAIL replies_prevent_relation_changes: thread_id changed' THEN
                RAISE;
            END IF;
    END;

    BEGIN
        UPDATE replies
        SET user_id = v_user2
        WHERE id = v_reply_a1;

        RAISE EXCEPTION 'FAIL replies_prevent_relation_changes: user_id changed';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM = 'FAIL replies_prevent_relation_changes: user_id changed' THEN
                RAISE;
            END IF;
    END;

    BEGIN
        UPDATE replies
        SET created_at = TIMESTAMPTZ '2024-01-01 00:00:00+00'
        WHERE id = v_reply_a1;

        RAISE EXCEPTION 'FAIL replies_prevent_relation_changes: created_at changed';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM = 'FAIL replies_prevent_relation_changes: created_at changed' THEN
                RAISE;
            END IF;
    END;

    RAISE NOTICE 'PASS reply immutable-field trigger';

    ---------------------------------------------------------------------------
    -- 12. REPLY DELETE RECALCULATION
    -- forum_after_reply_delete()
    -- replies_after_delete
    ---------------------------------------------------------------------------

    -- Remove newest A reply. A should fall back to A1.
    DELETE FROM replies
    WHERE id = v_reply_a2;

    SELECT messages_count, last_post_title, last_post_author_id, last_post_date
    INTO v_count, v_title, v_author, v_date
    FROM threads
    WHERE id = v_thread_a;

    IF v_count <> 1
       OR v_title <> 'Thread A renamed'
       OR v_author IS DISTINCT FROM v_user1
       OR v_date IS DISTINCT FROM TIMESTAMPTZ '2026-01-01 12:00:00+00' THEN
        RAISE EXCEPTION 'FAIL reply delete: Thread A did not fall back to A1';
    END IF;

    SELECT messages_count, last_post_thread_id, last_post_author_id, last_post_date
    INTO v_count, v_thread_id, v_author, v_date
    FROM forums
    WHERE id = v_forum_id;

    IF v_count <> 4
       OR v_thread_id <> v_thread_a
       OR v_author IS DISTINCT FROM v_user1
       OR v_date IS DISTINCT FROM TIMESTAMPTZ '2026-01-01 12:00:00+00' THEN
        RAISE EXCEPTION 'FAIL reply delete: forum state after deleting A2';
    END IF;

    IF (SELECT replies_count FROM neon_auth."user" WHERE id = v_user2)
       <> v_user2_replies_before + 1 THEN
        RAISE EXCEPTION 'FAIL reply delete: user2 replies_count after deleting A2';
    END IF;

    -- Remove A1. Thread A falls back to its opening post at 10:00,
    -- so Thread B reply at 11:00 becomes forum latest.
    DELETE FROM replies
    WHERE id = v_reply_a1;

    SELECT messages_count, last_post_author_id, last_post_date
    INTO v_count, v_author, v_date
    FROM threads
    WHERE id = v_thread_a;

    IF v_count <> 0
       OR v_author IS DISTINCT FROM v_user1
       OR v_date IS DISTINCT FROM TIMESTAMPTZ '2026-01-01 10:00:00+00' THEN
        RAISE EXCEPTION 'FAIL reply delete: Thread A did not fall back to opening post';
    END IF;

    SELECT messages_count, last_post_thread_id, last_post_title,
           last_post_author_id, last_post_date
    INTO v_count, v_thread_id, v_title, v_author, v_date
    FROM forums
    WHERE id = v_forum_id;

    IF v_count <> 3
       OR v_thread_id <> v_thread_b
       OR v_title <> 'Thread B renamed'
       OR v_author IS DISTINCT FROM v_user2
       OR v_date IS DISTINCT FROM TIMESTAMPTZ '2026-01-01 11:00:00+00' THEN
        RAISE EXCEPTION 'FAIL reply delete: forum did not fall back to Thread B';
    END IF;

    IF (SELECT replies_count FROM neon_auth."user" WHERE id = v_user1)
       <> v_user1_replies_before THEN
        RAISE EXCEPTION 'FAIL reply delete: user1 replies_count did not return to baseline';
    END IF;

    RAISE NOTICE 'PASS reply delete/recalculation trigger';

    ---------------------------------------------------------------------------
    -- 13. THREAD DELETE + CASCADED REPLY DELETE
    -- forum_after_thread_delete()
    -- threads_after_delete
    -- also exercises replies ON DELETE CASCADE and reply delete trigger
    ---------------------------------------------------------------------------

    DELETE FROM threads
    WHERE id = v_thread_b;

    -- Thread B had one reply, so forum now contains only Thread A opening post.
    SELECT messages_count, last_post_thread_id, last_post_title,
           last_post_author_id, last_post_date
    INTO v_count, v_thread_id, v_title, v_author, v_date
    FROM forums
    WHERE id = v_forum_id;

    IF v_count <> 1
       OR v_thread_id <> v_thread_a
       OR v_title <> 'Thread A renamed'
       OR v_author IS DISTINCT FROM v_user1
       OR v_date IS DISTINCT FROM TIMESTAMPTZ '2026-01-01 10:00:00+00' THEN
        RAISE EXCEPTION 'FAIL thread delete: forum state after deleting Thread B';
    END IF;

    IF (SELECT replies_count FROM neon_auth."user" WHERE id = v_user2)
       <> v_user2_replies_before THEN
        RAISE EXCEPTION 'FAIL thread delete cascade: user2 replies_count did not return to baseline';
    END IF;

    -- Delete final thread: forum aggregate/latest state must be empty.
    DELETE FROM threads
    WHERE id = v_thread_a;

    SELECT messages_count, last_post_thread_id, last_post_title,
           last_post_author_id, last_post_date
    INTO v_count, v_thread_id, v_title, v_author, v_date
    FROM forums
    WHERE id = v_forum_id;

    IF v_count <> 0
       OR v_thread_id IS NOT NULL
       OR v_title <> ''
       OR v_author IS NOT NULL
       OR v_date IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL thread delete: empty forum aggregate/latest state is wrong';
    END IF;

    RAISE NOTICE 'PASS thread delete/cascade/recalculation triggers';

    ---------------------------------------------------------------------------
    -- 14. FINAL INVARIANTS
    ---------------------------------------------------------------------------

    IF (SELECT replies_count FROM neon_auth."user" WHERE id = v_user1)
       <> v_user1_replies_before THEN
        RAISE EXCEPTION 'FAIL final invariant: user1 replies_count differs from baseline';
    END IF;

    IF (SELECT replies_count FROM neon_auth."user" WHERE id = v_user2)
       <> v_user2_replies_before THEN
        RAISE EXCEPTION 'FAIL final invariant: user2 replies_count differs from baseline';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM threads
        WHERE forum_id IN (v_forum_id, v_forum2_id)
    ) THEN
        RAISE EXCEPTION 'FAIL final invariant: test threads still exist';
    END IF;

    RAISE NOTICE '============================================================';
    RAISE NOTICE 'ALL FORUM FUNCTION/TRIGGER TESTS PASSED';
    RAISE NOTICE 'Transaction will now be rolled back; no test data is retained.';
    RAISE NOTICE '============================================================';
END
$test$;

ROLLBACK;
