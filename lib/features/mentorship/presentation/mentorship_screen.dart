import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_icons.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/auth/role_session.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../../shared/widgets/afos_text_field.dart';
import '../../../core/services/outbox_service.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../notifications/data/repositories/notification_service.dart';
import '../../shell/presentation/top_app_bar.dart';

class MentorshipScreen extends StatefulWidget {
  const MentorshipScreen({super.key});
  @override State<MentorshipScreen> createState() => _MentorshipState();
}

class _MentorshipState extends State<MentorshipScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<Map<String, dynamic>> _mentors = [], _sessions = [], _incomingRequests = [], _allBookings = [];
  Map<String, dynamic>? _myMentorProfile;
  bool _loading = true;
  String? _error;
  bool get _isTeacher => RoleSession.role == 'teacher';
  // Super admin never mentors or books sessions themselves — they get a
  // read-only oversight view (every pairing across the system) plus the
  // power to ban a mentor, never a participant role like everyone else.
  bool get _isSuperAdmin => RoleSession.role == 'super_admin';
  bool get _isStudent => RoleSession.role == 'student';

  @override
  void initState() { super.initState(); _tab = TabController(length: 2, vsync: this); _load(); }
  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      if (_isSuperAdmin) {
        final res = await SupabaseConfig.client.from('mentorship_bookings')
            .select('*, profiles!student_id(full_name, department), mentors(*, profiles(full_name, department))')
            .order('created_at', ascending: false) as List;
        if (mounted) setState(() => _allBookings = res.cast());
      } else if (_isTeacher) {
        // A mentorship request is only ever visible/actionable by the
        // specific teacher it was addressed to (mentor_id) — never a
        // roster of every teacher's requests — matching the RLS policy
        // on mentorship_bookings which scopes rows the same way.
        final results = await Future.wait([
          SupabaseConfig.client.from('mentorship_bookings')
              .select('*, profiles!student_id(full_name, department, avatar_url)')
              .eq('mentor_id', SupabaseConfig.uid ?? '').order('created_at', ascending: false) as Future,
          SupabaseConfig.client.from('mentors').select().eq('id', SupabaseConfig.uid ?? '').maybeSingle() as Future,
        ]);
        if (mounted) {
          setState(() {
          _incomingRequests = (results[0] as List).cast();
          _myMentorProfile = results[1] as Map<String, dynamic>?;
        });
        }
      } else {
        // Only show mentors relevant to this student — never expose the
        // whole faculty roster. Matched by department for now (the
        // mentors/teachers schema doesn't yet record per-semester/course
        // availability, so that's as fine-grained as this can go today).
        final myProfile = await SupabaseConfig.client.from('profiles')
            .select('department').eq('id', SupabaseConfig.uid ?? '').maybeSingle();
        final myDept = myProfile?['department'] as String?;

        var mentorsQuery = SupabaseConfig.client.from('mentors')
            .select('*, profiles!inner(full_name,avatar_url,department)');
        if (myDept != null && myDept.isNotEmpty) {
          mentorsQuery = mentorsQuery.eq('profiles.department', myDept);
        }

        final results = await Future.wait([
          mentorsQuery as Future,
          SupabaseConfig.client.from('mentorship_bookings').select('*, mentors(*, profiles(full_name))')
              .eq('student_id', SupabaseConfig.uid ?? '').order('created_at', ascending: false) as Future,
        ]);
        if (mounted) {
          setState(() {
          _mentors = (results[0] as List).cast();
          _sessions = (results[1] as List).cast();
        });
        }
      }
    } catch (e) {
      // Previously swallowed silently — a load failure (network blip, a
      // stale session, a real RLS gap) rendered identically to "no mentor
      // profile"/"no mentors yet", which is very likely what was actually
      // behind the long-standing "mentorship profile missing" report:
      // there was never any signal to tell a genuine failure apart from a
      // truthful empty state.
      if (mounted) setState(() => _error = friendlyError(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  Widget _errorView(BuildContext context) => Center(child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline_rounded, color: AppColors.red, size: 40),
        const SizedBox(height: 12),
        Text('Couldn\'t load: $_error', textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondaryOf(context))),
        const SizedBox(height: 12),
        TextButton(onPressed: _load, child: const Text('Retry')),
      ])));

  Widget _heroHeader(BuildContext context, {required String title, required String subtitle, required IconData icon}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [AppColors.blueLight, AppColors.blue]),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(children: [
          Container(padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), shape: BoxShape.circle),
              child: Icon(icon, color: Colors.white, size: 24)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: AppTextStyles.titleLarge.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text(subtitle, style: AppTextStyles.bodyMedium.copyWith(color: Colors.white.withValues(alpha: 0.9))),
          ])),
        ]),
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.06, curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    if (_isSuperAdmin) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: const AfosAppBar(title: 'Mentorship Oversight'),
        body: Column(children: [
          _heroHeader(context, title: 'Mentorship Oversight', icon: Icons.visibility_rounded,
              subtitle: _loading ? 'Loading…' : '${_allBookings.length} bookings across the system'),
          Expanded(child: _loading
              ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList())
              : _error != null
                  ? _errorView(context)
                  : _OversightTab(bookings: _allBookings, onRefresh: _load)),
        ]),
      );
    }
    if (!_isTeacher && !_isStudent) {
      // admin/dept_admin/staff/exam_controller previously fell through to
      // the student "Find Mentor"/"My Sessions" view (always empty) —
      // mentorship is only ever relevant to students/teachers/super_admin
      // (oversight), matching schedule_screen.dart's not-applicable pattern.
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: const AfosAppBar(title: 'Mentorship'),
        body: const EmptyState(icon: AppIcons.mentorship, title: 'Not applicable for your role',
            subtitle: 'Mentorship is for students and teachers only'),
      );
    }
    final tabLabels = _isTeacher ? const ['Requests', 'My Profile'] : const ['Find Mentor', 'My Sessions'];
    final tabIcons = _isTeacher
        ? const [Icons.inbox_rounded, Icons.badge_rounded]
        : const [Icons.explore_rounded, Icons.event_available_rounded];
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const AfosAppBar(title: 'Mentorship'),
      body: Column(children: [
        _heroHeader(context, title: 'Mentorship', icon: AppIcons.mentorship,
            subtitle: _isTeacher
                ? (_loading ? 'Loading…' : '${_incomingRequests.length} requests received')
                : (_loading ? 'Loading…' : '${_mentors.length} mentors available')),
        AnimatedBuilder(
          animation: _tab,
          builder: (ctx, _) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: List.generate(tabLabels.length, (i) {
              final sel = _tab.index == i;
              return Expanded(child: GestureDetector(
                onTap: () => _tab.animateTo(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                      gradient: sel ? const LinearGradient(colors: [AppColors.blueLight, AppColors.blue]) : null,
                      color: sel ? null : AppColors.glassFill(context),
                      borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(tabIcons[i], size: 16, color: sel ? Colors.white : AppColors.textSecondaryOf(context)),
                    const SizedBox(width: 6),
                    Text(tabLabels[i],
                        textHeightBehavior: const TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
                        style: TextStyle(color: sel ? Colors.white : AppColors.textSecondaryOf(context),
                            fontSize: 12.5, height: 1.0, fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
                  ]),
                ),
              ));
            })),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(child: _error != null
            ? _errorView(context)
            : TabBarView(controller: _tab, children: _isTeacher
                ? [
                    _loading ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList())
                        : _IncomingRequestsTab(requests: _incomingRequests, onRefresh: _load),
                    _loading ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList(count: 1, itemHeight: 260))
                        : _MyMentorProfileTab(profile: _myMentorProfile, onSaved: _load),
                  ]
                : [
                    _loading ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList(count: 4, itemHeight: 130))
                        : _MentorList(mentors: _mentors, onBook: (m) => _showBookingDialog(context, m)),
                    _loading ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList())
                        : _SessionsTab(sessions: _sessions, onRefresh: _load),
                  ])),
      ]),
    );
  }

  void _showBookingDialog(BuildContext ctx, Map<String, dynamic> mentor) {
    final topicCtrl = TextEditingController();
    showModalBottomSheet(context: ctx, isScrollControlled: true,
        backgroundColor: AppColors.surfaceOf(ctx),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (_) => SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Book Session', style: AppTextStyles.headlineLarge.copyWith(color: AppColors.textPrimaryOf(ctx))),
              const SizedBox(height: 6),
              Text('with ${(mentor['profiles'] as Map?)?['full_name'] ?? ''}',
                  style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(ctx))),
              const SizedBox(height: 20),
              AfosTextField(hint: 'What topic do you need help with?', controller: topicCtrl, maxLines: 3),
              const SizedBox(height: 16),
              AfosButton(label: 'Request Session', onTap: () async {
                if (topicCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx);
                try {
                  final queued = await OutboxService.instance.submitOrQueue('mentorship_booking_request', {
                    'student_id': SupabaseConfig.uid,
                    'mentor_id': mentor['id'],
                    'topic': topicCtrl.text.trim(),
                  });
                  _load();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(queued
                      ? const SnackBar(content: Text("Saved — will send when you're back online"), backgroundColor: AppColors.amber)
                      : const SnackBar(content: Text('Session requested ✓'), backgroundColor: AppColors.green));
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
                  }
                }
              }),
            ])));
  }
}

