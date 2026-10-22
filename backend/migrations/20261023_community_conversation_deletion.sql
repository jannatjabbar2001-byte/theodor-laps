BEGIN;

ALTER TABLE public.community_memberships
    ADD COLUMN IF NOT EXISTS hidden_after_message_id INTEGER;

COMMIT;
