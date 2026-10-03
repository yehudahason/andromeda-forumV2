-- =========================================================
-- COMBINED FORUM MIGRATION - UP
-- Combines 000001 + 000002 + 000003
-- =========================================================

-- =========================================================
-- FORUM MIGRATION - UP
-- PostgreSQL - PRODUCTION HARDENED
-- =========================================================

-- =========================================================
-- FORUMS
-- =========================================================

CREATE TABLE forums (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    name TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',

    -- Total messages in this forum: threads + replies.
    messages_count BIGINT NOT NULL DEFAULT 0
        CONSTRAINT forums_messages_count_check CHECK (messages_count >= 0),

    last_post_title TEXT NOT NULL DEFAULT '',
    last_post_author_id UUID,
    last_post_date TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),

    CONSTRAINT forums_last_post_author_fk
        FOREIGN KEY (last_post_author_id)
        REFERENCES neon_auth."user"(id)
        ON DELETE SET NULL,

    CONSTRAINT forums_name_length_check
        CHECK (char_length(btrim(name)) BETWEEN 1 AND 100)
);


-- =========================================================
-- THREADS
-- =========================================================

CREATE TABLE threads (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    forum_id BIGINT NOT NULL,
    -- Nullable only so historical content survives auth-user deletion.
    -- New threads are still required to have an author by trigger.
    user_id UUID,

    title TEXT NOT NULL,
    content TEXT NOT NULL,

    -- Total messages in this thread: opening post + replies.
    messages_count BIGINT NOT NULL DEFAULT 1
        CONSTRAINT threads_messages_count_check CHECK (messages_count >= 1),

    last_post_title TEXT NOT NULL DEFAULT '',
    last_post_author_id UUID,
    last_post_date TIMESTAMPTZ,

    notify BOOLEAN NOT NULL DEFAULT FALSE,
    sticky BOOLEAN NOT NULL DEFAULT FALSE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),

    CONSTRAINT threads_forum_id_fk
        FOREIGN KEY (forum_id)
        REFERENCES forums(id)
        ON DELETE CASCADE,

    CONSTRAINT threads_user_id_fk
        FOREIGN KEY (user_id)
        REFERENCES neon_auth."user"(id)
        ON DELETE SET NULL,

    CONSTRAINT threads_last_post_author_id_fk
        FOREIGN KEY (last_post_author_id)
        REFERENCES neon_auth."user"(id)
        ON DELETE SET NULL,

    CONSTRAINT threads_title_length_check
        CHECK (char_length(btrim(title)) BETWEEN 1 AND 255),

    CONSTRAINT threads_content_length_check
        CHECK (char_length(content) BETWEEN 1 AND 100000)
);


-- =========================================================
-- REPLIES
-- =========================================================

CREATE TABLE replies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    thread_id BIGINT NOT NULL,
    -- Nullable only so historical content survives auth-user deletion.
    -- New replies are still required to have an author by trigger.
    user_id UUID,

    post TEXT NOT NULL,
    notify BOOLEAN NOT NULL DEFAULT FALSE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),

    CONSTRAINT replies_thread_id_fk
        FOREIGN KEY (thread_id)
        REFERENCES threads(id)
        ON DELETE CASCADE,

    CONSTRAINT replies_user_id_fk
        FOREIGN KEY (user_id)
        REFERENCES neon_auth."user"(id)
        ON DELETE SET NULL,

    CONSTRAINT replies_post_length_check
        CHECK (char_length(post) BETWEEN 1 AND 100000)
);


-- =========================================================
-- USER REPLY COUNT
-- =========================================================

ALTER TABLE neon_auth."user"
ADD COLUMN replies_count BIGINT NOT NULL DEFAULT 0
    CONSTRAINT user_replies_count_check CHECK (replies_count >= 0);


-- =========================================================
-- INDEXES
-- PostgreSQL does not automatically index foreign-key columns.
-- =========================================================

DROP INDEX IF EXISTS idx_threads_forum_id;
CREATE INDEX idx_threads_forum_id
    ON threads(forum_id);

DROP INDEX IF EXISTS idx_threads_user_id;
CREATE INDEX idx_threads_user_id
    ON threads(user_id);

DROP INDEX IF EXISTS idx_threads_created_at;
CREATE INDEX idx_threads_created_at
    ON threads(created_at DESC);

DROP INDEX IF EXISTS idx_threads_last_post_date;
CREATE INDEX idx_threads_last_post_date
    ON threads(last_post_date DESC NULLS LAST);

DROP INDEX IF EXISTS idx_threads_forum_last_post_date;
CREATE INDEX idx_threads_forum_last_post_date
    ON threads(forum_id, last_post_date DESC NULLS LAST, id DESC);

