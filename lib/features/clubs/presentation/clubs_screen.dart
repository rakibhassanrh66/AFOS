import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_icons.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../config/theme/depth.dart';
import '../../../config/theme/liquid_glass_tokens.dart';
import '../../../config/theme/motion.dart';
import '../../../core/haptics/app_haptics.dart';
import '../../../core/auth/role_session.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../shared/models/user_model.dart';
import '../../../shared/animations/page_transitions.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/afos_text_field.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/glass_sheet.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../../core/services/outbox_service.dart';
import '../../notifications/data/repositories/notification_service.dart';
import '../../shell/presentation/top_app_bar.dart';
import 'club_chat_screen.dart';

import '../../../core/services/realtime_channel.dart';
import '../../../core/layout/nav_insets.dart';
IconData categoryIcon(String? category) => switch (category) {
      'Tech' => Icons.memory_rounded,
      'Sports' => Icons.sports_soccer_rounded,
      'Cultural' => Icons.theater_comedy_rounded,
      'Volunteer' => Icons.volunteer_activism_rounded,
      'Business' => Icons.business_center_rounded,
      'Academic' => Icons.menu_book_rounded,
      _ => AppIcons.clubs,
    };

class ClubsScreen extends StatefulWidget {
  const ClubsScreen({super.key});
  @override State<ClubsScreen> createState() => _ClubsState();
}