class _MentorList extends StatelessWidget {
  final List<Map<String, dynamic>> mentors;
  final ValueChanged<Map<String, dynamic>> onBook;
  const _MentorList({required this.mentors, required this.onBook});

  @override
  Widget build(BuildContext context) {
    if (mentors.isEmpty) {
      return const EmptyState(icon: AppIcons.mentorship,
        title: 'No mentors available', subtitle: 'Mentors will appear here once faculty register');
    }
    return ListView.builder(padding: const EdgeInsets.all(16), itemCount: mentors.length,
        itemBuilder: (ctx, i) {
          final m = mentors[i];
          final profile = m['profiles'] as Map<String, dynamic>? ?? {};
          final specs = (m['specializations'] as List?)?.cast<String>() ?? [];
          return Container(margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.borderOf(context), width: 0.5)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(width: 56, height: 56, decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                        colors: [AppColors.blueLight, AppColors.blue]),
                    boxShadow: [BoxShadow(color: AppColors.blue.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 3))]),
                    child: const Center(child: Icon(Icons.person_rounded, color: Colors.white, size: 28))),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(profile['full_name'] ?? '', style: AppTextStyles.titleLarge.copyWith(color: AppColors.textPrimaryOf(context)), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(m['title'] ?? '', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(context)), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(profile['department'] ?? '', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(context)), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 8),
                  if (specs.isNotEmpty) Wrap(spacing: 6, runSpacing: 4, children: specs.map((s) =>
                      Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: AppColors.blue.withValues(alpha:0.1), borderRadius: BorderRadius.circular(10)),
                          child: Text(s, style: const TextStyle(color: AppColors.blue, fontSize: 10)))).toList()),
                  const SizedBox(height: 12),
                  Row(children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(
                        color: (m['is_accepting_bookings'] as bool? ?? true) ? AppColors.green : AppColors.red,
                        shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text((m['is_accepting_bookings'] as bool? ?? true) ? 'Available' : 'Busy',
                        style: TextStyle(
                            color: (m['is_accepting_bookings'] as bool? ?? true) ? AppColors.green : AppColors.red,
                            fontSize: 12)),
                    const Spacer(),
                    if (m['is_accepting_bookings'] as bool? ?? true)
                      GestureDetector(onTap: () => onBook(m),
                          child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                              decoration: BoxDecoration(color: AppColors.blue, borderRadius: BorderRadius.circular(20)),
                              child: const Text('Book →', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)))),
                  ]),
                ])),
              ])).animate(delay: Duration(milliseconds: i * 70)).fadeIn().slideY(begin: 0.05);
        });
  }
}

