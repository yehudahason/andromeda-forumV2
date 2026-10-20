-- REVIEWED/DOCUMENTED COPY: original upload remains untouched.
-- Two scoped behavioral fixes versus the original migration:
--   (1) Enforce private-message sender membership/non-NULL at INSERT time.
--   (2) Allow private_messages.sender_id to become NULL on auth.users DELETE.
-- DO NOT run a complete CREATE TABLE migration again on an existing database.
-- See forum_trigger_review.md and private_trigger_patch_existing.sql.
-- Static review only: no live PostgreSQL instance was available for runtime tests.

-- Forum schema - full UP migration
-- Supabase version: auth.users handles authentication; public.profiles preserves forum identity; public.forum_user_stats tracks active-user counts.

BEGIN;

-- =========================================================
-- USER PROFILE + MESSAGE COUNT
-- auth.users remains the authentication source of truth.
-- profiles preserves public forum identity (name/avatar) after auth deletion.
-- forum_user_stats exists only while the auth user exists.
-- =========================================================

CREATE TABLE public.profiles (
  id UUID PRIMARY KEY,
  -- Mirrors auth.users.id while the auth user exists.
  -- Becomes NULL on auth-user deletion so the public profile can remain
  -- available for historical forum posts.
  auth_user_id UUID UNIQUE,
  name TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'user'
  CHECK (role IN ('user', 'admin', 'moderator')),
  image_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT profiles_auth_user_id_fk
    FOREIGN KEY (auth_user_id) REFERENCES auth.users (id) ON DELETE SET NULL,
  CONSTRAINT profiles_auth_user_matches_id_check
    CHECK (auth_user_id IS NULL OR auth_user_id = id),
  CONSTRAINT profiles_name_length_check
    CHECK (char_length(btrim(name)) BETWEEN 1 AND 100)
);

CREATE TABLE public.forum_user_stats (
  user_id UUID PRIMARY KEY,
  replies_count BIGINT NOT NULL DEFAULT 0
    CONSTRAINT forum_user_stats_replies_count_check CHECK (replies_count >= 0),
  CONSTRAINT forum_user_stats_user_id_fk
    FOREIGN KEY (user_id) REFERENCES auth.users (id) ON DELETE CASCADE
);

-- FUNCTION: Initialize per-account forum counters after auth.users insertion; ignore existing entries.
CREATE OR REPLACE FUNCTION public.forum_create_user_stats()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    INSERT INTO public.forum_user_stats (user_id)
    VALUES (NEW.id)
    ON CONFLICT (user_id) DO NOTHING;

    RETURN NEW;
END;
$$;

-- TRIGGER (AFTER INSERT on auth.users): Create forum_user_stats for the new auth user.
CREATE TRIGGER forum_auth_user_created
AFTER INSERT
ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.forum_create_user_stats();

-- FUNCTION: Create/upsert a public profile from auth.users metadata, retaining identity across later auth deletion.
CREATE OR REPLACE FUNCTION public.create_user_profile()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_name TEXT;
    v_image_url TEXT;
BEGIN
    v_name := left(
        COALESCE(
            NULLIF(btrim(NEW.raw_user_meta_data ->> 'name'), ''),
            NULLIF(btrim(NEW.raw_user_meta_data ->> 'full_name'), ''),
            NULLIF(btrim(split_part(COALESCE(NEW.email, ''), '@', 1)), ''),
            'User'
        ),
        100
    );

    v_image_url := COALESCE(
        NULLIF(btrim(NEW.raw_user_meta_data ->> 'avatar_url'), ''),
        NULLIF(btrim(NEW.raw_user_meta_data ->> 'picture'), '')
    );

    INSERT INTO public.profiles (
        id,
        auth_user_id,
        name,
        image_url
    )
    VALUES (
        NEW.id,
        NEW.id,
        v_name,
        v_image_url
    )
    ON CONFLICT (id) DO UPDATE
    SET
        auth_user_id = EXCLUDED.auth_user_id,
        name = EXCLUDED.name,
        image_url = EXCLUDED.image_url,
        updated_at = clock_timestamp();

    RETURN NEW;
END;
$$;

-- TRIGGER (AFTER INSERT on auth.users): Create the persistent public profile for the new auth user.
CREATE TRIGGER on_auth_user_created
AFTER INSERT
ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.create_user_profile();

-- Backfill users that existed before this migration.
INSERT INTO public.forum_user_stats (user_id)
SELECT id
FROM auth.users
ON CONFLICT (user_id) DO NOTHING;

INSERT INTO public.profiles (
    id,
    auth_user_id,
    name,
    image_url
)
SELECT
    u.id,
    u.id,
    left(
        COALESCE(
            NULLIF(btrim(u.raw_user_meta_data ->> 'name'), ''),
            NULLIF(btrim(u.raw_user_meta_data ->> 'full_name'), ''),
            NULLIF(btrim(split_part(COALESCE(u.email, ''), '@', 1)), ''),
            'User'
        ),
        100
    ),
    COALESCE(
        NULLIF(btrim(u.raw_user_meta_data ->> 'avatar_url'), ''),
        NULLIF(btrim(u.raw_user_meta_data ->> 'picture'), '')
    )
FROM auth.users AS u
ON CONFLICT (id) DO NOTHING;

-- =========================================================
-- FORUMS
-- =========================================================

CREATE TABLE forums (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  sort_order BIGINT NOT NULL,
  name TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  -- Total messages in this forum: threads + replies.
  messages_count BIGINT NOT NULL DEFAULT 0 CONSTRAINT forums_messages_count_check CHECK (messages_count >= 0),
  last_post_thread_id BIGINT,
  last_post_title TEXT NOT NULL DEFAULT '',
  last_post_author_id UUID,
  last_post_date TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT forums_last_post_author_fk FOREIGN KEY (last_post_author_id) REFERENCES public.profiles (id) ON DELETE SET NULL,
  CONSTRAINT forums_name_length_check CHECK (char_length(btrim(name)) BETWEEN 1 AND 100)
);