class _ClubsState extends State<ClubsScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<Map<String, dynamic>> _clubs = [], _myClubs = [], _events = [];
  List<Map<String, dynamic>> _myMembershipRequests = [], _myPostRequests = [];
  List<Map<String, dynamic>> _presidingRequests = [];
  Set<String> _myEventRegistrations = {};
  UserModel? _user;
  bool _loading = true;
  String? _error;
  String _filter = 'All';
  String _search = '';
  static const _filters = ['All', 'Tech', 'Sports', 'Cultural', 'Volunteer', 'Business', 'Academic'];
  RealtimeChannel? _clubsSub, _membersSub;
  final _refresh = RealtimeRefresh();

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _load();
    _loadUser();
    // ONE debouncer shared by both channels, deliberately: they both call the
    // same `_load()`, so joining a club (which writes `club_members` and bumps
    // the parent `clubs` row) fired two full reloads back to back. Sharing the
    // timer collapses the cross-table burst as well as each table's own.
    _clubsSub = SupabaseConfig.client.channel(screenChannel('clubs_screen_clubs', this))
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'clubs',
            callback: (_) => _refresh.schedule(_load))
        .subscribe();
    _membersSub = SupabaseConfig.client.channel(screenChannel('clubs_screen_members', this))
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'club_members',
            callback: (_) => _refresh.schedule(_load))
        .subscribe();
  }
  @override
  void dispose() {
    _tab.dispose();
    _clubsSub?.unsubscribe();
    _membersSub?.unsubscribe();
    // Cancel any queued refetch, or it fires against an unmounted widget.
    _refresh.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final uid = SupabaseConfig.uid;
    try {
      // Narrowed to what _ClubList's card + _presidentIdFor/_anyClubNameFor
      // lookups actually read — president_id looks unused by the card but
      // is read later via _clubs.firstWhere(...) for the notice/notify flow.
      var q = SupabaseConfig.client.from('clubs')
          .select('id, name, short_name, tagline, category, president_id');
      if (_filter != 'All') q = q.eq('category', _filter);
      final [clubs, events] = await Future.wait([
        q.order('name') as Future,
        SupabaseConfig.client.from('club_events')
            .select('id, title, venue, event_date, max_seats').order('event_date') as Future,
      ]);
      List myClubs = [], myMembershipRequests = [], myPostRequests = [], presidingRequests = [], myRegistrations = [];
      if (uid != null) {
        final results = await Future.wait([
          SupabaseConfig.client.from('club_members').select('*, clubs(*)').eq('member_id', uid) as Future,
          SupabaseConfig.client.from('club_membership_requests').select().eq('student_id', uid).eq('status', 'pending') as Future,
          SupabaseConfig.client.from('club_post_requests').select().eq('member_id', uid).eq('status', 'pending') as Future,
          SupabaseConfig.client.from('event_registrations').select('event_id').eq('student_id', uid) as Future,
        ]);
        myClubs = results[0] as List;
        myMembershipRequests = results[1] as List;
        myPostRequests = results[2] as List;
        myRegistrations = results[3] as List;
        final presidentClubIds = myClubs.cast<Map<String, dynamic>>()
            .where((m) => m['role'] == 'president').map((m) => m['club_id'] as String).toList();
        if (presidentClubIds.isNotEmpty) {
          presidingRequests = await SupabaseConfig.client.from('club_membership_requests')
              .select('*, profiles!student_id(full_name, university_id, avatar_url)')
              .inFilter('club_id', presidentClubIds).eq('status', 'pending') as List;
        }
      }
      if (mounted) {
        setState(() {
        _clubs = (clubs as List).cast();
        _events = (events as List).cast();
        _myClubs = myClubs.cast();
        _myMembershipRequests = myMembershipRequests.cast();
        _myPostRequests = myPostRequests.cast();
        _presidingRequests = presidingRequests.cast();
        _myEventRegistrations = myRegistrations.cast<Map<String, dynamic>>().map((r) => r['event_id'] as String).toSet();
      });
      }
    } catch (e) {
      // Previously swallowed silently — a real load failure rendered
      // identically to "no clubs/events", same class of bug found and
      // fixed elsewhere this session.
      if (mounted) setState(() => _error = friendlyError(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadUser() async {
    final uid = SupabaseConfig.uid;
    if (uid == null) return;
    try {
      final p = await SupabaseConfig.client.from('profiles')
          .select('*, students(batch_label,section)').eq('id', uid).single();
      if (mounted) setState(() => _user = UserModel.fromJson(p));
    } catch (_) {}
  }

  /// Neither the president self-serve approval flow nor these requests
  /// themselves ever notified the president — they only found out about a
  /// pending request by manually opening the My Clubs tab.
  String? _presidentIdFor(String clubId) {
    final club = _clubs.firstWhere((c) => c['id'] == clubId, orElse: () => {});
    return club['president_id'] as String?;
  }

  /// The requesting student isn't a member yet, so _clubNameFor's _myClubs
  /// lookup (built for the president's own perspective) won't have it —
  /// look up from the full discover list instead, which is always loaded.
  String _anyClubNameFor(String clubId) {
    final club = _clubs.firstWhere((c) => c['id'] == clubId, orElse: () => {});
    return club['name'] as String? ?? 'the club';
  }

  Future<void> _requestJoin(String clubId) async {
    try {
      final queued = await OutboxService.instance.submitOrQueue('club_join_request', {
        'club_id': clubId,
        'student_id': SupabaseConfig.uid,
        'president_id': _presidentIdFor(clubId),
        'club_name': _anyClubNameFor(clubId),
      });
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(queued
          ? const SnackBar(content: Text("Saved — will send when you're back online"), backgroundColor: AppColors.amber)
          : const SnackBar(content: Text('Membership requested'), backgroundColor: AppColors.green));
      AppHaptics.success();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
  }

  Future<void> _requestPost(String clubId, String role) async {
    try {
      await SupabaseConfig.client.from('club_post_requests').insert(
          {'club_id': clubId, 'member_id': SupabaseConfig.uid, 'requested_role': role});
      final presidentId = _presidentIdFor(clubId);
      if (presidentId != null) {
        NotificationService.sendToUsers(
          userIds: [presidentId],
          title: 'New post application',
          message: 'A member applied for ${role.replaceAll('_', ' ')} in ${_anyClubNameFor(clubId)}.',
          category: 'club', deepLink: '/clubs',
        );
      }
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Post application submitted'), backgroundColor: AppColors.green));
      AppHaptics.success();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
  }

  Future<void> _registerForEvent(String eventId) async {
    final uid = SupabaseConfig.uid;
    if (uid == null) return;
    try {
      await SupabaseConfig.client.from('event_registrations').insert(
          {'event_id': eventId, 'student_id': uid});
      if (mounted) setState(() => _myEventRegistrations = {..._myEventRegistrations, eventId});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
  }

  final Set<String> _processingRequestIds = {};

  /// approve_club_membership_request/reject_club_membership_request are
  /// plain SQL functions — they can't call OneSignal themselves, so the
  /// notification has to happen here after the RPC succeeds. This was
  /// missing entirely before (the admin-side approval in
  /// manage_clubs_screen.dart already notified; this president self-serve
  /// path silently didn't).
  String _clubNameFor(String clubId) {
    final match = _myClubs.firstWhere((m) => m['club_id'] == clubId, orElse: () => {});
    return (match['clubs'] as Map?)?['name'] as String? ?? 'the club';
  }

  Future<void> _approvePresidingRequest(String requestId) async {
    if (_processingRequestIds.contains(requestId)) return;
    setState(() => _processingRequestIds.add(requestId));
    try {
      final req = _presidingRequests.firstWhere((r) => r['id'] == requestId, orElse: () => {});
      await SupabaseConfig.client.rpc('approve_club_membership_request', params: {'p_request_id': requestId});
      final studentId = req['student_id'] as String?;
      if (studentId != null) {
        await NotificationService.sendToUsers(
          userIds: [studentId],
          title: 'Club membership approved',
          message: 'You are now a member of ${_clubNameFor(req['club_id'] as String? ?? '')}.',
          category: 'club', deepLink: '/clubs',
        );
      }
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Member approved'), backgroundColor: AppColors.green));
      AppHaptics.success();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
    if (mounted) setState(() => _processingRequestIds.remove(requestId));
  }

  Future<void> _rejectPresidingRequest(String requestId) async {
    if (_processingRequestIds.contains(requestId)) return;
    setState(() => _processingRequestIds.add(requestId));
    try {
      final req = _presidingRequests.firstWhere((r) => r['id'] == requestId, orElse: () => {});
      await SupabaseConfig.client.rpc('reject_club_membership_request', params: {'p_request_id': requestId});
      final studentId = req['student_id'] as String?;
      if (studentId != null) {
        await NotificationService.sendToUsers(
          userIds: [studentId],
          title: 'Club membership declined',
          message: 'Your request to join ${_clubNameFor(req['club_id'] as String? ?? '')} was not approved.',
          category: 'club',
        );
      }
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Request rejected'), backgroundColor: AppColors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
    if (mounted) setState(() => _processingRequestIds.remove(requestId));
  }

  Future<void> _sendClubNotice(String clubId, String clubName) async {
    final titleCtrl = TextEditingController();
    final msgCtrl = TextEditingController();
    await showGlassModal(context,
        builder: (sheetCtx) => SingleChildScrollView(
            padding: EdgeInsetsDirectional.fromSTEB(24, 24, 24, MediaQuery.of(sheetCtx).viewInsets.bottom + 24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Notice for $clubName', style: AppTextStyles.headlineLarge.copyWith(color: AppColors.textPrimaryOf(sheetCtx))),
              const SizedBox(height: 16),
              AfosTextField(hint: 'Title', controller: titleCtrl),
              const SizedBox(height: 12),
              AfosTextField(hint: 'Message', controller: msgCtrl, maxLines: 3),
              const SizedBox(height: 20),
              AfosButton(label: 'Send to All Members', onTap: () async {
                if (titleCtrl.text.trim().isEmpty || msgCtrl.text.trim().isEmpty) return;
                // Capture the messenger before popping the sheet + awaiting so
                // no defunct sheet BuildContext is used after the async gap.
                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(sheetCtx);
                final reached = await NotificationService.notifyClub(
                    clubId: clubId, title: titleCtrl.text.trim(), message: msgCtrl.text.trim());
                if (reached == 0) {
                  messenger.showSnackBar(
                      const SnackBar(content: Text('No other members to notify yet — nobody has joined this club besides you.'),
                          backgroundColor: AppColors.amber));
                } else {
                  messenger.showSnackBar(
                      SnackBar(content: Text('Notice sent to $reached member${reached == 1 ? '' : 's'}'), backgroundColor: AppColors.green));
                }
              }),
            ])));
  }

  Future<void> _showCreateEventDialog(String clubId, String clubName) async {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final venueCtrl = TextEditingController();
    final seatsCtrl = TextEditingController();
    DateTime? eventDate;
    DateTime? visibleFrom;
    bool saving = false;

    Future<DateTime?> pickDateTime(BuildContext c, DateTime? initial) async {
      final date = await showDatePicker(context: c, initialDate: initial ?? DateTime.now(),
          firstDate: DateTime.now().subtract(const Duration(days: 1)),
          lastDate: DateTime.now().add(const Duration(days: 730)));
      if (date == null || !c.mounted) return null;
      final time = await showTimePicker(context: c,
          initialTime: initial != null ? TimeOfDay.fromDateTime(initial) : TimeOfDay.now());
      if (time == null) return null;
      return DateTime(date.year, date.month, date.day, time.hour, time.minute);
    }

    await showGlassModal(context,
        builder: (sheetCtx) => StatefulBuilder(builder: (sheetCtx, setSheetState) {
          final textPrimary = AppColors.textPrimaryOf(sheetCtx);
          return SingleChildScrollView(
              padding: EdgeInsetsDirectional.fromSTEB(24, 24, 24, MediaQuery.of(sheetCtx).viewInsets.bottom + 24),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Create Event for $clubName', style: AppTextStyles.headlineLarge.copyWith(color: textPrimary)),
                const SizedBox(height: 16),
                AfosTextField(hint: 'Event title', controller: titleCtrl),
                const SizedBox(height: 12),
                AfosTextField(hint: 'Description', controller: descCtrl, maxLines: 3),
                const SizedBox(height: 12),
                AfosTextField(hint: 'Venue', controller: venueCtrl),
                const SizedBox(height: 12),
                AfosTextField(hint: 'Max seats (optional)', controller: seatsCtrl, keyboardType: TextInputType.number),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_rounded, color: AppColors.pink),
                  title: Text(eventDate == null ? 'Event date & time' : '${eventDate!.day}/${eventDate!.month}/${eventDate!.year} ${eventDate!.hour}:${eventDate!.minute.toString().padLeft(2, '0')}',
                      style: TextStyle(color: textPrimary)),
                  onTap: () async {
                    final picked = await pickDateTime(sheetCtx, eventDate);
                    if (picked != null) setSheetState(() => eventDate = picked);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.visibility_outlined, color: AppColors.pink),
                  title: Text(visibleFrom == null ? 'Visible to everyone: immediately' : 'Visible to everyone from: ${visibleFrom!.day}/${visibleFrom!.month}/${visibleFrom!.year} ${visibleFrom!.hour}:${visibleFrom!.minute.toString().padLeft(2, '0')}',
                      style: TextStyle(color: textPrimary)),
                  subtitle: Text('Club members always see it — this only controls when everyone else can',
                      style: TextStyle(color: AppColors.textSecondaryOf(sheetCtx), fontSize: 11)),
                  onTap: () async {
                    final picked = await pickDateTime(sheetCtx, visibleFrom);
                    if (picked != null) setSheetState(() => visibleFrom = picked);
                  },
                ),
                const SizedBox(height: 20),
                AfosButton(
                  label: 'Create Event',
                  loading: saving,
                  onTap: () async {
                    if (titleCtrl.text.trim().isEmpty || eventDate == null) return;
                    setSheetState(() => saving = true);
                    try {
                      await SupabaseConfig.client.from('club_events').insert({
                        'club_id': clubId, 'created_by': SupabaseConfig.uid,
                        'title': titleCtrl.text.trim(),
                        'description': descCtrl.text.trim(),
                        'event_date': eventDate!.toIso8601String(),
                        'venue': venueCtrl.text.trim(),
                        'max_seats': int.tryParse(seatsCtrl.text.trim()),
                        'visible_from': (visibleFrom ?? DateTime.now()).toIso8601String(),
                      });
                      if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                      _load();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Event created'), backgroundColor: AppColors.green));
                      }
                    } catch (e) {
                      if (sheetCtx.mounted) {
                        ScaffoldMessenger.of(sheetCtx).showSnackBar(
                          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
                      }
                      setSheetState(() => saving = false);
                    }
                  },
                ),
              ]));
        }));
  }

  void _showPostDialog(BuildContext ctx, String clubId, String currentRole) {
    // Faculty apply to supervise; students stand for the elected officer
    // posts. Offering one combined list would let a student apply to be a
    // supervisor, which is a staff appointment, and a teacher to stand for
    // president, which is a student one.
    final isTeacher = RoleSession.role == 'teacher';
    final options = (isTeacher
            ? ['supervisor', 'assistant_supervisor']
            : ['secretary', 'vice_president', 'president'])
        .where((r) => r != currentRole)
        .toList();
    showGlassModal(ctx,
        builder: (sheetCtx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(padding: const EdgeInsets.all(16),
              child: Text(isTeacher ? 'Apply to supervise this club' : 'Apply for a post',
              style: AppTextStyles.titleLarge.copyWith(color: AppColors.textPrimaryOf(sheetCtx)))),
          ...options.map((r) => ListTile(
              title: Text(r.replaceAll('_', ' ').toUpperCase()),
              onTap: () { Navigator.pop(sheetCtx); _requestPost(clubId, r); })),
          const SizedBox(height: 8),
        ])));
  }

  List<Map<String, dynamic>> get _searchFiltered {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return _clubs;
    // Match the abbreviation too — searching "CPC" or "DC" is the whole point
    // of having short names, and it would be odd for the badge on the card to
    // be the one thing search can't find.
    return _clubs.where((c) =>
        (c['name'] as String? ?? '').toLowerCase().contains(q) ||
        (c['short_name'] as String? ?? '').toLowerCase().contains(q)).toList();
  }

  Widget _errorView(BuildContext context) =>
      ErrorView(message: _error ?? 'Something went wrong', onRetry: _load);

  @override
  Widget build(BuildContext context) {
    final pendingClubIds = _myMembershipRequests.map((r) => r['club_id'] as String).toSet();
    final pendingPostClubIds = _myPostRequests.map((r) => r['club_id'] as String).toSet();
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const AfosAppBar(title: 'Clubs'),
      body: Column(children: [
        Container(color: AppColors.surfaceOf(context), child: TabBar(controller: _tab,
            labelColor: AppColors.blue, unselectedLabelColor: AppColors.textSecondaryOf(context),
            indicatorColor: AppColors.blue,
            tabs: const [Tab(text: 'Discover'), Tab(text: 'My Clubs'), Tab(text: 'Events')])),
        Expanded(child: TabBarView(controller: _tab, children: [
          Column(children: [
            Padding(padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 8), child: TextField(
                onChanged: (v) => setState(() => _search = v),
                style: TextStyle(color: AppColors.textPrimaryOf(context)),
                decoration: InputDecoration(hintText: 'Search clubs', prefixIcon: const Icon(Icons.search_rounded),
                    filled: true, fillColor: AppColors.glassFill(context),
                    border: OutlineInputBorder(borderRadius: AppDepth.radius(1), borderSide: BorderSide.none)))),
            _FilterBar(selected: _filter, filters: _filters,
                onSelect: (f) { setState(() => _filter = f); _load(); }),
            Expanded(child: _loading
                ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList(count: 5, itemHeight: 120))
                : _error != null ? _errorView(context)
                : _ClubList(clubs: _searchFiltered, myClubs: _myClubs, pendingClubIds: pendingClubIds,
                    pendingPostClubIds: pendingPostClubIds, onJoin: _requestJoin,
                    onApplyPost: (clubId, role) => _showPostDialog(context, clubId, role))),
          ]),
          _loading ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList())
              : _error != null ? _errorView(context)
              : _MyClubsTab(myClubs: _myClubs, pendingPostClubIds: pendingPostClubIds,
                  presidingRequests: _presidingRequests, processingRequestIds: _processingRequestIds,
                  onApplyPost: (clubId, role) => _showPostDialog(context, clubId, role),
                  onSendNotice: _sendClubNotice, user: _user,
                  onCreateEvent: _showCreateEventDialog,
                  onApproveRequest: _approvePresidingRequest, onRejectRequest: _rejectPresidingRequest),
          _loading ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList())
              : _error != null ? _errorView(context)
              : _EventsTab(events: _events, registeredIds: _myEventRegistrations, onRegister: _registerForEvent),
        ])),
      ]),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final String selected; final List<String> filters; final ValueChanged<String> onSelect;
  const _FilterBar({required this.selected, required this.filters, required this.onSelect});
  @override
  Widget build(BuildContext context) => Container(
    // Was a razor-thin fixed 48px: the ListView's own 8px top+bottom padding
    // plus each chip's 6px top+bottom padding plus real (Google Fonts, not
    // system default) line-height metrics add up to ~51px, tipping over by
    // a few pixels depending on the exact font metrics measured at runtime
    // -- confirmed live via integration_test (RenderFlex overflowed by 3.2
    // pixels on the bottom). 56px gives real margin instead of a coincidental
    // near-fit.
    height: 56, color: AppColors.surfaceOf(context),
    child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: filters.map((f) {
          final sel = selected == f;
          return Padding(padding: const EdgeInsetsDirectional.only(end: 8),
              child: GestureDetector(onTap: () => onSelect(f),
                  child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      // This chip is a direct child of a horizontally-
                      // scrolling ListView -- unlike Row/Column (which
                      // center children on the cross axis by default),
                      // ListView's sliver layout stretches each item to the
                      // viewport's full cross-axis extent (its 56px height,
                      // minus the ListView's own 8+8px padding). Without an
                      // explicit alignment, this Container's padding only
                      // insets from the top, leaving the real cause of what
                      // looked like a font-metrics issue: dead, unfilled
                      // space below the text with nothing pushing it down
                      // to center. Every other badge in the app sits inside
                      // a Row/Wrap instead, which is why only this specific
                      // filter-chip row showed the symptom.
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: sel ? null : AppColors.surfaceOf(context),
                          gradient: sel ? AppColors.pinkGradient : null,
                          borderRadius: AppDepth.radius(2),
                          border: Border.all(color: sel ? Colors.transparent : AppColors.borderOf(context), width: 0.5)),
                      child: Text(f, textHeightBehavior: const TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
                          style: TextStyle(color: sel ? Colors.white : AppColors.textSecondaryOf(context),
                          fontSize: 12, height: 1.0, fontWeight: sel ? FontWeight.w600 : FontWeight.normal)))));
        }).toList()),
  );
}