class _SessionsTab extends StatelessWidget {
  final List<Map<String, dynamic>> sessions; final VoidCallback onRefresh;
  const _SessionsTab({required this.sessions, required this.onRefresh});

  Color _statusColor(String s) => switch(s) {
    'confirmed' => AppColors.green, 'rejected' => AppColors.red,
    'completed' => AppColors.textSecondary, _ => AppColors.amber
  };

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) {
      return const EmptyState(icon: Icons.event_note_rounded,
        title: 'No sessions yet', subtitle: 'Book your first mentorship session');
    }
    return ListView.builder(padding: const EdgeInsets.all(16), itemCount: sessions.length,
        itemBuilder: (ctx, i) {
          final s = sessions[i];
          final mentor = (s['mentors'] as Map?)?['profiles'] as Map? ?? {};
          final status = s['status'] as String? ?? 'pending';
          return Container(margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.borderOf(context), width: 0.5)),
              child: Row(children: [
                Container(width: 44, height: 44, decoration: BoxDecoration(
                    color: AppColors.blue.withValues(alpha:0.1), borderRadius: BorderRadius.circular(10),
                    shape: BoxShape.rectangle),
                    child: const Icon(AppIcons.mentorship, color: AppColors.blue, size: 22)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(mentor['full_name'] ?? 'Faculty', style: AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimaryOf(context))),
                  Text(s['topic'] ?? '', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(context)), maxLines: 2, overflow: TextOverflow.ellipsis),
                ])),
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: _statusColor(status).withValues(alpha:0.12), borderRadius: BorderRadius.circular(10)),
                    child: Text(status.toUpperCase(), textHeightBehavior: const TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
                        style: TextStyle(color: _statusColor(status), fontSize: 10, height: 1.0, fontWeight: FontWeight.w700))),
              ]));
        });
  }
}