DROP INDEX IF EXISTS idx_threads_forum_sticky_last_post;
CREATE INDEX idx_threads_forum_sticky_last_post
    ON threads(forum_id, sticky DESC, last_post_date DESC NULLS LAST, id DESC);

DROP INDEX IF EXISTS idx_threads_notify;
CREATE INDEX idx_threads_notify
    ON threads(id)
    WHERE notify = TRUE;

DROP INDEX IF EXISTS idx_replies_thread_id;
CREATE INDEX idx_replies_thread_id
    ON replies(thread_id);

DROP INDEX IF EXISTS idx_replies_user_id;
CREATE INDEX idx_replies_user_id
    ON replies(user_id);

DROP INDEX IF EXISTS idx_replies_created_at;
CREATE INDEX idx_replies_created_at
    ON replies(created_at DESC);

DROP INDEX IF EXISTS idx_replies_thread_created_at;
CREATE INDEX idx_replies_thread_created_at
    ON replies(thread_id, created_at DESC, id DESC);


-- =========================================================
-- FORUM INITIAL VALUES
-- Prevent callers from seeding trigger-maintained aggregate state.
-- =========================================================

DROP FUNCTION IF EXISTS forum_prepare_forum_insert();
CREATE FUNCTION forum_prepare_forum_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.messages_count := 0;
    NEW.last_post_title := '';
    NEW.last_post_author_id := NULL;
    NEW.last_post_date := NULL;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS forums_prepare_insert ON forums;
CREATE TRIGGER forums_prepare_insert
BEFORE INSERT ON forums
FOR EACH ROW
EXECUTE FUNCTION forum_prepare_forum_insert();


-- =========================================================
-- GENERIC updated_at TRIGGER FUNCTION
-- =========================================================

DROP FUNCTION IF EXISTS forum_set_updated_at();
CREATE FUNCTION forum_set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := clock_timestamp();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS forums_set_updated_at ON forums;
CREATE TRIGGER forums_set_updated_at
BEFORE UPDATE ON forums
FOR EACH ROW
EXECUTE FUNCTION forum_set_updated_at();

DROP TRIGGER IF EXISTS threads_set_updated_at ON threads;
CREATE TRIGGER threads_set_updated_at
BEFORE UPDATE ON threads
FOR EACH ROW
EXECUTE FUNCTION forum_set_updated_at();

DROP TRIGGER IF EXISTS replies_set_updated_at ON replies;
CREATE TRIGGER replies_set_updated_at
BEFORE UPDATE ON replies
FOR EACH ROW
EXECUTE FUNCTION forum_set_updated_at();


-- =========================================================
-- THREAD INITIAL VALUES
-- =========================================================

DROP FUNCTION IF EXISTS forum_prepare_thread_insert();
CREATE FUNCTION forum_prepare_thread_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.user_id IS NULL THEN
        RAISE EXCEPTION 'new thread user_id cannot be NULL';
    END IF;

    -- created_at normally comes from the column default. This also handles
    -- callers that explicitly supply NULL before NOT NULL is checked.
    IF NEW.created_at IS NULL THEN
        NEW.created_at := clock_timestamp();
    END IF;

    NEW.messages_count := 1;
    NEW.last_post_title := NEW.title;
    NEW.last_post_author_id := NEW.user_id;
    NEW.last_post_date := NEW.created_at;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS threads_prepare_insert ON threads;
CREATE TRIGGER threads_prepare_insert
BEFORE INSERT ON threads
FOR EACH ROW
EXECUTE FUNCTION forum_prepare_thread_insert();


-- =========================================================
-- IMMUTABLE RELATION / CREATION FIELDS
-- =========================================================

DROP FUNCTION IF EXISTS forum_prevent_thread_relation_changes();
CREATE FUNCTION forum_prevent_thread_relation_changes()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.forum_id IS DISTINCT FROM OLD.forum_id THEN
        RAISE EXCEPTION 'thread forum_id cannot be changed';
    END IF;

    IF NEW.user_id IS DISTINCT FROM OLD.user_id
       AND NEW.user_id IS NOT NULL THEN
        RAISE EXCEPTION 'thread user_id cannot be changed';
    END IF;

    IF NEW.created_at IS DISTINCT FROM OLD.created_at THEN
        RAISE EXCEPTION 'thread created_at cannot be changed';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS threads_prevent_relation_changes ON threads;
CREATE TRIGGER threads_prevent_relation_changes
BEFORE UPDATE OF forum_id, user_id, created_at ON threads
FOR EACH ROW
EXECUTE FUNCTION forum_prevent_thread_relation_changes();