-- =========================================================
-- THREADS
-- =========================================================

CREATE TABLE threads (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  forum_id BIGINT NOT NULL,
  views BIGINT NOT NULL DEFAULT 0
    CONSTRAINT threads_views_check CHECK (views >= 0),
  -- Normally references a preserved public profile.
  -- New threads must reference an active auth user; NULL is only possible if the profile itself is deleted.
  user_id UUID,
  title TEXT NOT NULL,
  content TEXT NOT NULL,
  -- Total number of replies in this thread; opening post is not counted.
  messages_count BIGINT NOT NULL DEFAULT 0 CONSTRAINT threads_messages_count_check CHECK (messages_count >= 0),
  last_post_title TEXT NOT NULL DEFAULT '',
  last_post_author_id UUID,
  last_post_date TIMESTAMPTZ,
  notify BOOLEAN NOT NULL DEFAULT TRUE,
  sticky BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT threads_forum_id_fk FOREIGN KEY (forum_id) REFERENCES forums (id) ON DELETE CASCADE,
  CONSTRAINT threads_user_id_fk FOREIGN KEY (user_id) REFERENCES public.profiles (id) ON DELETE SET NULL,
  CONSTRAINT threads_last_post_author_id_fk FOREIGN KEY (last_post_author_id) REFERENCES public.profiles (id) ON DELETE SET NULL,
  CONSTRAINT threads_title_length_check CHECK (char_length(btrim(title)) BETWEEN 1 AND 255),
  CONSTRAINT threads_content_length_check CHECK (char_length(content) BETWEEN 1 AND 100000)
);

-- Threads that has been read
CREATE TABLE thread_reads (
    user_id UUID NOT NULL
        REFERENCES public.profiles(id)
        ON DELETE CASCADE,

    thread_id BIGINT NOT NULL
        REFERENCES public.threads(id)
        ON DELETE CASCADE,

    last_read_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    PRIMARY KEY (user_id, thread_id)
);
ALTER TABLE forums
ADD CONSTRAINT forums_last_post_thread_fk FOREIGN KEY (last_post_thread_id) REFERENCES threads (id) ON DELETE SET NULL;

-- =========================================================
-- REPLIES
-- =========================================================

CREATE TABLE replies (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  thread_id BIGINT NOT NULL,
  -- Normally references a preserved public profile.
  -- New replies must reference an active auth user; NULL is only possible if the profile itself is deleted.
  user_id UUID,
  post TEXT NOT NULL,
  notify BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT replies_thread_id_fk FOREIGN KEY (thread_id) REFERENCES threads (id) ON DELETE CASCADE,
  CONSTRAINT replies_user_id_fk FOREIGN KEY (user_id) REFERENCES public.profiles (id) ON DELETE SET NULL,
  CONSTRAINT replies_post_length_check CHECK (char_length(post) BETWEEN 1 AND 100000)
);

-- notification for followed threads  and private messages
CREATE TABLE public.notifications (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    user_id UUID NOT NULL
        REFERENCES auth.users(id) ON DELETE CASCADE,

    type TEXT NOT NULL
        CHECK (type IN ('thread_reply', 'private_message')),

    thread_id BIGINT
        REFERENCES public.threads(id) ON DELETE CASCADE,

    thread_page BIGINT  NOT NULL DEFAULT 1 ,

    reply_id UUID
        REFERENCES public.replies(id) ON DELETE CASCADE,


    message_id BIGINT,

    actor_id UUID
        REFERENCES auth.users(id) ON DELETE SET NULL,

    is_read BOOLEAN NOT NULL DEFAULT FALSE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT notifications_target_check CHECK (
        (
            type = 'thread_reply'
            AND thread_id IS NOT NULL
            AND reply_id IS NOT NULL
            AND message_id IS NULL
        )
        OR
        (
            type = 'private_message'
            AND message_id IS NOT NULL
            AND thread_id IS NULL
            AND reply_id IS NULL
        )
    )
);

CREATE TABLE public.private_threads (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    title TEXT,

    created_by UUID
        REFERENCES auth.users(id)
        ON DELETE SET NULL,

    last_message_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE public.private_thread_participants (
    thread_id BIGINT NOT NULL
        REFERENCES public.private_threads(id)
        ON DELETE CASCADE,

    user_id UUID NOT NULL
        REFERENCES auth.users(id)
        ON DELETE CASCADE,

    joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    last_read_at TIMESTAMPTZ,

    PRIMARY KEY (thread_id, user_id)
);

CREATE TABLE public.private_messages (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    thread_id BIGINT NOT NULL
        REFERENCES public.private_threads(id)
        ON DELETE CASCADE,

    sender_id UUID
        REFERENCES auth.users(id)
        ON DELETE SET NULL,

    content TEXT NOT NULL
        CHECK (
            char_length(btrim(content)) BETWEEN 1 AND 100000
        ),

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);



-- Validates every new message at the database boundary.
-- The Go API must still authenticate the caller and authorize their actions:
-- this trigger checks sender/participant consistency, not caller identity.
-- Participants must be inserted BEFORE the first message in the same transaction.
-- FUNCTION: Require a non-NULL private-message sender who already belongs to the conversation.
CREATE OR REPLACE FUNCTION public.private_messages_validate_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
    IF NEW.sender_id IS NULL THEN
        RAISE EXCEPTION 'private message sender_id cannot be NULL';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.private_thread_participants AS p
        WHERE p.thread_id = NEW.thread_id
          AND p.user_id = NEW.sender_id
    ) THEN
        RAISE EXCEPTION 'private message sender must be a thread participant';
    END IF;

    RETURN NEW;