class _ClubList extends StatelessWidget {
  final List<Map<String, dynamic>> clubs, myClubs;
  final Set<String> pendingClubIds;
  /// Clubs this user already has a pending post application for. Supervisors
  /// apply from THIS tab rather than My Clubs, because a faculty supervisor is
  /// normally not a member of the club they supervise and so never appears
  /// there — which is why the request had nowhere to start from before.
  final Set<String> pendingPostClubIds;
  final ValueChanged<String> onJoin;
  final void Function(String clubId, String currentRole) onApplyPost;
  const _ClubList({required this.clubs, required this.myClubs, required this.pendingClubIds,
      required this.pendingPostClubIds, required this.onJoin, required this.onApplyPost});
  @override
  Widget build(BuildContext context) {
    if (clubs.isEmpty) return const EmptyState(icon: AppIcons.clubs, title: 'No clubs found', subtitle: 'Check back later');
    final joinedIds = myClubs.map((m) => m['club_id'] as String? ?? '').toSet();
    final canJoin = RoleSession.role == 'student';
    return ListView.builder(padding: EdgeInsetsDirectional.fromSTEB(16, 16, 16, 16 + NavInsets.of(context)), itemCount: clubs.length,
        // Guarded by the `if (clubs.isEmpty) return EmptyState(...)`
        // early-return above, so .first is safe. The index only drives the
        // stagger fade-in delay, not row height, so 0 is fine for the
        // prototype's one-off measurement.
        prototypeItem: _buildClubCard(context, clubs.first, 0, joinedIds, canJoin),
        itemBuilder: (ctx, i) => _buildClubCard(ctx, clubs[i], i, joinedIds, canJoin));
  }