DROP FUNCTION IF EXISTS forum_prevent_reply_relation_changes();
CREATE FUNCTION forum_prevent_reply_relation_changes()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.thread_id IS DISTINCT FROM OLD.thread_id THEN
        RAISE EXCEPTION 'reply thread_id cannot be changed';
    END IF;

    IF NEW.user_id IS DISTINCT FROM OLD.user_id
       AND NEW.user_id IS NOT NULL THEN
        RAISE EXCEPTION 'reply user_id cannot be changed';
    END IF;

    IF NEW.created_at IS DISTINCT FROM OLD.created_at THEN
        RAISE EXCEPTION 'reply created_at cannot be changed';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS replies_prevent_relation_changes ON replies;
CREATE TRIGGER replies_prevent_relation_changes
BEFORE UPDATE OF thread_id, user_id, created_at ON replies
FOR EACH ROW
EXECUTE FUNCTION forum_prevent_reply_relation_changes();


-- =========================================================
-- REPLY INSERT VALIDATION
-- user_id is nullable only for preserving historical rows after user deletion.
-- =========================================================

DROP FUNCTION IF EXISTS forum_validate_reply_insert();
CREATE FUNCTION forum_validate_reply_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.user_id IS NULL THEN
        RAISE EXCEPTION 'new reply user_id cannot be NULL';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS replies_validate_insert ON replies;
CREATE TRIGGER replies_validate_insert
BEFORE INSERT ON replies
FOR EACH ROW
EXECUTE FUNCTION forum_validate_reply_insert();


-- =========================================================
-- PROTECT TRIGGER-MAINTAINED DENORMALIZED FIELDS
-- Direct application writes are rejected. Nested writes issued by this
-- migration's own triggers remain allowed. SET NULL of last_post_author_id
-- is allowed so ON DELETE SET NULL can preserve content after user deletion.
-- =========================================================

DROP FUNCTION IF EXISTS forum_guard_forum_denormalized_update();
CREATE FUNCTION forum_guard_forum_denormalized_update()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF pg_trigger_depth() = 1 THEN
        IF NEW.messages_count IS DISTINCT FROM OLD.messages_count
           OR NEW.last_post_title IS DISTINCT FROM OLD.last_post_title
           OR NEW.last_post_date IS DISTINCT FROM OLD.last_post_date
           OR (
                NEW.last_post_author_id IS DISTINCT FROM OLD.last_post_author_id
                AND NEW.last_post_author_id IS NOT NULL
           ) THEN
            RAISE EXCEPTION 'forum message/last-post fields are trigger-maintained';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS forums_guard_denormalized_update ON forums;
CREATE TRIGGER forums_guard_denormalized_update
BEFORE UPDATE OF messages_count, last_post_title, last_post_author_id, last_post_date
ON forums
FOR EACH ROW
EXECUTE FUNCTION forum_guard_forum_denormalized_update();


DROP FUNCTION IF EXISTS forum_guard_thread_denormalized_update();
CREATE FUNCTION forum_guard_thread_denormalized_update()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF pg_trigger_depth() = 1 THEN
        IF NEW.messages_count IS DISTINCT FROM OLD.messages_count
           OR NEW.last_post_date IS DISTINCT FROM OLD.last_post_date
           OR (
                NEW.last_post_title IS DISTINCT FROM OLD.last_post_title
                AND NEW.title IS NOT DISTINCT FROM OLD.title
           )
           OR (
                NEW.last_post_author_id IS DISTINCT FROM OLD.last_post_author_id
                AND NEW.last_post_author_id IS NOT NULL
           ) THEN
            RAISE EXCEPTION 'thread message/last-post fields are trigger-maintained';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS threads_guard_denormalized_update ON threads;
CREATE TRIGGER threads_guard_denormalized_update
BEFORE UPDATE OF messages_count, last_post_title, last_post_author_id, last_post_date
ON threads
FOR EACH ROW
EXECUTE FUNCTION forum_guard_thread_denormalized_update();


-- =========================================================
-- THREAD AFTER INSERT
-- =========================================================

DROP FUNCTION IF EXISTS forum_after_thread_insert();
CREATE FUNCTION forum_after_thread_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- Lock the forum before updating
    PERFORM 1 FROM forums WHERE id = NEW.forum_id FOR UPDATE;

    UPDATE forums
    SET
        messages_count = messages_count + 1,
        last_post_title = CASE
            WHEN last_post_date IS NULL OR NEW.last_post_date >= last_post_date
                THEN NEW.title
            ELSE last_post_title
        END,
        last_post_author_id = CASE
            WHEN last_post_date IS NULL OR NEW.last_post_date >= last_post_date
                THEN NEW.last_post_author_id
            ELSE last_post_author_id
        END,
        last_post_date = CASE
            WHEN last_post_date IS NULL OR NEW.last_post_date >= last_post_date
                THEN NEW.last_post_date
            ELSE last_post_date
        END
    WHERE id = NEW.forum_id;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS threads_after_insert ON threads;