END;
$$;

-- TRIGGER (BEFORE INSERT on public.private_messages): Reject anonymous/new messages from nonparticipants.
CREATE TRIGGER private_messages_validate_insert
BEFORE INSERT ON public.private_messages
FOR EACH ROW
EXECUTE FUNCTION public.private_messages_validate_insert();

-- FUNCTION: After a private message insert, create one notification for each participant other than the sender.
CREATE OR REPLACE FUNCTION public.notify_private_message_participants()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    INSERT INTO public.notifications (
        user_id,
        type,
        message_id,
        actor_id
    )
    SELECT
        p.user_id,
        'private_message',
        NEW.id,
        NEW.sender_id
    FROM public.private_thread_participants AS p
    WHERE p.thread_id = NEW.thread_id
      AND p.user_id IS DISTINCT FROM NEW.sender_id;

    RETURN NULL;
END;
$$;


-- TRIGGER (AFTER INSERT on public.private_messages): Notify all other participants; the sender is excluded.
CREATE TRIGGER private_messages_notify_participants
AFTER INSERT ON public.private_messages
FOR EACH ROW
EXECUTE FUNCTION public.notify_private_message_participants();


-- FUNCTION: Refresh updated_at on private threads and messages whenever they are updated.
CREATE OR REPLACE FUNCTION public.private_set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
    NEW.updated_at := clock_timestamp();
    RETURN NEW;
END;
$$;
-- TRIGGER (BEFORE UPDATE on public.private_threads): Refresh private thread updated_at.
CREATE TRIGGER private_threads_set_updated_at
BEFORE UPDATE ON public.private_threads
FOR EACH ROW
EXECUTE FUNCTION public.private_set_updated_at();

-- TRIGGER (BEFORE UPDATE on public.private_messages): Refresh private message updated_at.
CREATE TRIGGER private_messages_set_updated_at
BEFORE UPDATE ON public.private_messages
FOR EACH ROW
EXECUTE FUNCTION public.private_set_updated_at();


-- FUNCTION: Move private_threads.last_message_at forward to the inserted message timestamp.
CREATE OR REPLACE FUNCTION public.private_messages_after_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
    UPDATE public.private_threads AS t
    SET last_message_at = GREATEST(
        t.last_message_at,
        NEW.created_at
    )
    WHERE t.id = NEW.thread_id;

    RETURN NULL;
END;
$$;

-- TRIGGER (AFTER INSERT on public.private_messages): Track newest private message timestamp in its conversation.
CREATE TRIGGER private_messages_after_insert
AFTER INSERT ON public.private_messages
FOR EACH ROW
EXECUTE FUNCTION public.private_messages_after_insert();


ALTER TABLE public.notifications
ADD CONSTRAINT notifications_message_id_fk
FOREIGN KEY (message_id)
REFERENCES public.private_messages(id)
ON DELETE CASCADE;


-- Find conversations belonging to a user
CREATE INDEX idx_private_participants_user
ON public.private_thread_participants (user_id, thread_id);

-- Fetch messages efficiently with pagination
CREATE INDEX idx_private_messages_thread
ON public.private_messages (
    thread_id,
    created_at DESC,
    id DESC
);

-- Sort conversations by recent activity
CREATE INDEX idx_private_threads_last_message
ON public.private_threads (
    last_message_at DESC NULLS LAST
);

-- FUNCTION: Recalculate private_threads.last_message_at when a message is deleted, including deletion of the latest message.
CREATE OR REPLACE FUNCTION public.private_messages_after_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
    UPDATE public.private_threads AS t
    SET last_message_at = (
        SELECT MAX(m.created_at)
        FROM public.private_messages AS m
        WHERE m.thread_id = OLD.thread_id
    )
    WHERE t.id = OLD.thread_id;

    RETURN NULL;
END;
$$;

-- TRIGGER (AFTER DELETE on public.private_messages): Recompute newest private message timestamp after deletion.
CREATE TRIGGER private_messages_after_delete
AFTER DELETE ON public.private_messages
FOR EACH ROW
EXECUTE FUNCTION public.private_messages_after_delete();


-- FUNCTION: Forbid private message identity/parent/timestamp changes; permit sender_id becoming NULL on auth-user deletion.
CREATE OR REPLACE FUNCTION public.private_messages_protect_fields()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
    -- sender_id can become NULL when auth.users is deleted because
    -- private_messages.sender_id has ON DELETE SET NULL. Reassigning a
    -- message to another non-NULL sender remains forbidden.
    -- Limit direct UPDATE privileges: this exception also permits an
    -- explicit sender_id=NULL update by a sufficiently privileged role.
    IF NEW.thread_id IS DISTINCT FROM OLD.thread_id
       OR (
            NEW.sender_id IS DISTINCT FROM OLD.sender_id
            AND NEW.sender_id IS NOT NULL
          )
       OR NEW.created_at IS DISTINCT FROM OLD.created_at
       OR NEW.id IS DISTINCT FROM OLD.id
    THEN
        RAISE EXCEPTION 'Cannot modify protected message fields';
    END IF;

    RETURN NEW;
END;
$$;

-- TRIGGER (BEFORE UPDATE on public.private_messages): Preserve immutable fields while allowing sender removal via auth FK.
CREATE TRIGGER private_messages_protect_fields
BEFORE UPDATE ON public.private_messages
FOR EACH ROW
EXECUTE FUNCTION public.private_messages_protect_fields();
CREATE INDEX notifications_user_created_idx
ON public.notifications (user_id, created_at DESC);

CREATE INDEX notifications_unread_idx
ON public.notifications (user_id, created_at DESC)
WHERE is_read = FALSE;

CREATE UNIQUE INDEX notifications_unique_reply_idx
ON public.notifications (user_id, reply_id)
WHERE type = 'thread_reply';

