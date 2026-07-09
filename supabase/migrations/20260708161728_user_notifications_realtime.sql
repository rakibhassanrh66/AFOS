-- The notification bell (top_app_bar.dart's _NotificationBellState) has
-- always subscribed to realtime changes on user_notifications, but this
-- table was never actually added to the supabase_realtime publication --
-- so that subscription has never once fired. The badge only ever reflected
-- whatever _load() saw at initial mount, which read as "stuck/stale even
-- after marking read." SOS alerts will multiply insert volume into this
-- table, making this fix a prerequisite, not just a bell cosmetic fix.
ALTER PUBLICATION supabase_realtime ADD TABLE user_notifications;