CREATE TRIGGER threads_after_insert
AFTER INSERT ON threads
FOR EACH ROW
EXECUTE FUNCTION forum_after_thread_insert();


-- =========================================================
-- THREAD TITLE UPDATE
-- Keep denormalized thread/forum titles synchronized.
-- =========================================================

DROP FUNCTION IF EXISTS forum_sync_thread_title();
CREATE FUNCTION forum_sync_thread_title()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.last_post_title := NEW.title;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS threads_sync_title ON threads;
CREATE TRIGGER threads_sync_title
BEFORE UPDATE OF title ON threads
FOR EACH ROW
WHEN (NEW.title IS DISTINCT FROM OLD.title)
EXECUTE FUNCTION forum_sync_thread_title();


DROP FUNCTION IF EXISTS forum_after_thread_title_update();
CREATE FUNCTION forum_after_thread_title_update()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_latest_thread_id BIGINT;
BEGIN
    -- Lock the forum before checking/updating
    PERFORM 1 FROM forums WHERE id = NEW.forum_id FOR UPDATE;

    SELECT t.id
    INTO v_latest_thread_id
    FROM threads AS t
    WHERE t.forum_id = NEW.forum_id
    ORDER BY t.last_post_date DESC NULLS LAST, t.id DESC
    LIMIT 1
    FOR UPDATE;

    IF v_latest_thread_id = NEW.id THEN
        UPDATE forums
        SET last_post_title = NEW.title
        WHERE id = NEW.forum_id;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS threads_after_title_update ON threads;
CREATE TRIGGER threads_after_title_update
AFTER UPDATE OF title ON threads
FOR EACH ROW
WHEN (NEW.title IS DISTINCT FROM OLD.title)
EXECUTE FUNCTION forum_after_thread_title_update();


-- =========================================================
-- REPLY AFTER INSERT
-- Thread -> forum -> user update order is kept consistent.
-- =========================================================

DROP FUNCTION IF EXISTS forum_after_reply_insert();
CREATE FUNCTION forum_after_reply_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_forum_id BIGINT;
    v_thread_title TEXT;
BEGIN
    -- Update thread and get forum_id/title in one operation
    UPDATE threads
    SET
        messages_count = messages_count + 1,
        last_post_title = CASE
            WHEN last_post_date IS NULL OR NEW.created_at >= last_post_date
                THEN title
            ELSE last_post_title
        END,
        last_post_author_id = CASE
            WHEN last_post_date IS NULL OR NEW.created_at >= last_post_date
                THEN NEW.user_id
            ELSE last_post_author_id
        END,
        last_post_date = CASE
            WHEN last_post_date IS NULL OR NEW.created_at >= last_post_date
                THEN NEW.created_at
            ELSE last_post_date
        END
    WHERE id = NEW.thread_id
    RETURNING forum_id, title
    INTO v_forum_id, v_thread_title;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'thread % does not exist', NEW.thread_id;
    END IF;

    -- Lock the forum before updating it
    PERFORM 1 FROM forums WHERE id = v_forum_id FOR UPDATE;

    UPDATE forums
    SET
        messages_count = messages_count + 1,
        last_post_title = CASE
            WHEN last_post_date IS NULL OR NEW.created_at >= last_post_date
                THEN v_thread_title
            ELSE last_post_title
        END,
        last_post_author_id = CASE
            WHEN last_post_date IS NULL OR NEW.created_at >= last_post_date
                THEN NEW.user_id
            ELSE last_post_author_id
        END,
        last_post_date = CASE
            WHEN last_post_date IS NULL OR NEW.created_at >= last_post_date
                THEN NEW.created_at
            ELSE last_post_date
        END
    WHERE id = v_forum_id;

    -- User row updated last
    UPDATE neon_auth."user"
    SET replies_count = replies_count + 1
    WHERE id = NEW.user_id;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS replies_after_insert ON replies;
CREATE TRIGGER replies_after_insert
AFTER INSERT ON replies
FOR EACH ROW
EXECUTE FUNCTION forum_after_reply_insert();


-- =========================================================
-- REPLY AFTER DELETE
-- Statement-level trigger: one recalculation per affected thread/forum,
-- even when many replies are deleted in one statement.
-- =========================================================

DROP FUNCTION IF EXISTS forum_after_reply_delete();
CREATE FUNCTION forum_after_reply_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_thread_id BIGINT;
    v_forum_id BIGINT;
    v_thread_title TEXT;
    v_thread_user_id UUID;
    v_thread_created_at TIMESTAMPTZ;
    v_last_reply_id UUID;
    v_last_reply_user_id UUID;
    v_last_reply_created_at TIMESTAMPTZ;
    v_latest_title TEXT;
    v_latest_author_id UUID;
    v_latest_date TIMESTAMPTZ;
