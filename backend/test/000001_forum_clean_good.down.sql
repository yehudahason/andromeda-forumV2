-- Forum schema - full DOWN migration
-- Reverses 000001_forum_clean.up.sql.

BEGIN;

-- Drop forum tables in dependency order.
DROP TABLE IF EXISTS replies CASCADE;
DROP TABLE IF EXISTS threads CASCADE;
DROP TABLE IF EXISTS forums CASCADE;

-- Drop functions created by the UP migration.
DROP FUNCTION IF EXISTS forum_after_thread_delete CASCADE;
DROP FUNCTION IF EXISTS forum_after_reply_delete CASCADE;
DROP FUNCTION IF EXISTS forum_after_reply_insert CASCADE;
DROP FUNCTION IF EXISTS forum_after_thread_title_update CASCADE;
DROP FUNCTION IF EXISTS forum_sync_thread_title CASCADE;
DROP FUNCTION IF EXISTS forum_after_thread_insert CASCADE;
DROP FUNCTION IF EXISTS forum_guard_thread_denormalized_update CASCADE;
DROP FUNCTION IF EXISTS forum_guard_forum_denormalized_update CASCADE;
DROP FUNCTION IF EXISTS forum_validate_reply_insert CASCADE;
DROP FUNCTION IF EXISTS forum_prevent_reply_relation_changes CASCADE;
DROP FUNCTION IF EXISTS forum_prevent_thread_relation_changes CASCADE;
DROP FUNCTION IF EXISTS forum_prepare_thread_insert CASCADE;
DROP FUNCTION IF EXISTS forum_set_updated_at CASCADE;
DROP FUNCTION IF EXISTS forum_prepare_forum_insert CASCADE;

-- Remove columns added to the existing auth user table.
ALTER TABLE neon_auth."user" DROP COLUMN IF EXISTS replies_count CASCADE;

COMMIT;