CREATE UNIQUE INDEX notifications_unique_message_idx
ON public.notifications (user_id, message_id)
WHERE type = 'private_message';

--list of followed threads
CREATE TABLE public.thread_follows (
    user_id UUID NOT NULL
        REFERENCES auth.users(id) ON DELETE CASCADE,

    thread_id BIGINT NOT NULL
        REFERENCES public.threads(id) ON DELETE CASCADE,
    

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    PRIMARY KEY (user_id, thread_id)
);

CREATE INDEX thread_follows_thread_idx
ON public.thread_follows (thread_id);

  -- Notify all followers except the reply author
-- FUNCTION: Create a notification for every thread follower except the reply author; store a 14-replies/page estimate.
CREATE OR REPLACE FUNCTION public.notify_thread_followers()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_page INTEGER;
BEGIN
    -- Calculate the page of the new reply (14 replies per page)
    SELECT ((COUNT(*) - 1) / 14 + 1)::INTEGER
    INTO v_page
    FROM public.replies
    WHERE thread_id = NEW.thread_id;

    -- Notify all followers except the reply author
    INSERT INTO public.notifications (
        user_id,
        type,
        thread_id,
        thread_page,
        reply_id,
        actor_id
    )
    SELECT
        tf.user_id,
        'thread_reply',
        NEW.thread_id,
        v_page,
        NEW.id,
        NEW.user_id
    FROM public.thread_follows AS tf
    WHERE tf.thread_id = NEW.thread_id
      AND tf.user_id <> NEW.user_id
    ON CONFLICT DO NOTHING;

    RETURN NEW;
END;
$$;

-- TRIGGER (AFTER INSERT on public.replies): Create thread follower notifications.
CREATE TRIGGER replies_notify_followers
AFTER INSERT ON public.replies
FOR EACH ROW
EXECUTE FUNCTION public.notify_thread_followers();


-- =========================================================
-- INDEXES
-- PostgreSQL does not automatically index foreign-key columns.
-- =========================================================

CREATE INDEX idx_forums_last_post_thread_id ON forums (last_post_thread_id);

CREATE INDEX idx_threads_forum_id ON threads (forum_id);

CREATE INDEX idx_threads_user_id ON threads (user_id);

CREATE INDEX idx_threads_created_at ON threads (created_at DESC);

CREATE INDEX idx_threads_last_post_date ON threads (last_post_date DESC NULLS LAST);

CREATE INDEX idx_threads_forum_last_post_date ON threads (forum_id, last_post_date DESC NULLS LAST, id DESC);

CREATE INDEX idx_threads_forum_sticky_last_post ON threads (
  forum_id,
  sticky DESC,
  last_post_date DESC NULLS LAST,
  id DESC
);

CREATE INDEX idx_threads_notify ON threads (id)
WHERE
notify = TRUE;

CREATE INDEX idx_replies_thread_id ON replies (thread_id);

CREATE INDEX idx_replies_user_id ON replies (user_id);

CREATE INDEX idx_replies_created_at ON replies (created_at DESC);

CREATE INDEX idx_replies_thread_created_at ON replies (thread_id, created_at DESC, id DESC);

-- =========================================================
-- FORUM INITIAL VALUES
-- Prevent callers from seeding trigger-maintained aggregate state.
-- =========================================================

-- FUNCTION: Reset forum aggregate columns to their initial values on insert.
CREATE OR REPLACE FUNCTION forum_prepare_forum_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.messages_count := 0;
    NEW.last_post_thread_id := NULL;
    NEW.last_post_title := '';
    NEW.last_post_author_id := NULL;
    NEW.last_post_date := NULL;
    RETURN NEW;
END;
$$;

-- TRIGGER (BEFORE INSERT on forums): Initialize zero aggregate state for new forums.
CREATE TRIGGER forums_prepare_insert
BEFORE INSERT
ON forums
FOR EACH ROW
EXECUTE FUNCTION forum_prepare_forum_insert();

-- =========================================================
-- GENERIC updated_at TRIGGER FUNCTION
-- =========================================================

-- FUNCTION: Maintain updated_at on forum profiles, categories, threads, and replies.
CREATE OR REPLACE FUNCTION forum_set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := clock_timestamp();
    RETURN NEW;
END;
$$;

-- TRIGGER (BEFORE UPDATE on public.profiles): Refresh public profile updated_at.
CREATE TRIGGER profiles_set_updated_at
BEFORE UPDATE
ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION forum_set_updated_at();

-- TRIGGER (BEFORE UPDATE on forums): Refresh forum updated_at.
CREATE TRIGGER forums_set_updated_at
BEFORE UPDATE
ON forums
FOR EACH ROW
EXECUTE FUNCTION forum_set_updated_at();

-- TRIGGER (BEFORE UPDATE on threads): Refresh thread updated_at.
CREATE TRIGGER threads_set_updated_at
BEFORE UPDATE
ON threads
FOR EACH ROW
EXECUTE FUNCTION forum_set_updated_at();

-- TRIGGER (BEFORE UPDATE on replies): Refresh reply updated_at.
CREATE TRIGGER replies_set_updated_at
BEFORE UPDATE
ON replies
FOR EACH ROW
EXECUTE FUNCTION forum_set_updated_at();

-- FUNCTION: Require active thread author; initialize reply count and last-post metadata.
CREATE OR REPLACE FUNCTION forum_prepare_thread_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.user_id IS NULL THEN
        RAISE EXCEPTION 'new thread user_id cannot be NULL';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.profiles AS p
        WHERE p.id = NEW.user_id
          AND p.auth_user_id = NEW.user_id
    ) THEN
        RAISE EXCEPTION 'new thread user_id must reference an active auth user';
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

-- TRIGGER (BEFORE INSERT on threads): Check thread author and initialize aggregate state.
CREATE TRIGGER threads_prepare_insert
BEFORE INSERT
ON threads
FOR EACH ROW
EXECUTE FUNCTION forum_prepare_thread_insert();