  Widget _buildClubCard(BuildContext ctx, Map<String, dynamic> c, int i, Set<String> joinedIds, bool canJoin) {
    final clubId = c['id'] as String?;
    final joined = joinedIds.contains(clubId);
    final pending = pendingClubIds.contains(clubId);
    return Container(margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
            color: AppColors.surfaceOf(ctx), borderRadius: AppDepth.radius(2),
            border: Border.all(color: AppColors.pink.withValues(alpha: 0.25), width: 0.8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(height: 80, decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [AppColors.pink.withValues(alpha: 0.18), AppColors.teal.withValues(alpha: 0.12)]),
              // Sits on the card's top edge, so it takes the card's own
              // corners — three large, top-right cut. Same shape as the lost &
              // found photo header and the exam-seat accent bar.
              borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(LiquidGlass.radiusCard),
                  topRight: Radius.circular(LiquidGlass.radiusCut))),
              child: Center(child: Icon(categoryIcon(c['category'] as String?), color: AppColors.pink, size: 36))),
          Padding(padding: const EdgeInsets.all(14), child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Short form leads, full proper name stays underneath — 55 clubs
              // whose names nearly all begin "DIU …" were indistinguishable at
              // a glance when only the full name was shown.
              Row(children: [
                if ((c['short_name'] as String?)?.isNotEmpty == true)
                  Container(
                      margin: const EdgeInsetsDirectional.only(end: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: AppColors.pink.withValues(alpha: 0.16),
                          borderRadius: AppDepth.radius(0)),
                      child: Text(c['short_name'] as String,
                          textHeightBehavior: const TextHeightBehavior(
                              applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
                          style: const TextStyle(
                              color: AppColors.pink, fontSize: 12, height: 1.0,
                              fontWeight: FontWeight.w800, letterSpacing: 0.3))),
                Flexible(
                  child: Text(c['name'] ?? '',
                      style: AppTextStyles.titleLarge.copyWith(color: AppColors.textPrimaryOf(ctx)),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ]),
              const SizedBox(height: 3),
              Text(c['tagline'] ?? '', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(ctx)), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 6),
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.pink.withValues(alpha: 0.1), borderRadius: AppDepth.radius(0)),
                  child: Text(c['category'] ?? '', textHeightBehavior: const TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
                      style: const TextStyle(color: AppColors.pink, fontSize: 11, height: 1.0, fontWeight: FontWeight.w600))),
            ])),
            const SizedBox(width: 12),
            // Faculty get "Supervise" where a student gets "Join" — the two
            // are mutually exclusive, and a teacher had no entry point at all
            // before this.
            if (RoleSession.role == 'teacher' && clubId != null)
              _SuperviseButton(
                pending: pendingPostClubIds.contains(clubId),
                onTap: () => onApplyPost(clubId, ''),
              )
            else if (canJoin || joined)
              GestureDetector(onTap: (joined || pending || clubId == null) ? null : () => onJoin(clubId),
                  child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                          color: joined ? AppColors.green.withValues(alpha: 0.1)
                              : pending ? AppColors.amber.withValues(alpha: 0.1) : null,
                          gradient: (joined || pending) ? null : AppColors.pinkGradient,
                          borderRadius: AppDepth.radius(2)),
                      child: Text(joined ? 'Joined' : pending ? 'Pending' : 'Join',
                          textHeightBehavior: const TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
                          style: TextStyle(color: joined ? AppColors.green : pending ? AppColors.amber : Colors.white,
                              fontSize: 13, height: 1.0, fontWeight: FontWeight.w600)))),
          ])),
        ])).animate(delay: AppMotion.staggerFor(ctx, i)).fadeIn().slideY(begin: 0.05);
  }
}