class _IncomingRequestsTab extends StatefulWidget {
  final List<Map<String, dynamic>> requests; final VoidCallback onRefresh;
  const _IncomingRequestsTab({required this.requests, required this.onRefresh});
  @override State<_IncomingRequestsTab> createState() => _IncomingRequestsTabState();
}

class _IncomingRequestsTabState extends State<_IncomingRequestsTab> {
  bool _busy = false;

  Future<void> _respond(Map<String, dynamic> request, String status) async {
    setState(() => _busy = true);
    try {
      await SupabaseConfig.client.from('mentorship_bookings').update({'status': status}).eq('id', request['id']);
      final studentId = request['student_id'] as String?;
      if (studentId != null) {
        final label = switch (status) {
          'confirmed' => 'accepted your mentorship request',
          'rejected' => 'declined your mentorship request',
          _ => 'marked your mentorship session as completed',
        };
        NotificationService.sendToUsers(
          userIds: [studentId],
          title: 'Mentorship update',
          message: 'Your mentor $label',
          deepLink: '/mentorship',
          category: 'mentorship',
        );
      }
      widget.onRefresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  Color _statusColor(String s) => switch (s) {
    'confirmed' => AppColors.green, 'rejected' => AppColors.red,
    'completed' => AppColors.textSecondary, _ => AppColors.amber
  };

  @override
  Widget build(BuildContext context) {
    if (widget.requests.isEmpty) {
      return const EmptyState(icon: Icons.inbox_outlined,
        title: 'No requests yet', subtitle: 'Student mentorship requests addressed to you will appear here');
    }
    return ListView.builder(padding: const EdgeInsets.all(16), itemCount: widget.requests.length,
        itemBuilder: (ctx, i) {
          final r = widget.requests[i];
          final student = r['profiles'] as Map<String, dynamic>? ?? {};
          final status = r['status'] as String? ?? 'pending';
          return Container(margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.borderOf(context), width: 0.5)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(student['full_name'] ?? 'Student',
                      style: AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimaryOf(context)),
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: _statusColor(status).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                      child: Text(status.toUpperCase(), textHeightBehavior: const TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
                          style: TextStyle(color: _statusColor(status), fontSize: 10, height: 1.0, fontWeight: FontWeight.w700))),
                ]),
                if ((student['department'] as String? ?? '').isNotEmpty)
                  Text(student['department'], style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondaryOf(context))),
                const SizedBox(height: 6),
                Text(r['topic'] ?? '', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(context)),
                    maxLines: 3, overflow: TextOverflow.ellipsis),
                if (status == 'pending') ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    TextButton(onPressed: _busy ? null : () => _respond(r, 'confirmed'),
                        child: const Text('Accept', style: TextStyle(fontSize: 12, color: AppColors.green))),
                    TextButton(onPressed: _busy ? null : () => _respond(r, 'rejected'),
                        child: const Text('Decline', style: TextStyle(fontSize: 12, color: AppColors.red))),
                  ]),
                ] else if (status == 'confirmed') ...[
                  const SizedBox(height: 10),
                  TextButton(onPressed: _busy ? null : () => _respond(r, 'completed'),
                      child: const Text('Mark completed', style: TextStyle(fontSize: 12, color: AppColors.blue))),
                ],
              ]));
        });
  }
}

class _MyMentorProfileTab extends StatefulWidget {
  final Map<String, dynamic>? profile; final VoidCallback onSaved;
  const _MyMentorProfileTab({required this.profile, required this.onSaved});
  @override State<_MyMentorProfileTab> createState() => _MyMentorProfileTabState();
}

class _MyMentorProfileTabState extends State<_MyMentorProfileTab> {
  late final _titleCtrl = TextEditingController(text: widget.profile?['title'] ?? '');
  late final _bioCtrl = TextEditingController(text: widget.profile?['bio'] ?? '');
  late final _specCtrl = TextEditingController(
      text: ((widget.profile?['specializations'] as List?)?.cast<String>() ?? []).join(', '));
  late bool _accepting = widget.profile?['is_accepting_bookings'] as bool? ?? true;
  bool _saving = false;