-- =========================================================
-- IMMUTABLE RELATION / CREATION FIELDS
-- =========================================================

-- FUNCTION: Prevent reparenting/reassigning threads and changes to their creation timestamp; allow author SET NULL on profile deletion.
CREATE OR REPLACE FUNCTION forum_prevent_thread_relation_changes()
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

-- TRIGGER (BEFORE UPDATE on threads): Forbid editing thread parent, author or created_at (except author SET NULL).
CREATE TRIGGER threads_prevent_relation_changes
BEFORE UPDATE OF
    forum_id,
    user_id,
    created_at
ON threads
FOR EACH ROW
EXECUTE FUNCTION forum_prevent_thread_relation_changes();

-- FUNCTION: Prevent reparenting/reassigning replies and changes to their creation timestamp; allow author SET NULL on profile deletion.
CREATE OR REPLACE FUNCTION forum_prevent_reply_relation_changes()
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

-- TRIGGER (BEFORE UPDATE on replies): Forbid editing reply parent, author or created_at (except author SET NULL).
CREATE TRIGGER replies_prevent_relation_changes
BEFORE UPDATE OF
    thread_id,
    user_id,
    created_at
ON replies
FOR EACH ROW
EXECUTE FUNCTION forum_prevent_reply_relation_changes();

-- =========================================================
-- REPLY INSERT VALIDATION
-- New replies must belong to an active auth user. Historical profile IDs remain after auth-user deletion.
-- =========================================================

-- FUNCTION: Require every newly inserted reply to reference an active forum profile.
CREATE OR REPLACE FUNCTION forum_validate_reply_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.user_id IS NULL THEN
        RAISE EXCEPTION 'new reply user_id cannot be NULL';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.profiles AS p
        WHERE p.id = NEW.user_id
          AND p.auth_user_id = NEW.user_id
    ) THEN
        RAISE EXCEPTION 'new reply user_id must reference an active auth user';
    END IF;

    RETURN NEW;
END;
$$;

-- TRIGGER (BEFORE INSERT on replies): Require a valid, active author for new replies.
CREATE TRIGGER replies_validate_insert
BEFORE INSERT
ON replies
FOR EACH ROW
EXECUTE FUNCTION forum_validate_reply_insert();

-- =========================================================
-- PROTECT TRIGGER-MAINTAINED DENORMALIZED FIELDS
-- Direct application writes are rejected. Nested writes issued by this
-- migration's own triggers remain allowed. SET NULL of last_post_author_id
-- is allowed so ON DELETE SET NULL can preserve content if a profile row is explicitly deleted.
-- =========================================================

-- FUNCTION: Reject direct updates of forum cached counts/latest-post metadata; allow nested trigger maintenance.
CREATE OR REPLACE FUNCTION forum_guard_forum_denormalized_update()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF pg_trigger_depth() = 1 THEN
        IF NEW.messages_count IS DISTINCT FROM OLD.messages_count
           OR (
                NEW.last_post_thread_id IS DISTINCT FROM OLD.last_post_thread_id
                AND NEW.last_post_thread_id IS NOT NULL
           )
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

-- TRIGGER (BEFORE UPDATE on forums): Reject client modifications to cached forum aggregates.
CREATE TRIGGER forums_guard_denormalized_update
BEFORE UPDATE OF
    messages_count,
    last_post_thread_id,
    last_post_title,
    last_post_author_id,
    last_post_date
ON forums
FOR EACH ROW
EXECUTE FUNCTION forum_guard_forum_denormalized_update();

-- FUNCTION: Reject direct updates of thread cached counts/latest-post metadata; allow nested trigger maintenance.
CREATE OR REPLACE FUNCTION forum_guard_thread_denormalized_update()
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

-- TRIGGER (BEFORE UPDATE on threads): Reject client modifications to cached thread aggregates.
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
-- THREAD AFTER INSERT
-- =========================================================

-- FUNCTION: Update forum latest-post metadata and total messages; increment author message count.
CREATE OR REPLACE FUNCTION forum_after_thread_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- Lock the forum before updating
    PERFORM 1 FROM forums WHERE id = NEW.forum_id FOR UPDATE;
    UPDATE forums
    SET
        messages_count = messages_count + 1,
        last_post_thread_id = CASE
            WHEN last_post_date IS NULL OR NEW.last_post_date >= last_post_date
                THEN NEW.id
            ELSE last_post_thread_id
        END,
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
    -- User message count = opened threads + replies.
    UPDATE public.forum_user_stats
    SET replies_count = replies_count + 1
    WHERE user_id = NEW.user_id;
    RETURN NEW;
END;
$$;

-- TRIGGER (AFTER INSERT on threads): Update parent forum and author totals.
CREATE TRIGGER threads_after_insert
AFTER INSERT
ON threads
FOR EACH ROW
EXECUTE FUNCTION forum_after_thread_insert();

-- =========================================================
-- THREAD TITLE UPDATE
-- Keep denormalized thread/forum titles synchronized.
-- =========================================================

-- FUNCTION: Keep cached thread last_post_title synchronized with title during title updates.
CREATE OR REPLACE FUNCTION forum_sync_thread_title()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.last_post_title := NEW.title;
    RETURN NEW;
END;
$$;

-- TRIGGER (BEFORE UPDATE on threads): Mirror thread title into its cached last-post title.
CREATE TRIGGER threads_sync_title
BEFORE UPDATE OF title
ON threads
FOR EACH ROW
WHEN (NEW.title IS DISTINCT FROM OLD.title)
EXECUTE FUNCTION forum_sync_thread_title();