BEGIN
    UPDATE neon_auth."user" AS u
    SET replies_count = GREATEST(u.replies_count - d.deleted_count, 0)
    FROM (
        SELECT user_id, COUNT(*)::BIGINT AS deleted_count
        FROM deleted_replies
        WHERE user_id IS NOT NULL
        GROUP BY user_id
    ) AS d
    WHERE u.id = d.user_id;

    FOR v_thread_id IN
        SELECT DISTINCT thread_id
        FROM deleted_replies
    LOOP
        SELECT t.forum_id, t.title, t.user_id, t.created_at
        INTO v_forum_id, v_thread_title, v_thread_user_id, v_thread_created_at
        FROM threads AS t
        WHERE t.id = v_thread_id
        FOR UPDATE;

        IF NOT FOUND THEN
            CONTINUE;
        END IF;

        v_last_reply_id := NULL;
        v_last_reply_user_id := NULL;
        v_last_reply_created_at := NULL;

        SELECT r.id, r.user_id, r.created_at
        INTO v_last_reply_id, v_last_reply_user_id, v_last_reply_created_at
        FROM replies AS r
        WHERE r.thread_id = v_thread_id
        ORDER BY r.created_at DESC, r.id DESC
        LIMIT 1;

        UPDATE threads
        SET
            messages_count = 1 + (
                SELECT COUNT(*)
                FROM replies AS r
                WHERE r.thread_id = v_thread_id
            ),
            last_post_title = v_thread_title,
            last_post_author_id = CASE
                WHEN v_last_reply_id IS NOT NULL THEN v_last_reply_user_id
                ELSE v_thread_user_id
            END,
            last_post_date = COALESCE(v_last_reply_created_at, v_thread_created_at)
        WHERE id = v_thread_id;
    END LOOP;

    FOR v_forum_id IN
        SELECT DISTINCT t.forum_id
        FROM deleted_replies AS d
        JOIN threads AS t ON t.id = d.thread_id
    LOOP
        PERFORM 1
        FROM forums
        WHERE id = v_forum_id
        FOR UPDATE;

        IF NOT FOUND THEN
            CONTINUE;
        END IF;

        SELECT
            t.last_post_title,
            t.last_post_author_id,
            t.last_post_date
        INTO v_latest_title, v_latest_author_id, v_latest_date
        FROM threads AS t
        WHERE t.forum_id = v_forum_id
        ORDER BY t.last_post_date DESC NULLS LAST, t.id DESC
        LIMIT 1;

        UPDATE forums AS f
        SET
            messages_count =
                (SELECT COUNT(*) FROM threads AS t WHERE t.forum_id = v_forum_id)
                +
                (SELECT COUNT(*)
                 FROM replies AS r
                 JOIN threads AS t ON t.id = r.thread_id
                 WHERE t.forum_id = v_forum_id),
            last_post_title = COALESCE(v_latest_title, ''),
            last_post_author_id = v_latest_author_id,
            last_post_date = v_latest_date
        WHERE f.id = v_forum_id;
    END LOOP;

    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS replies_after_delete ON replies;
CREATE TRIGGER replies_after_delete
AFTER DELETE ON replies
REFERENCING OLD TABLE AS deleted_replies
FOR EACH STATEMENT
EXECUTE FUNCTION forum_after_reply_delete();


-- =========================================================
-- THREAD AFTER DELETE
-- Statement-level trigger: recalculate each surviving forum once.
-- This also keeps forum deletion cascades cheap because a deleted forum
-- is simply skipped.
-- =========================================================

DROP FUNCTION IF EXISTS forum_after_thread_delete();
CREATE FUNCTION forum_after_thread_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_forum_id BIGINT;
    v_latest_title TEXT;
    v_latest_author_id UUID;
    v_latest_date TIMESTAMPTZ;
BEGIN
    FOR v_forum_id IN
        SELECT DISTINCT forum_id
        FROM deleted_threads
    LOOP
        PERFORM 1
        FROM forums
        WHERE id = v_forum_id
        FOR UPDATE;

        IF NOT FOUND THEN
            CONTINUE;
        END IF;

        SELECT
            t.last_post_title,
            t.last_post_author_id,
            t.last_post_date
        INTO v_latest_title, v_latest_author_id, v_latest_date
        FROM threads AS t
        WHERE t.forum_id = v_forum_id
        ORDER BY t.last_post_date DESC NULLS LAST, t.id DESC
        LIMIT 1;

        UPDATE forums AS f
        SET
            messages_count =
                (SELECT COUNT(*) FROM threads AS t WHERE t.forum_id = v_forum_id)
                +
                (SELECT COUNT(*)
                 FROM replies AS r
                 JOIN threads AS t ON t.id = r.thread_id
                 WHERE t.forum_id = v_forum_id),
            last_post_title = COALESCE(v_latest_title, ''),
            last_post_author_id = v_latest_author_id,
            last_post_date = v_latest_date
        WHERE f.id = v_forum_id;
    END LOOP;

    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS threads_after_delete ON threads;