  @override
  void dispose() { _titleCtrl.dispose(); _bioCtrl.dispose(); _specCtrl.dispose(); super.dispose(); }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final specs = _specCtrl.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      await SupabaseConfig.client.from('mentors').upsert({
        'id': SupabaseConfig.uid,
        'title': _titleCtrl.text.trim(),
        'bio': _bioCtrl.text.trim(),
        'specializations': specs,
        'is_accepting_bookings': _accepting,
      });
      widget.onSaved();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mentor profile saved ✓'), backgroundColor: AppColors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (widget.profile == null)
        Text('Set up your mentor profile so students can find and book you.',
            style: AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
      if (widget.profile == null) const SizedBox(height: 16),
      AfosTextField(hint: 'Title (e.g. Senior Lecturer)', controller: _titleCtrl),
      const SizedBox(height: 12),
      AfosTextField(hint: 'Short bio', controller: _bioCtrl, maxLines: 3),
      const SizedBox(height: 12),
      AfosTextField(hint: 'Specializations (comma separated)', controller: _specCtrl),
      const SizedBox(height: 16),
      Row(children: [
        Text('Accepting new requests', style: AppTextStyles.bodyMedium.copyWith(color: textPrimary)),
        const Spacer(),
        Switch(value: _accepting, activeThumbColor: AppColors.blue,
            onChanged: (v) => setState(() => _accepting = v)),
      ]),
      const SizedBox(height: 16),
      AfosButton(label: widget.profile == null ? 'Become a Mentor' : 'Save Changes',
          loading: _saving, onTap: _save),
    ]));
  }
}

class _OversightTab extends StatelessWidget {
  final List<Map<String, dynamic>> bookings; final VoidCallback onRefresh;
  const _OversightTab({required this.bookings, required this.onRefresh});

  Color _statusColor(String s) => switch (s) {
    'confirmed' => AppColors.green, 'rejected' => AppColors.red,
    'completed' => AppColors.textSecondary, _ => AppColors.amber,
  };

  Future<void> _banMentor(BuildContext context, String mentorId, String mentorName) async {
    final confirm = await showDialog<bool>(
        context: context,
        builder: (dCtx) => AlertDialog(
              backgroundColor: AppColors.surfaceOf(dCtx),
              title: Text('Ban $mentorName as a mentor?', style: TextStyle(color: AppColors.textPrimaryOf(dCtx))),
              content: Text('Stops them accepting new mentorship requests and removes their mentor profile. They keep their teacher account.',
                  style: TextStyle(color: AppColors.textSecondaryOf(dCtx))),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Cancel')),
                TextButton(onPressed: () => Navigator.pop(dCtx, true), child: const Text('Ban', style: TextStyle(color: AppColors.red))),
              ],
            ));
    if (confirm != true) return;
    try {
      await SupabaseConfig.client.from('mentors').delete().eq('id', mentorId);
      onRefresh();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    if (bookings.isEmpty) {
      return const EmptyState(icon: Icons.school_outlined,
        title: 'No mentorship activity yet', subtitle: 'Every booking across the system will show up here');
    }
    return ListView.builder(padding: const EdgeInsets.all(16), itemCount: bookings.length,
        itemBuilder: (ctx, i) {
          final b = bookings[i];
          final student = b['profiles'] as Map<String, dynamic>? ?? {};
          final mentorRow = b['mentors'] as Map<String, dynamic>? ?? {};
          final mentorProfile = mentorRow['profiles'] as Map<String, dynamic>? ?? {};
          final mentorId = b['mentor_id'] as String?;
          final status = b['status'] as String? ?? 'pending';
          return Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.borderOf(context), width: 0.5)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('${student['full_name'] ?? 'Student'} → ${mentorProfile['full_name'] ?? 'Mentor'}',
                      style: AppTextStyles.titleMedium.copyWith(color: textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: _statusColor(status).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                      child: Text(status.toUpperCase(), textHeightBehavior: const TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
                          style: TextStyle(color: _statusColor(status), fontSize: 10, height: 1.0, fontWeight: FontWeight.w700))),
                ]),
                Text('${student['department'] ?? ''} · ${mentorProfile['department'] ?? ''}',
                    style: AppTextStyles.labelSmall.copyWith(color: textSecondary)),
                const SizedBox(height: 6),
                Text(b['topic'] ?? '', style: AppTextStyles.bodyMedium.copyWith(color: textSecondary), maxLines: 2, overflow: TextOverflow.ellipsis),
                if (mentorId != null) ...[
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerRight, child: TextButton.icon(
                      onPressed: () => _banMentor(context, mentorId, mentorProfile['full_name'] ?? 'this mentor'),
                      icon: const Icon(Icons.block, size: 16, color: AppColors.red),
                      label: const Text('Ban Mentor', style: TextStyle(color: AppColors.red, fontSize: 12)))),
                ],
              ]));
        });
  }
}