-- FUNCTION: Propagate a thread title change into the forum latest-post title when applicable.
CREATE OR REPLACE FUNCTION forum_after_thread_title_update()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE forums
    SET last_post_title = NEW.title
    WHERE id = NEW.forum_id
      AND last_post_thread_id = NEW.id;
    RETURN NEW;
END;
$$;

-- TRIGGER (AFTER UPDATE on threads): Refresh forum cached title when this thread was most recently active.
CREATE TRIGGER threads_after_title_update
AFTER UPDATE OF title
ON threads
FOR EACH ROW
WHEN (NEW.title IS DISTINCT FROM OLD.title)
EXECUTE FUNCTION forum_after_thread_title_update();

-- FUNCTION: Increment thread/forum reply counters and update latest-post metadata and author stats.
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
    UPDATE public.forum_user_stats
    SET replies_count = replies_count + 1
    WHERE user_id = NEW.user_id;
    RETURN NEW;
END;
$$;

-- TRIGGER (AFTER INSERT on replies): Update thread/forum latest-post data and counts.
CREATE TRIGGER replies_after_insert
AFTER INSERT
ON replies
FOR EACH ROW
EXECUTE FUNCTION forum_after_reply_insert();

-- FUNCTION: For affected surviving threads/forums, recalculate counters/latest-post metadata and decrement author stats.
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
    -- Keep lock/update order consistent with reply insertion:
    -- thread -> forum -> user.
    UPDATE public.forum_user_stats AS u
    SET replies_count = GREATEST(u.replies_count - d.deleted_count, 0)
    FROM (
        SELECT user_id, COUNT(*)::BIGINT AS deleted_count
        FROM deleted_replies
        WHERE user_id IS NOT NULL
        GROUP BY user_id
    ) AS d
    WHERE u.user_id = d.user_id;
    RETURN NULL;
END;
$$;

-- TRIGGER (AFTER DELETE (statement) on replies): Recompute affected thread/forum data using the deleted_replies transition table.
CREATE TRIGGER replies_after_delete
AFTER DELETE
ON replies
REFERENCING OLD TABLE AS deleted_replies
FOR EACH STATEMENT
EXECUTE FUNCTION forum_after_reply_delete();

-- =========================================================
-- THREAD AFTER DELETE
-- Statement-level trigger: recalculate each surviving forum once.
-- This also keeps forum deletion cascades cheap because a deleted forum
-- is simply skipped.
-- =========================================================

-- FUNCTION: For affected surviving forums, recalculate totals/latest-post metadata and decrement thread-author stats.
CREATE OR REPLACE FUNCTION forum_after_thread_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_forum_id BIGINT;
    v_latest_thread_id BIGINT;
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
            t.id,
            t.last_post_title,
            t.last_post_author_id,
            t.last_post_date
        INTO v_latest_thread_id, v_latest_title, v_latest_author_id, v_latest_date
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
            last_post_thread_id = v_latest_thread_id,
            last_post_title = COALESCE(v_latest_title, ''),
            last_post_author_id = v_latest_author_id,
            last_post_date = v_latest_date
        WHERE f.id = v_forum_id;
    END LOOP;
    -- Reply deletes (including ON DELETE CASCADE) already subtract replies.
    -- Subtract one more message for each deleted opening thread.
    UPDATE public.forum_user_stats AS u
    SET replies_count = GREATEST(u.replies_count - d.deleted_count, 0)
    FROM (
        SELECT user_id, COUNT(*)::BIGINT AS deleted_count
        FROM deleted_threads
        WHERE user_id IS NOT NULL
        GROUP BY user_id
    ) AS d
    WHERE u.user_id = d.user_id;
    RETURN NULL;
END;
$$;

-- TRIGGER (AFTER DELETE (statement) on threads): Recompute affected forum data using the deleted_threads transition table.
CREATE TRIGGER threads_after_delete
AFTER DELETE
ON threads
REFERENCING OLD TABLE AS deleted_threads
FOR EACH STATEMENT
EXECUTE FUNCTION forum_after_thread_delete();

-- =========================================================
-- COMMENTS
-- =========================================================

COMMENT ON TABLE public.profiles IS 'Public forum identity preserved independently of auth-user lifetime';
COMMENT ON COLUMN public.profiles.id IS 'Stable public profile ID; initially equal to auth.users.id';
COMMENT ON COLUMN public.profiles.auth_user_id IS 'Active auth user ID; becomes NULL when the auth account is deleted';
COMMENT ON COLUMN public.profiles.name IS 'Public display name';
COMMENT ON COLUMN public.profiles.image_url IS 'Public avatar/image URL';
COMMENT ON TABLE public.forum_user_stats IS 'Per-user forum message counters for active auth users';
COMMENT ON TABLE forums IS 'Forum categories containing threads';
COMMENT ON COLUMN forums.id IS 'Unique forum identifier';
COMMENT ON COLUMN forums.name IS 'Forum name (1-100 characters)';
COMMENT ON COLUMN forums.description IS 'Forum description';
COMMENT ON COLUMN forums.messages_count IS 'Total messages in the forum: threads + replies';
COMMENT ON COLUMN forums.last_post_thread_id IS 'Thread ID of the most recent forum activity';
COMMENT ON COLUMN forums.last_post_title IS 'Title of the most recently active thread';
COMMENT ON COLUMN forums.last_post_author_id IS 'Profile ID of the most recent poster';
COMMENT ON COLUMN forums.last_post_date IS 'Timestamp of the most recent forum activity';
COMMENT ON TABLE threads IS 'Discussion threads within forums';
COMMENT ON COLUMN threads.id IS 'Unique thread identifier';
COMMENT ON COLUMN threads.forum_id IS 'Parent forum ID';
COMMENT ON COLUMN threads.user_id IS 'Original author profile ID; normally preserved after auth-user deletion and NULL only if the profile itself is deleted';
COMMENT ON COLUMN threads.title IS 'Thread title (1-255 characters)';
COMMENT ON COLUMN threads.content IS 'Opening post content/body';
COMMENT ON COLUMN threads.messages_count IS 'Total number of replies in the thread; opening post is not counted';
COMMENT ON COLUMN threads.last_post_title IS 'Copy of the current thread title';
COMMENT ON COLUMN threads.last_post_author_id IS 'Profile ID of the most recent poster in the thread';
COMMENT ON COLUMN threads.last_post_date IS 'Timestamp of the most recent thread activity';
COMMENT ON COLUMN threads.notify IS 'Whether the thread author requested notifications';
COMMENT ON COLUMN threads.sticky IS 'Whether the thread is pinned';
COMMENT ON TABLE replies IS 'Replies to forum threads';
COMMENT ON COLUMN replies.id IS 'Unique reply identifier';
COMMENT ON COLUMN replies.thread_id IS 'Parent thread ID';
COMMENT ON COLUMN replies.user_id IS 'Reply author profile ID; normally preserved after auth-user deletion and NULL only if the profile itself is deleted';
COMMENT ON COLUMN replies.post IS 'Reply content/body';
COMMENT ON COLUMN replies.notify IS 'Whether the reply author requested notifications';
COMMENT ON COLUMN public.forum_user_stats.replies_count IS 'Total forum messages currently authored by this user: opened threads + replies';