/// Faculty-facing counterpart to the student "Join" button on a club card.
class _SuperviseButton extends StatelessWidget {
  final bool pending;
  final VoidCallback onTap;
  const _SuperviseButton({required this.pending, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = pending ? AppColors.amber : AppColors.teal;
    return GestureDetector(
      onTap: pending ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: AppDepth.radius(0),
          border: Border.all(color: color.withValues(alpha: 0.4), width: 0.8),
        ),
        child: Text(pending ? 'Requested' : 'Supervise',
            textHeightBehavior: const TextHeightBehavior(
                applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
            style: TextStyle(
                color: color, fontSize: 12, height: 1.0, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _MyClubsTab extends StatelessWidget {
  final List<Map<String, dynamic>> myClubs;
  final Set<String> pendingPostClubIds;
  final List<Map<String, dynamic>> presidingRequests;
  final Set<String> processingRequestIds;
  final void Function(String clubId, String currentRole) onApplyPost;
  final void Function(String clubId, String clubName) onSendNotice;
  final void Function(String clubId, String clubName) onCreateEvent;
  final ValueChanged<String> onApproveRequest;
  final ValueChanged<String> onRejectRequest;
  final UserModel? user;
  const _MyClubsTab({required this.myClubs, required this.pendingPostClubIds,
      required this.presidingRequests, required this.processingRequestIds,
      required this.onApplyPost, required this.onSendNotice, this.user,
      required this.onCreateEvent,
      required this.onApproveRequest, required this.onRejectRequest});
  @override
  Widget build(BuildContext context) {
    if (myClubs.isEmpty) {
      return const EmptyState(icon: Icons.group_add_rounded,
        title: 'No clubs joined', subtitle: 'Discover and request to join clubs from the Discover tab');
    }
    return ListView.builder(padding: EdgeInsetsDirectional.fromSTEB(16, 16, 16, 16 + NavInsets.of(context)), itemCount: myClubs.length,
        itemBuilder: (ctx, i) {
          final m = myClubs[i];
          final club = m['clubs'] as Map<String, dynamic>? ?? {};
          final clubId = m['club_id'] as String? ?? '';
          final clubName = club['name'] as String? ?? 'Club';
          final role = m['role'] as String? ?? 'member';
          final isPresident = role == 'president';
          final hasPendingPost = pendingPostClubIds.contains(clubId);
          final myPendingRequests = presidingRequests.where((r) => r['club_id'] == clubId).toList();
          return Container(margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: AppDepth.radius(1),
                  border: Border.all(color: AppColors.borderOf(context), width: 0.5)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(width: 44, height: 44, decoration: BoxDecoration(
                      color: AppColors.pink.withValues(alpha: 0.15), borderRadius: AppDepth.radius(0)),
                      child: Icon(categoryIcon(club['category'] as String?), color: AppColors.pink, size: 24)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(club['name'] ?? '', style: AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimaryOf(context)), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(club['category'] ?? '', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(context)), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ])),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: (isPresident ? AppColors.gold : AppColors.blue).withValues(alpha: 0.1), borderRadius: AppDepth.radius(0)),
                      child: Text(role.replaceAll('_', ' ').toUpperCase(),
                          textHeightBehavior: const TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
                          style: TextStyle(color: isPresident ? AppColors.gold : AppColors.blue, fontSize: 10, height: 1.0, fontWeight: FontWeight.w700))),
                  if (user != null)
                    IconButton(icon: const Icon(Icons.chat_bubble_outline_rounded, color: AppColors.pink, size: 20),
                        onPressed: () => Navigator.push(context,
                            appPageRoute(ClubChatScreen(clubId: clubId, clubName: clubName, user: user!)))),
                ]),
                const SizedBox(height: 10),
                if (isPresident) ...[
                  SizedBox(width: double.infinity, child: OutlinedButton.icon(
                      onPressed: () => onSendNotice(clubId, club['name'] ?? 'Club'),
                      icon: const Icon(Icons.campaign_outlined, size: 16),
                      label: const Text('Send Club Notice'))),
                  const SizedBox(height: 8),
                  SizedBox(width: double.infinity, child: OutlinedButton.icon(
                      onPressed: () => onCreateEvent(clubId, club['name'] ?? 'Club'),
                      icon: const Icon(Icons.event_rounded, size: 16),
                      label: const Text('Create Event'))),
                ] else if (hasPendingPost)
                  const Text('Post application pending approval', style: TextStyle(color: AppColors.amber, fontSize: 12))
                else
                  SizedBox(width: double.infinity, child: OutlinedButton(
                      onPressed: () => onApplyPost(clubId, role),
                      child: const Text('Apply for a Post'))),
                if (isPresident && myPendingRequests.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text('Pending Membership Requests (${myPendingRequests.length})',
                      style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondaryOf(context), fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  ...myPendingRequests.map((r) {
                    final requestId = r['id'] as String;
                    final student = r['profiles'] as Map<String, dynamic>? ?? {};
                    final busy = processingRequestIds.contains(requestId);
                    return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: AppColors.glassFill(context), borderRadius: AppDepth.radius(0)),
                        child: Row(children: [
                          CircleAvatar(radius: 16, backgroundColor: AppColors.pink.withValues(alpha: 0.15),
                              backgroundImage: (student['avatar_url'] as String?)?.isNotEmpty == true
                                  ? CachedNetworkImageProvider(student['avatar_url'], maxWidth: 128, maxHeight: 128) : null,
                              child: (student['avatar_url'] as String?)?.isNotEmpty != true
                                  ? Text(((student['full_name'] as String?)?.isNotEmpty == true ? (student['full_name'] as String)[0] : '?').toUpperCase(),
                                      style: const TextStyle(color: AppColors.pink, fontWeight: FontWeight.bold, fontSize: 12))
                                  : null),
                          const SizedBox(width: 10),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(student['full_name'] ?? 'Unknown', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimaryOf(context)), maxLines: 1, overflow: TextOverflow.ellipsis),
                            if ((student['university_id'] as String?)?.isNotEmpty == true)
                              Text(student['university_id'], style: TextStyle(color: AppColors.textSecondaryOf(context), fontSize: 11)),
                          ])),
                          if (busy)
                            const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                          else ...[
                            IconButton(icon: const Icon(Icons.check_circle_outline, color: AppColors.green, size: 22),
                                onPressed: () => onApproveRequest(requestId)),
                            IconButton(icon: const Icon(Icons.cancel_outlined, color: AppColors.red, size: 22),
                                onPressed: () => onRejectRequest(requestId)),
                          ],
                        ]));
                  }),
                ],
              ]));
        });
  }
}

