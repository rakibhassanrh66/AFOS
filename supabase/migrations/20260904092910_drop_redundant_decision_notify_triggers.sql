-- REVERTS 20260904085938 ENTIRELY. It was based on a wrong reading.
--
-- That migration added notification triggers to club_membership_requests,
-- cr_requests, hall_applications and mentorship_bookings after finding that
-- none of the four had a trigger of any kind. The conclusion drawn from that
-- -- "the student is never told" -- was wrong. These four are notified from
-- the CLIENT, through NotificationService.sendToUsers -> the send-notification
-- edge function, which writes the user_notifications row and sends the push:
--
--   club approve/reject   clubs_screen.dart:257,287
--                         manage_clubs_screen.dart:108,134
--   hall approve/reject   manage_hall_screen.dart:229,282
--   mentorship verdict    mentorship_screen.dart:366
--   CR approve/reject     manage_users_screen.dart:466,507  (category 'general',
--                         which is why no row carries category 'cr')
--
-- The row counts say the same thing: category 'club' 21, 'hall' 13,
-- 'mentorship' 6. Those notifications have been arriving all along.
--
-- So the triggers were not filling a gap, they were adding a SECOND in-app row
-- for every decision -- the exact fault NotificationService's own doc comment
-- warns about ("Calling sendToUsers for these would insert a SECOND in-app row
-- and show the student the same notification twice"). Dropped before any of
-- them reached a user: they were applied and exercised only inside
-- transactions that rolled back, and no release carrying them was ever
-- published.
--
-- The trigger-owns-the-row + pushToUsers pattern used by offerings, results and
-- marks IS more robust than the client-side send, because it cannot be lost if
-- the client dies mid-flow. Converting these four to it is a real improvement
-- and a deliberate change to eight call sites -- not something to slip into a
-- release as a side effect of a misdiagnosis.

DROP TRIGGER IF EXISTS trg_notify_club_membership_reviewed ON public.club_membership_requests;
DROP TRIGGER IF EXISTS trg_notify_cr_request_reviewed ON public.cr_requests;
DROP TRIGGER IF EXISTS trg_notify_hall_application_reviewed ON public.hall_applications;
DROP TRIGGER IF EXISTS trg_notify_mentorship_booking_reviewed ON public.mentorship_bookings;

DROP FUNCTION IF EXISTS public.notify_club_membership_reviewed();
DROP FUNCTION IF EXISTS public.notify_cr_request_reviewed();
DROP FUNCTION IF EXISTS public.notify_hall_application_reviewed();
DROP FUNCTION IF EXISTS public.notify_mentorship_booking_reviewed();