CREATE TRIGGER threads_after_delete
AFTER DELETE ON threads
REFERENCING OLD TABLE AS deleted_threads
FOR EACH STATEMENT
EXECUTE FUNCTION forum_after_thread_delete();


-- =========================================================
-- COMMENTS
-- =========================================================

COMMENT ON TABLE forums IS 'Forum categories containing threads';
COMMENT ON COLUMN forums.id IS 'Unique forum identifier';
COMMENT ON COLUMN forums.name IS 'Forum name (1-100 characters)';
COMMENT ON COLUMN forums.description IS 'Forum description';
COMMENT ON COLUMN forums.messages_count IS 'Total messages in the forum: threads + replies';
COMMENT ON COLUMN forums.last_post_title IS 'Title of the most recently active thread';
COMMENT ON COLUMN forums.last_post_author_id IS 'User ID of the most recent poster';
COMMENT ON COLUMN forums.last_post_date IS 'Timestamp of the most recent forum activity';

COMMENT ON TABLE threads IS 'Discussion threads within forums';
COMMENT ON COLUMN threads.id IS 'Unique thread identifier';
COMMENT ON COLUMN threads.forum_id IS 'Parent forum ID';
COMMENT ON COLUMN threads.user_id IS 'Original thread author ID; NULL only after that auth user is deleted';
COMMENT ON COLUMN threads.title IS 'Thread title (1-255 characters)';
COMMENT ON COLUMN threads.content IS 'Opening post content/body';
COMMENT ON COLUMN threads.messages_count IS 'Total messages in thread: opening post + replies';
COMMENT ON COLUMN threads.last_post_title IS 'Copy of the current thread title';
COMMENT ON COLUMN threads.last_post_author_id IS 'User ID of the most recent poster in the thread';
COMMENT ON COLUMN threads.last_post_date IS 'Timestamp of the most recent thread activity';
COMMENT ON COLUMN threads.notify IS 'Whether the thread author requested notifications';
COMMENT ON COLUMN threads.sticky IS 'Whether the thread is pinned';

COMMENT ON TABLE replies IS 'Replies to forum threads';
COMMENT ON COLUMN replies.id IS 'Unique reply identifier';
COMMENT ON COLUMN replies.thread_id IS 'Parent thread ID';
COMMENT ON COLUMN replies.user_id IS 'Reply author ID; NULL only after that auth user is deleted';
COMMENT ON COLUMN replies.post IS 'Reply content/body';
COMMENT ON COLUMN replies.notify IS 'Whether the reply author requested notifications';

COMMENT ON COLUMN neon_auth."user".replies_count IS 'Total number of replies currently authored by this user';

-- =========================================================
-- ADD FORUM LAST POST THREAD ID
-- Combined from migration 000002 final schema requirement
-- =========================================================

BEGIN;

ALTER TABLE forums
    ADD COLUMN last_post_thread_id BIGINT;

ALTER TABLE forums
    ADD CONSTRAINT forums_last_post_thread_fk
    FOREIGN KEY (last_post_thread_id)
    REFERENCES threads(id)
    ON DELETE SET NULL;

CREATE INDEX idx_forums_last_post_thread_id
    ON forums(last_post_thread_id);

COMMIT;

-- =========================================================
-- SET REPLY COUNTS TO START FROM 0
-- PostgreSQL
--
-- Keeps the existing forum behavior the same.
--
-- After this migration:
--   threads.messages_count = number of replies only
--   neon_auth."user".replies_count = number of replies only
--
-- A new thread starts with messages_count = 0.
-- Each reply increments both the thread count and author's user count.
-- Deleting replies recalculates/decrements the counts correctly.
-- =========================================================

BEGIN;

-- =========================================================
-- THREAD COUNT DEFINITION
-- Change from "opening post + replies" to "replies only".
-- =========================================================

ALTER TABLE threads
    ALTER COLUMN messages_count SET DEFAULT 0;

ALTER TABLE threads
    DROP CONSTRAINT IF EXISTS threads_messages_count_check;

ALTER TABLE threads
    ADD CONSTRAINT threads_messages_count_check
    CHECK (messages_count >= 0);


-- =========================================================
-- THREAD INITIAL VALUES
-- New threads must start with 0 replies.
-- =========================================================

CREATE OR REPLACE FUNCTION forum_prepare_thread_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.user_id IS NULL THEN
        RAISE EXCEPTION 'new thread user_id cannot be NULL';
    END IF;

    IF NEW.created_at IS NULL THEN
        NEW.created_at := clock_timestamp();
    END IF;

    -- replies only: a new thread has zero replies
    NEW.messages_count := 0;

    NEW.last_post_title := NEW.title;
    NEW.last_post_author_id := NEW.user_id;
    NEW.last_post_date := NEW.created_at;

    RETURN NEW;
