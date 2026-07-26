-- Needed so the pending-approval screen's realtime subscription on its own
-- profile row (waiting for is_verified to flip true) actually fires —
-- profiles was never added to the realtime publication before now.
ALTER PUBLICATION supabase_realtime ADD TABLE profiles;