-- =========================================================


-- =========================================================
-- PRIVATE MESSAGING / NOTIFICATION DATABASE DOCUMENTATION
-- These COMMENT statements are stored in PostgreSQL metadata and
-- appear in introspection tools (including psql and schema browsers).
-- =========================================================

COMMENT ON TABLE public.private_threads IS 'Private conversations. last_message_at is maintained by insert/delete message triggers; NULL indicates no messages.';
COMMENT ON COLUMN public.private_threads.created_by IS 'Authenticated user who created the conversation; nullable after auth account deletion.';
COMMENT ON COLUMN public.private_threads.last_message_at IS 'Newest remaining message created_at, or NULL if the conversation is empty.';
COMMENT ON TABLE public.private_thread_participants IS 'Conversation membership and per-user last-read timestamp.';
COMMENT ON COLUMN public.private_thread_participants.last_read_at IS 'Last private-message timestamp read by this participant; maintained by the Go read endpoint.';
COMMENT ON TABLE public.private_messages IS 'Messages in private conversations. New messages must have a sender who belongs to the conversation.';
COMMENT ON COLUMN public.private_messages.sender_id IS 'Auth user who sent the message; set to NULL if that account is deleted.';
COMMENT ON COLUMN public.private_messages.created_at IS 'Message creation time; ordering affects last_message_at, pagination and unread status.';
COMMENT ON TABLE public.notifications IS 'Per-user forum reply and private-message notifications; target depends on type.';
COMMENT ON COLUMN public.notifications.type IS 'thread_reply or private_message; see notifications_target_check.';
COMMENT ON COLUMN public.notifications.thread_page IS 'Cached page number for forum replies; may become stale if replies are deleted or reordered.';
COMMENT ON COLUMN public.notifications.reply_id IS 'Forum reply notification target; deleted with its reply.';
COMMENT ON COLUMN public.notifications.message_id IS 'Private message notification target; deleted with its message.';
COMMENT ON COLUMN public.notifications.actor_id IS 'Actor who triggered notification; nullable after auth-user deletion.';
COMMENT ON COLUMN public.notifications.is_read IS 'Notification read state; independent of private_thread_participants.last_read_at.';
COMMENT ON TABLE public.thread_follows IS 'Explicit forum-thread follow subscriptions, used to generate reply notifications.';

COMMENT ON FUNCTION public.forum_create_user_stats() IS 'Initialize per-account forum counters after auth.users insertion; ignore existing entries.';
COMMENT ON FUNCTION public.create_user_profile() IS 'Create/upsert a public profile from auth.users metadata, retaining identity across later auth deletion.';
COMMENT ON FUNCTION public.private_messages_validate_insert() IS 'Require a non-NULL private-message sender who already belongs to the conversation.';
COMMENT ON FUNCTION public.notify_private_message_participants() IS 'After a private message insert, create one notification for each participant other than the sender.';
COMMENT ON FUNCTION public.private_set_updated_at() IS 'Refresh updated_at on private threads and messages whenever they are updated.';
COMMENT ON FUNCTION public.private_messages_after_insert() IS 'Move private_threads.last_message_at forward to the inserted message timestamp.';
COMMENT ON FUNCTION public.private_messages_after_delete() IS 'Recalculate private_threads.last_message_at when a message is deleted, including deletion of the latest message.';
COMMENT ON FUNCTION public.private_messages_protect_fields() IS 'Forbid private message identity/parent/timestamp changes; permit sender_id becoming NULL on auth-user deletion.';
COMMENT ON FUNCTION public.notify_thread_followers() IS 'Create a notification for every thread follower except the reply author; store a 14-replies/page estimate.';
COMMENT ON FUNCTION forum_prepare_forum_insert() IS 'Reset forum aggregate columns to their initial values on insert.';
COMMENT ON FUNCTION forum_set_updated_at() IS 'Maintain updated_at on forum profiles, categories, threads, and replies.';
COMMENT ON FUNCTION forum_prepare_thread_insert() IS 'Require active thread author; initialize reply count and last-post metadata.';
COMMENT ON FUNCTION forum_prevent_thread_relation_changes() IS 'Prevent reparenting/reassigning threads and changes to their creation timestamp; allow author SET NULL on profile deletion.';
COMMENT ON FUNCTION forum_prevent_reply_relation_changes() IS 'Prevent reparenting/reassigning replies and changes to their creation timestamp; allow author SET NULL on profile deletion.';
COMMENT ON FUNCTION forum_validate_reply_insert() IS 'Require every newly inserted reply to reference an active forum profile.';
COMMENT ON FUNCTION forum_guard_forum_denormalized_update() IS 'Reject direct updates of forum cached counts/latest-post metadata; allow nested trigger maintenance.';
COMMENT ON FUNCTION forum_guard_thread_denormalized_update() IS 'Reject direct updates of thread cached counts/latest-post metadata; allow nested trigger maintenance.';
COMMENT ON FUNCTION forum_after_thread_insert() IS 'Update forum latest-post metadata and total messages; increment author message count.';
COMMENT ON FUNCTION forum_sync_thread_title() IS 'Keep cached thread last_post_title synchronized with title during title updates.';
COMMENT ON FUNCTION forum_after_thread_title_update() IS 'Propagate a thread title change into the forum latest-post title when applicable.';
COMMENT ON FUNCTION forum_after_reply_insert() IS 'Increment thread/forum reply counters and update latest-post metadata and author stats.';
COMMENT ON FUNCTION forum_after_reply_delete() IS 'For affected surviving threads/forums, recalculate counters/latest-post metadata and decrement author stats.';
COMMENT ON FUNCTION forum_after_thread_delete() IS 'For affected surviving forums, recalculate totals/latest-post metadata and decrement thread-author stats.';