END;
$$;


-- =========================================================
-- BACKFILL EXISTING THREAD COUNTS
--
-- The normal guard trigger prevents direct writes to messages_count.
-- Temporarily remove only that trigger while repairing stored counts.
-- The guard function itself is left unchanged.
-- =========================================================

DROP TRIGGER IF EXISTS threads_guard_denormalized_update ON threads;

UPDATE threads AS t
SET messages_count = (
    SELECT COUNT(*)::BIGINT
    FROM replies AS r
    WHERE r.thread_id = t.id
);

CREATE TRIGGER threads_guard_denormalized_update
BEFORE UPDATE OF
    messages_count,
    last_post_title,
    last_post_author_id,
    last_post_date
ON threads
FOR EACH ROW
EXECUTE FUNCTION forum_guard_thread_denormalized_update();


-- =========================================================
-- BACKFILL EXISTING USER REPLY COUNTS
-- Users with no replies are explicitly reset to 0.
-- =========================================================

UPDATE neon_auth."user" AS u
SET replies_count = COALESCE((
    SELECT COUNT(*)::BIGINT
    FROM replies AS r
    WHERE r.user_id = u.id
), 0);


-- =========================================================
-- REPLY AFTER INSERT
--
-- Existing logic is already correct for reply-only counts:
--   thread.messages_count += 1
--   forum.messages_count  += 1
--   user.replies_count    += 1
--
-- Recreate it here so this migration is self-contained and guarantees
-- the expected behavior after older migrations have run.
-- =========================================================

CREATE OR REPLACE FUNCTION forum_after_reply_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_forum_id BIGINT;
    v_thread_title TEXT;
BEGIN
    UPDATE threads
    SET
        messages_count = messages_count + 1,
        last_post_title = CASE
            WHEN last_post_date IS NULL OR NEW.created_at >= last_post_date
                THEN title
            ELSE last_post_title
        END,
        last_post_author_id = CASE
            WHEN last_post_date IS NULL OR NEW.created_at >= last_post_date
                THEN NEW.user_id
            ELSE last_post_author_id
        END,
        last_post_date = CASE
            WHEN last_post_date IS NULL OR NEW.created_at >= last_post_date
                THEN NEW.created_at
            ELSE last_post_date
        END
    WHERE id = NEW.thread_id
    RETURNING forum_id, title
    INTO v_forum_id, v_thread_title;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'thread % does not exist', NEW.thread_id;
    END IF;

    PERFORM 1
    FROM forums
    WHERE id = v_forum_id
    FOR UPDATE;

    -- Forum count intentionally remains:
    -- total forum messages = threads + replies.
    UPDATE forums
    SET
        messages_count = messages_count + 1,
        last_post_thread_id = CASE
            WHEN last_post_date IS NULL OR NEW.created_at >= last_post_date
                THEN NEW.thread_id
            ELSE last_post_thread_id
        END,
        last_post_title = CASE
            WHEN last_post_date IS NULL OR NEW.created_at >= last_post_date
                THEN v_thread_title
            ELSE last_post_title
        END,
        last_post_author_id = CASE
            WHEN last_post_date IS NULL OR NEW.created_at >= last_post_date
                THEN NEW.user_id
            ELSE last_post_author_id
        END,
        last_post_date = CASE
            WHEN last_post_date IS NULL OR NEW.created_at >= last_post_date
                THEN NEW.created_at
            ELSE last_post_date
        END
    WHERE id = v_forum_id;

    UPDATE neon_auth."user"
    SET replies_count = replies_count + 1
    WHERE id = NEW.user_id;

    RETURN NEW;
END;
$$;


-- =========================================================
-- REPLY AFTER DELETE
--
-- Important change:
-- thread.messages_count is recalculated as COUNT(replies),
-- NOT 1 + COUNT(replies).
-- =========================================================

CREATE OR REPLACE FUNCTION forum_after_reply_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_thread_id BIGINT;
    v_forum_id BIGINT;
    v_thread_title TEXT;
    v_thread_user_id UUID;
    v_thread_created_at TIMESTAMPTZ;
    v_last_reply_id UUID;
    v_last_reply_user_id UUID;
    v_last_reply_created_at TIMESTAMPTZ;
    v_latest_thread_id BIGINT;
    v_latest_title TEXT;
    v_latest_author_id UUID;
    v_latest_date TIMESTAMPTZ;
