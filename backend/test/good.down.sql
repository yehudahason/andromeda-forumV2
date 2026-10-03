-- =========================================================
-- COMBINED FORUM MIGRATION - DOWN
-- Reverts the complete combined forum migration.
-- =========================================================

BEGIN;

-- Drop forum/reply/thread triggers first.
DROP TRIGGER IF EXISTS replies_after_delete ON replies;
DROP TRIGGER IF EXISTS replies_after_insert ON replies;
DROP TRIGGER IF EXISTS replies_prepare_insert ON replies;
DROP TRIGGER IF EXISTS replies_guard_immutable_update ON replies;

DROP TRIGGER IF EXISTS threads_after_delete ON threads;
DROP TRIGGER IF EXISTS threads_after_insert ON threads;
DROP TRIGGER IF EXISTS threads_prepare_insert ON threads;
DROP TRIGGER IF EXISTS threads_guard_denormalized_update ON threads;
DROP TRIGGER IF EXISTS threads_guard_immutable_update ON threads;

DROP TRIGGER IF EXISTS forums_prepare_insert ON forums;
DROP TRIGGER IF EXISTS forums_guard_denormalized_update ON forums;

-- Drop tables in dependency order.
DROP TABLE IF EXISTS replies CASCADE;
DROP TABLE IF EXISTS threads CASCADE;
DROP TABLE IF EXISTS forums CASCADE;

-- Drop forum migration functions.
DROP FUNCTION IF EXISTS forum_after_reply_delete();
DROP FUNCTION IF EXISTS forum_after_reply_insert();
DROP FUNCTION IF EXISTS forum_prepare_reply_insert();
DROP FUNCTION IF EXISTS forum_guard_reply_immutable_update();

DROP FUNCTION IF EXISTS forum_after_thread_delete();
DROP FUNCTION IF EXISTS forum_after_thread_insert();
DROP FUNCTION IF EXISTS forum_prepare_thread_insert();
DROP FUNCTION IF EXISTS forum_guard_thread_denormalized_update();
DROP FUNCTION IF EXISTS forum_guard_thread_immutable_update();

DROP FUNCTION IF EXISTS forum_prepare_forum_insert();
DROP FUNCTION IF EXISTS forum_guard_forum_denormalized_update();
DROP FUNCTION IF EXISTS update_updated_at_column();

-- Remove the column added to the existing Neon Auth user table.
ALTER TABLE neon_auth."user"
    DROP COLUMN IF EXISTS replies_count;

COMMIT;