-- Supabase Auth owns auth.users; COMMENT ON TRIGGER requires relation ownership.
-- COMMENT ON TRIGGER forum_auth_user_created ON auth.users IS 'AFTER INSERT: Create forum_user_stats for the new auth user.';
-- Supabase Auth owns auth.users; COMMENT ON TRIGGER requires relation ownership.
-- COMMENT ON TRIGGER on_auth_user_created ON auth.users IS 'AFTER INSERT: Create the persistent public profile for the new auth user.';
COMMENT ON TRIGGER private_messages_validate_insert ON public.private_messages IS 'BEFORE INSERT: Reject anonymous/new messages from nonparticipants.';
COMMENT ON TRIGGER private_messages_notify_participants ON public.private_messages IS 'AFTER INSERT: Notify all other participants; the sender is excluded.';
COMMENT ON TRIGGER private_threads_set_updated_at ON public.private_threads IS 'BEFORE UPDATE: Refresh private thread updated_at.';
COMMENT ON TRIGGER private_messages_set_updated_at ON public.private_messages IS 'BEFORE UPDATE: Refresh private message updated_at.';
COMMENT ON TRIGGER private_messages_after_insert ON public.private_messages IS 'AFTER INSERT: Track newest private message timestamp in its conversation.';
COMMENT ON TRIGGER private_messages_after_delete ON public.private_messages IS 'AFTER DELETE: Recompute newest private message timestamp after deletion.';
COMMENT ON TRIGGER private_messages_protect_fields ON public.private_messages IS 'BEFORE UPDATE: Preserve immutable fields while allowing sender removal via auth FK.';
COMMENT ON TRIGGER replies_notify_followers ON public.replies IS 'AFTER INSERT: Create thread follower notifications.';
COMMENT ON TRIGGER forums_prepare_insert ON forums IS 'BEFORE INSERT: Initialize zero aggregate state for new forums.';
COMMENT ON TRIGGER profiles_set_updated_at ON public.profiles IS 'BEFORE UPDATE: Refresh public profile updated_at.';
COMMENT ON TRIGGER forums_set_updated_at ON forums IS 'BEFORE UPDATE: Refresh forum updated_at.';
COMMENT ON TRIGGER threads_set_updated_at ON threads IS 'BEFORE UPDATE: Refresh thread updated_at.';
COMMENT ON TRIGGER replies_set_updated_at ON replies IS 'BEFORE UPDATE: Refresh reply updated_at.';
COMMENT ON TRIGGER threads_prepare_insert ON threads IS 'BEFORE INSERT: Check thread author and initialize aggregate state.';
COMMENT ON TRIGGER threads_prevent_relation_changes ON threads IS 'BEFORE UPDATE: Forbid editing thread parent, author or created_at (except author SET NULL).';
COMMENT ON TRIGGER replies_prevent_relation_changes ON replies IS 'BEFORE UPDATE: Forbid editing reply parent, author or created_at (except author SET NULL).';
COMMENT ON TRIGGER replies_validate_insert ON replies IS 'BEFORE INSERT: Require a valid, active author for new replies.';
COMMENT ON TRIGGER forums_guard_denormalized_update ON forums IS 'BEFORE UPDATE: Reject client modifications to cached forum aggregates.';
COMMENT ON TRIGGER threads_guard_denormalized_update ON threads IS 'BEFORE UPDATE: Reject client modifications to cached thread aggregates.';
COMMENT ON TRIGGER threads_after_insert ON threads IS 'AFTER INSERT: Update parent forum and author totals.';
COMMENT ON TRIGGER threads_sync_title ON threads IS 'BEFORE UPDATE: Mirror thread title into its cached last-post title.';
COMMENT ON TRIGGER threads_after_title_update ON threads IS 'AFTER UPDATE: Refresh forum cached title when this thread was most recently active.';
COMMENT ON TRIGGER replies_after_insert ON replies IS 'AFTER INSERT: Update thread/forum latest-post data and counts.';
COMMENT ON TRIGGER replies_after_delete ON replies IS 'AFTER DELETE (statement): Recompute affected thread/forum data using the deleted_replies transition table.';
COMMENT ON TRIGGER threads_after_delete ON threads IS 'AFTER DELETE (statement): Recompute affected forum data using the deleted_threads transition table.';

-- The database consistency triggers do not replace authorization:
-- restrict direct public/private table access and configure Supabase RLS or
-- revoke client-facing PostgREST permissions if all access is through Go.
-- The Go read endpoint should mark matching private_message notifications
-- read when it advances private_thread_participants.last_read_at.

COMMIT;