BEGIN
    -- Decrement each affected user's reply count.
    UPDATE neon_auth."user" AS u
    SET replies_count = GREATEST(u.replies_count - d.deleted_count, 0)
    FROM (
        SELECT user_id, COUNT(*)::BIGINT AS deleted_count
        FROM deleted_replies
        WHERE user_id IS NOT NULL
        GROUP BY user_id
    ) AS d
    WHERE u.id = d.user_id;

    -- Recalculate each affected surviving thread.
    FOR v_thread_id IN
        SELECT DISTINCT thread_id
        FROM deleted_replies
    LOOP
        SELECT t.forum_id, t.title, t.user_id, t.created_at
        INTO v_forum_id, v_thread_title, v_thread_user_id, v_thread_created_at
        FROM threads AS t
        WHERE t.id = v_thread_id
        FOR UPDATE;

        -- During ON DELETE CASCADE from threads, the thread may already
        -- be gone. In that case there is nothing to recalculate here.
        IF NOT FOUND THEN
            CONTINUE;
        END IF;

        v_last_reply_id := NULL;
        v_last_reply_user_id := NULL;
        v_last_reply_created_at := NULL;

        SELECT r.id, r.user_id, r.created_at
        INTO v_last_reply_id, v_last_reply_user_id, v_last_reply_created_at
        FROM replies AS r
        WHERE r.thread_id = v_thread_id
        ORDER BY r.created_at DESC, r.id DESC
        LIMIT 1;

        UPDATE threads
        SET
            -- replies only
            messages_count = (
                SELECT COUNT(*)::BIGINT
                FROM replies AS r
                WHERE r.thread_id = v_thread_id
            ),
            last_post_title = v_thread_title,
            last_post_author_id = CASE
                WHEN v_last_reply_id IS NOT NULL THEN v_last_reply_user_id
                ELSE v_thread_user_id
            END,
            last_post_date = COALESCE(
                v_last_reply_created_at,
                v_thread_created_at
            )
        WHERE id = v_thread_id;
    END LOOP;

    -- Forum semantics stay unchanged:
    -- forum.messages_count = threads + replies.
    FOR v_forum_id IN
        SELECT DISTINCT t.forum_id
        FROM deleted_replies AS d
        JOIN threads AS t ON t.id = d.thread_id
    LOOP
        PERFORM 1
        FROM forums
        WHERE id = v_forum_id
        FOR UPDATE;

        IF NOT FOUND THEN
            CONTINUE;
        END IF;

        v_latest_thread_id := NULL;
        v_latest_title := NULL;
        v_latest_author_id := NULL;
        v_latest_date := NULL;

        SELECT
            t.id,
            t.last_post_title,
            t.last_post_author_id,
            t.last_post_date
        INTO
            v_latest_thread_id,
            v_latest_title,
            v_latest_author_id,
            v_latest_date
        FROM threads AS t
        WHERE t.forum_id = v_forum_id
        ORDER BY t.last_post_date DESC NULLS LAST, t.id DESC
        LIMIT 1;

        UPDATE forums AS f
        SET
            messages_count =
                (
                    SELECT COUNT(*)::BIGINT
                    FROM threads AS t
                    WHERE t.forum_id = v_forum_id
                )
                +
                (
                    SELECT COUNT(*)::BIGINT
                    FROM replies AS r
                    JOIN threads AS t ON t.id = r.thread_id
                    WHERE t.forum_id = v_forum_id
                ),
            last_post_thread_id = v_latest_thread_id,
            last_post_title = COALESCE(v_latest_title, ''),
            last_post_author_id = v_latest_author_id,
            last_post_date = v_latest_date
        WHERE f.id = v_forum_id;
    END LOOP;

    RETURN NULL;
END;
$$;


-- =========================================================
-- ENSURE THE EXISTING TRIGGERS POINT TO THE CORRECT FUNCTIONS
-- =========================================================

DROP TRIGGER IF EXISTS threads_prepare_insert ON threads;
CREATE TRIGGER threads_prepare_insert
BEFORE INSERT ON threads
FOR EACH ROW
EXECUTE FUNCTION forum_prepare_thread_insert();

DROP TRIGGER IF EXISTS replies_after_insert ON replies;
CREATE TRIGGER replies_after_insert
AFTER INSERT ON replies
FOR EACH ROW
EXECUTE FUNCTION forum_after_reply_insert();

DROP TRIGGER IF EXISTS replies_after_delete ON replies;
CREATE TRIGGER replies_after_delete
AFTER DELETE ON replies
REFERENCING OLD TABLE AS deleted_replies
FOR EACH STATEMENT
EXECUTE FUNCTION forum_after_reply_delete();


-- =========================================================
-- COMMENTS
-- =========================================================

COMMENT ON COLUMN threads.messages_count
IS 'Total number of replies in the thread; opening post is not counted';

COMMENT ON COLUMN neon_auth."user".replies_count
IS 'Total number of replies currently authored by this user';

COMMIT;