class _EventsTab extends StatelessWidget {
  final List<Map<String, dynamic>> events;
  final Set<String> registeredIds;
  final ValueChanged<String> onRegister;
  const _EventsTab({required this.events, required this.registeredIds, required this.onRegister});
  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const EmptyState(icon: Icons.event_rounded,
        title: 'No upcoming events', subtitle: 'Events will appear here');
    }
    return ListView.builder(padding: EdgeInsetsDirectional.fromSTEB(16, 16, 16, 16 + NavInsets.of(context)), itemCount: events.length,
        itemBuilder: (ctx, i) {
          final e = events[i];
          final eventId = e['id'] as String?;
          final date = e['event_date'] != null ? DateTime.tryParse(e['event_date']) : null;
          final registered = eventId != null && registeredIds.contains(eventId);
          return Container(margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: AppDepth.radius(1),
                  border: Border.all(color: AppColors.borderOf(context), width: 0.5)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(width: 48, height: 56, decoration: BoxDecoration(
                      color: AppColors.indigo.withValues(alpha: 0.15), borderRadius: AppDepth.radius(0)),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text(date != null ? '${date.day}' : '?',
                            style: const TextStyle(color: AppColors.indigo, fontSize: 18, fontWeight: FontWeight.w800)),
                        Text(date != null ? _month(date.month) : '',
                            style: const TextStyle(color: AppColors.indigo, fontSize: 10)),
                      ])),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(e['title'] ?? '', style: AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimaryOf(context)), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(e['venue'] ?? '', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(context)), maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (e['max_seats'] != null) Text('${e['max_seats']} seats',
                        style: TextStyle(color: AppColors.textSecondaryOf(context), fontSize: 11)),
                  ])),
                ]),
                if (eventId != null) ...[
                  const SizedBox(height: 10),
                  SizedBox(width: double.infinity, child: OutlinedButton(
                      onPressed: registered ? null : () => onRegister(eventId),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: registered ? AppColors.green : AppColors.indigo,
                          side: BorderSide(color: registered ? AppColors.green : AppColors.indigo),
                          minimumSize: const Size(0, 40)),
                      child: Text(registered ? 'Joined' : 'Join / Visit'))),
                ],
              ]));
        });
  }
  String _month(int m) => ['','Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][m];
}
