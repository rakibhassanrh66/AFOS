import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../config/supabase_config.dart';
import 'package:url_launcher/url_launcher.dart';
import 'handover_scan_screen.dart';
import 'lost_found_chat_screen.dart';
import '../../../core/network/storage_upload_service.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../config/theme/depth.dart';
import '../../../config/theme/liquid_glass_tokens.dart';
import '../../../config/theme/motion.dart';
import '../../../config/theme/spacing.dart';
import '../../../core/haptics/app_haptics.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../../shared/widgets/afos_text_field.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/feature_header.dart';
import '../../../shared/widgets/glass_tab_bar.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../notifications/data/repositories/notification_service.dart';
import '../../shell/presentation/top_app_bar.dart';
import '../../../core/auth/role_session.dart';
import '../../../core/utils/error_formatter.dart';

import '../../../core/layout/nav_insets.dart';
import '../../web/presentation/widgets/adaptive_list.dart';
/// Refuses to go on without a phone number, and offers the fix.
///
/// The database refuses too — `require_phone_for_lost_found` is a BEFORE INSERT
/// trigger on both posts and claims, so this cannot be skipped by any client.
/// But a trigger exception arrives after the user has filled in a whole form,
/// and it arrives as an error rather than as an errand. This asks first, and
/// sends them to the one screen that fixes it.
///
/// Why the requirement exists at all: the entire point of the new flow is that
/// the two people can reach each other. A post from someone with no number is
/// a dead end that looks like a live one.
Future<bool> ensurePhoneOnFile(BuildContext context) async {
  final uid = SupabaseConfig.uid;
  if (uid == null) return false;
  try {
    final row = await SupabaseConfig.client
        .from('profiles').select('phone').eq('id', uid).maybeSingle();
    final phone = (row?['phone'] as String?)?.trim() ?? '';
    if (phone.isNotEmpty) return true;
  } catch (_) {
    // Could not check. Let it through — the trigger is the real gate, and
    // blocking a post because a lookup failed is the worse failure.
    return true;
  }
  if (!context.mounted) return false;

  final go = await showDialog<bool>(
    context: context,
    builder: (dctx) => AlertDialog(
      backgroundColor: AppColors.surfaceOf(dctx),
      title: Text('Add your phone number first',
          style: TextStyle(color: AppColors.textPrimaryOf(dctx))),
      content: Text(
        'Lost & Found works by putting two people in touch — whoever finds '
        'your item needs to be able to call you. Your number is only ever '
        'shown to the one person whose claim you accept, and only for 24 hours.',
        style: TextStyle(color: AppColors.textSecondaryOf(dctx)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dctx, false),
          child: Text('Not now',
              style: TextStyle(color: AppColors.textSecondaryOf(dctx))),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.holoviolet),
          onPressed: () => Navigator.pop(dctx, true),
          child: const Text('Add it in Settings'),
        ),
      ],
    ),
  );
  if (go == true && context.mounted) context.push('/settings');
  return false;
}

class LostFoundScreen extends StatefulWidget {
  const LostFoundScreen({super.key});
  @override State<LostFoundScreen> createState() => _LFState();
}

class _LFState extends State<LostFoundScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<Map<String, dynamic>> _posts = [];
  bool _loading = true;
  String _filter = 'all';
  String? _error;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    _load();
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      // Columns narrowed to exactly what _PostCard (below) reads/acts on —
      // poster_id and id are needed for the own-post/claim actions, not
      // just display.
      var q = SupabaseConfig.client.from('lost_found_posts')
          .select('id, poster_id, title, description, type, photo_url, location_text, status');
      // Resolved posts drop out of normal browsing automatically once
      // claimed/returned — 'returned' remains available as its own filter
      // chip for anyone who wants to look at resolved history.
      if (_filter == 'returned') {
        q = q.eq('status', 'returned');
      } else {
        q = q.neq('status', 'returned');
        if (_filter != 'all') q = q.eq('type', _filter);
      }
      final res = await q.order('created_at', ascending: false).limit(50) as List;
      if (mounted) setState(() => _posts = res.cast());
    } catch (e) {
      // Previously swallowed silently — a real load failure rendered
      // identically to "nothing posted", same class of bug already found
      // and fixed once in Manage Hall.
      if (mounted) setState(() => _error = friendlyError(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  static const _tabLabels = ['Feed', 'Post', 'My Posts', 'My Claims'];
  static const _tabIcons = [Icons.dynamic_feed_rounded, Icons.add_circle_outline_rounded, Icons.inventory_2_outlined, Icons.assignment_ind_outlined];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const AfosAppBar(title: 'Lost & Found'),
      body: Column(children: [
        FeatureHeader(
          title: 'Lost & Found',
          subtitle: _loading ? 'Loading…' : '${_posts.length} active ${_posts.length == 1 ? 'post' : 'posts'}',
          icon: Icons.find_in_page_rounded,
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [AppColors.coral, AppColors.red]),
          margin: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 12),
        ).animate().fadeIn(duration: AppMotion.durationOf(context, AppMotion.base))
            .slideY(begin: -0.06, curve: AppMotion.standard),
        AnimatedBuilder(
          animation: _tab,
          builder: (ctx, _) => GlassTabBar(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            currentIndex: _tab.index,
            onChanged: (i) => _tab.animateTo(i),
            tabs: [
              for (var i = 0; i < _tabLabels.length; i++)
                GlassTab(_tabLabels[i], icon: _tabIcons[i]),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(child: TabBarView(controller: _tab, children: [
          _FeedTab(posts: _posts, loading: _loading, error: _error, filter: _filter,
              onFilter: (f) { setState(() => _filter = f); _load(); },
              onRefresh: _load),
          _PostTab(onPosted: () { _load(); _tab.animateTo(0); }),
          _MyPostsTab(),
          const _MyClaimsTab(),
        ])),
      ]),
    );
  }
}

class _FeedTab extends StatelessWidget {
  final List<Map<String, dynamic>> posts;
  final bool loading; final String? error; final String filter;
  final ValueChanged<String> onFilter; final VoidCallback onRefresh;
  const _FeedTab({required this.posts, required this.loading, required this.error,
      required this.filter, required this.onFilter, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 8),
          child: SingleChildScrollView(scrollDirection: Axis.horizontal,
              child: Row(children: ['all', 'lost', 'found', 'returned'].map((f) {
                final sel = filter == f;
                return Padding(padding: const EdgeInsetsDirectional.only(end: 8),
                    child: GestureDetector(
                        onTap: () { AppHaptics.selection(); onFilter(f); },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: AppSpace.md),
                          decoration: BoxDecoration(
                              color: sel ? AppColors.blue : AppColors.surfaceOf(context),
                              borderRadius: BorderRadius.circular(LiquidGlass.radiusPill),
                              border: Border.all(color: sel ? AppColors.blue : AppColors.borderOf(context), width: 0.5)),
                          child: Text(f.substring(0, 1).toUpperCase() + f.substring(1),
                              style: TextStyle(color: sel ? Colors.white : AppColors.textSecondaryOf(context),
                                  fontSize: 13, fontWeight: sel ? FontWeight.w600 : FontWeight.normal)),
                        )));
              }).toList()))),
      Expanded(child: loading
          ? const Padding(padding: EdgeInsets.all(16), child: ShimmerGrid())
          : error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.error_outline_rounded, color: AppColors.red, size: 40),
                  const SizedBox(height: 12),
                  Text('Couldn\'t load: $error', textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondaryOf(context))),
                  const SizedBox(height: 12),
                  TextButton(onPressed: onRefresh, child: const Text('Retry')),
                ])))
              : posts.isEmpty
              ? const EmptyState(icon: Icons.search_off_rounded, title: 'No posts yet',
                  subtitle: 'Be the first to report a lost or found item')
              : RefreshIndicator(onRefresh: () async => onRefresh(), color: AppColors.blue,
                  child: GridView.builder(
                      padding: EdgeInsetsDirectional.fromSTEB(16, 16, 16, 16 + NavInsets.of(context)),
                      // Fixed 2-column count stretched into 2 wide tiles on a
                      // desktop browser window instead of more, reasonably-sized
                      // ones (see dashboard_screen.dart) -- max-extent keeps the
                      // same fixed height (still sized for the worst case: title +
                      // 2-line description + location row + Claim button) while
                      // adding columns as space allows.
                      // 260 before. The Claim button was 30dp tall, under the
                      // 48dp touch floor; raising it to 48 needs 18 more
                      // vertical pixels or the fixed-extent tile overflows.
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 220, crossAxisSpacing: 12, mainAxisSpacing: 12,
                          mainAxisExtent: 280),
                      itemCount: posts.length,
                      itemBuilder: (ctx, i) => _PostCard(post: posts[i], index: i, onDeleted: onRefresh)))),
    ]);
  }
}

class _PostCard extends StatelessWidget {
  final Map<String, dynamic> post; final int index; final VoidCallback onDeleted;
  const _PostCard({required this.post, required this.index, required this.onDeleted});

  bool get _isOwnPost => post['poster_id'] == SupabaseConfig.uid;

  Future<void> _superAdminDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (dctx) => AlertDialog(
              title: const Text('Delete this post?'),
              content: const Text('As Super Admin you can remove this post entirely — it will disappear for both the poster and any claimants.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Cancel')),
                TextButton(onPressed: () => Navigator.pop(dctx, true), child: const Text('Delete', style: TextStyle(color: AppColors.red))),
              ],
            ));
    if (confirmed != true) return;
    AppHaptics.warning();
    try {
      await SupabaseConfig.client.from('lost_found_posts').delete().eq('id', post['id']);
      onDeleted();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
  }

  Future<void> _openClaimDialog(BuildContext context) async {
    // Same gate as posting: a claim from someone unreachable is a dead end for
    // the person who found the item.
    if (!await ensurePhoneOnFile(context)) return;
    if (!context.mounted) return;
    final msgCtrl = TextEditingController();
    bool? sent;
    String message = '';
    try {
      sent = await showDialog<bool>(
        context: context,
        builder: (dctx) => AlertDialog(
              title: const Text('Claim this item'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Describe matching details (color, marks, contents, receipt, etc.) so the poster can verify it\'s yours.',
                    style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(dctx))),
                const SizedBox(height: 12),
                TextField(controller: msgCtrl, maxLines: 3,
                    decoration: const InputDecoration(hintText: 'Matching details...', border: OutlineInputBorder())),
              ]),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Cancel')),
                TextButton(onPressed: () => Navigator.pop(dctx, true), child: const Text('Send claim')),
              ],
            ));
      // Read the field BEFORE the finally disposes the controller.
      message = msgCtrl.text.trim();
    } finally {
      // BUG_REGISTER P1-02: one controller leaked per claim dialog opened.
      msgCtrl.dispose();
    }
    if (sent != true || message.isEmpty) return;
    try {
      await SupabaseConfig.client.from('lost_found_claims').insert({
        'post_id': post['id'], 'claimant_id': SupabaseConfig.uid,
        'message': message,
      });
      final posterId = post['poster_id'] as String?;
      if (posterId != null) {
        NotificationService.sendToUsers(
          userIds: [posterId],
          title: 'New claim on your post',
          message: 'Someone claimed "${post['title'] ?? 'your item'}" — review it in Lost & Found.',
          deepLink: '/lost-found',
          category: 'lost_found',
        );
      }
      if (context.mounted) {
        AppHaptics.success();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Claim sent to poster for review')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = post['type'] as String? ?? 'lost';
    final typeColor = type == 'lost' ? AppColors.red : AppColors.green;
    // The header image has to clip to the card's OWN top corners, and the card
    // radius is the AFOS signature — three corners large, top-right cut. A
    // symmetric BorderRadius.vertical here would leave the photo proud of the
    // cut corner.
    const headerRadius = BorderRadius.only(
        topLeft: Radius.circular(LiquidGlass.radiusCard),
        topRight: Radius.circular(LiquidGlass.radiusCut));
    return Container(
      decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: AppDepth.radius(2),
          border: Border.all(color: typeColor.withValues(alpha:0.3), width: 0.7)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Stack(children: [
          Container(height: 110, decoration: BoxDecoration(
              color: typeColor.withValues(alpha:0.1),
              borderRadius: headerRadius),
              child: post['photo_url'] != null
                  ? ClipRRect(borderRadius: headerRadius,
                      child: CachedNetworkImage(imageUrl: post['photo_url'], fit: BoxFit.cover, memCacheWidth: 440,
                          width: double.infinity,
                          errorWidget: (_, __, ___) => const Center(
                              child: Icon(Icons.image_not_supported_outlined,
                                  color: AppColors.textMuted, size: 32))))
                  : Center(child: Icon(Icons.search, color: typeColor, size: 36))),
          Positioned(top: 8, right: 8, child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: typeColor, borderRadius: AppDepth.radius(1)),
              child: Text(type.toUpperCase(),
                  textHeightBehavior: const TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
                  style: const TextStyle(color: Colors.white, fontSize: 9, height: 1.0, fontWeight: FontWeight.w800)))),
          if (RoleSession.role == 'super_admin') Positioned(top: 6, left: 6, child: GestureDetector(
              onTap: () => _superAdminDelete(context),
              child: Container(padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha:0.55), shape: BoxShape.circle),
                  child: const Icon(Icons.delete_forever_rounded, color: Colors.white, size: 16)))),
        ]),
        Padding(padding: const EdgeInsets.all(10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(post['title'] ?? '', style: AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimaryOf(context)), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 3),
          Text(post['description'] ?? '', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(context)), maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          Row(children: [
            Icon(Icons.location_on_outlined, size: 11, color: AppColors.textSecondaryOf(context)),
            const SizedBox(width: 3),
            Expanded(child: Text(post['location_text'] ?? '', style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondaryOf(context)), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
          if (!_isOwnPost && post['status'] == 'active') ...[
            const SizedBox(height: 8),
            // Was 30dp tall — the primary action on the card, under the touch floor.
            SizedBox(width: double.infinity, height: AppSpace.minTouchTarget, child: OutlinedButton(
                onPressed: () => _openClaimDialog(context),
                style: OutlinedButton.styleFrom(padding: EdgeInsets.zero,
                    side: BorderSide(color: typeColor.withValues(alpha:0.5))),
                child: Text('Claim', style: TextStyle(color: typeColor, fontSize: 11, fontWeight: FontWeight.w700)))),
          ],
        ])),
      ]),
    ).animate(delay: AppMotion.staggerFor(context, index)).fadeIn().scale(begin: const Offset(0.95, 0.95));
  }
}


class _PostTab extends StatefulWidget {
  final VoidCallback onPosted;
  const _PostTab({required this.onPosted});
  @override State<_PostTab> createState() => _PostTabState();
}

class _PostTabState extends State<_PostTab> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _locCtrl = TextEditingController();

  @override
  void dispose() { _titleCtrl.dispose(); _descCtrl.dispose(); _locCtrl.dispose(); super.dispose(); }
  String _type = 'lost', _category = 'Electronics';
  XFile? _image;
  bool _loading = false;

  Future<void> _pickImage() async {
    final img = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 70);
    // BUG_REGISTER P1-01: setState after an await with no mounted guard. The
    // picker is a full platform round-trip, so leaving the tab mid-pick is easy.
    if (img != null && mounted) setState(() => _image = img);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!await ensurePhoneOnFile(context)) return;
    // The other `ensurePhoneOnFile` call in this same file (the claim flow)
    // already guards after this await, because it can put a dialog up and
    // wait on the person. This one was missed.
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      String? photoUrl;
      if (_image != null) {
        photoUrl = await StorageUploadService.uploadImage(bucket: 'lost-found', image: _image!);
      }
      await SupabaseConfig.client.from('lost_found_posts').insert({
        'poster_id': SupabaseConfig.uid, 'type': _type,
        'title': _titleCtrl.text.trim(), 'description': _descCtrl.text.trim(),
        'category': _category, 'location_text': _locCtrl.text.trim(),
        'photo_url': photoUrl, 'status': 'active',
      });
      _formKey.currentState!.reset();
      _titleCtrl.clear();
      _descCtrl.clear();
      _locCtrl.clear();
      if (mounted) setState(() { _type = 'lost'; _category = 'Electronics'; _image = null; });
      AppHaptics.success();
      widget.onPosted();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsetsDirectional.fromSTEB(20, 20, 20, 20 + NavInsets.of(context)),
      child: Form(key: _formKey, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: _TypeChip('I Lost Something', 'lost', _type, (v) => setState(() => _type = v))),
          const SizedBox(width: 12),
          Expanded(child: _TypeChip('I Found Something', 'found', _type, (v) => setState(() => _type = v))),
        ]),
        const SizedBox(height: 20),
        AfosTextField(hint: 'Item title', controller: _titleCtrl,
            validator: (v) => v == null || v.isEmpty ? 'Title required' : null),
        const SizedBox(height: 14),
        AfosTextField(hint: 'Description', controller: _descCtrl, maxLines: 3,
            validator: (v) => v == null || v.isEmpty ? 'Description required' : null),
        const SizedBox(height: 14),
        AfosTextField(hint: 'Where was it lost/found?', controller: _locCtrl,
            validator: (v) => v == null || v.isEmpty ? 'Location required' : null),
        const SizedBox(height: 14),
        GestureDetector(onTap: _pickImage, child: Container(
            width: double.infinity, height: 100,
            decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: AppDepth.radius(1),
                border: Border.all(color: _image != null ? AppColors.green : AppColors.borderOf(context))),
            child: _image != null
                // dart:io's File doesn't work on Flutter Web at all -- the
                // actual upload already goes through XFile.readAsBytes()
                // (web-safe), but this preview still built a File from the
                // path directly. On web, XFile.path is a blob: URL that
                // Image.network can load directly; only native platforms
                // get a real filesystem path Image.file can use.
                // cacheWidth on both: this box is 100px tall, but `pickImage`
                // only compresses QUALITY (imageQuality: 70), never the
                // dimensions, so what lands here is a full camera frame —
                // decoding 4000x3000 into a 100px strip costs ~48MB of bitmap
                // for a thumbnail. 1080 is a full-width phone screen at 3x,
                // so the preview is still sharp and the decode is ~13x
                // cheaper. The constitution bans images without cacheWidth
                // for exactly this reason; this was the app's only Image.network.
                ? ClipRRect(borderRadius: AppDepth.radius(1),
                    child: kIsWeb
                        ? Image.network(_image!.path, fit: BoxFit.cover, cacheWidth: 1080)
                        : Image.file(File(_image!.path), fit: BoxFit.cover, cacheWidth: 1080))
                : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.add_photo_alternate_outlined, color: AppColors.textSecondaryOf(context), size: 32),
                    const SizedBox(height: 6),
                    Text('Add photo (optional)', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(context))),
                  ]))),
        const SizedBox(height: 24),
        AfosButton(label: 'Post ${_type == 'lost' ? 'Lost' : 'Found'} Item',
            loading: _loading, onTap: _submit),
      ])),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String label, value, selected; final ValueChanged<String> onTap;
  const _TypeChip(this.label, this.value, this.selected, this.onTap);
  @override
  Widget build(BuildContext context) {
    final sel = selected == value;
    final color = value == 'lost' ? AppColors.red : AppColors.green;
    return GestureDetector(
        onTap: () { AppHaptics.selection(); onTap(value); },
        child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.lg),
        decoration: BoxDecoration(color: sel ? color.withValues(alpha:0.15) : AppColors.surfaceOf(context),
            borderRadius: AppDepth.radius(1),
            border: Border.all(color: sel ? color : AppColors.borderOf(context))),
        child: Center(child: Text(label,
            style: TextStyle(color: sel ? color : AppColors.textSecondaryOf(context), fontSize: 12,
                fontWeight: FontWeight.w600), textAlign: TextAlign.center))));
  }
}

class _MyPostsTab extends StatefulWidget {
  @override State<_MyPostsTab> createState() => _MyPostsTabState();
}

class _MyPostsTabState extends State<_MyPostsTab> {
  List<Map<String, dynamic>> _myPosts = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  // The old _startHandover lived here: it fetched the accepted claimant's name
  // itself and always opened the scanner AS THE POSTER. Both halves are now
  // wrong -- _HandoverPanel already holds the counterparty (through the RPC
  // that also enforces the 24h window), and on a `found` post the claimant is
  // the one who scans. Keeping a second path to the scanner would have meant
  // two places deciding who receives, which is the bug this batch is fixing.

  /// Plain English for a status the database stores as a keyword.
  ///
  /// 'awaiting_handover' was being rendered to users verbatim.
  String _statusLabel(Map<String, dynamic> p) {
    final status = p['status'] as String? ?? '';
    switch (status) {
      case 'awaiting_handover':
        return 'Waiting to hand over';
      case 'returned':
        // The distinction that makes the record worth keeping: proven by a
        // campus-ID scan, or closed on someone's word.
        return p['handover_verified'] == true
            ? 'Returned - ID verified'
            : 'Returned - not verified';
      case 'active':
        return 'Open';
      default:
        return status;
    }
  }

  Future<void> _load() async {
    final uid = SupabaseConfig.uid;
    if (uid == null) { setState(() => _loading = false); return; }
    try {
      final res = await SupabaseConfig.client.from('lost_found_posts')
          .select('id, poster_id, title, description, type, photo_url, location_text, status, handover_verified, returned_to')
          .eq('poster_id', uid).order('created_at', ascending: false) as List;
      if (mounted) setState(() => _myPosts = res.cast());
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Padding(padding: EdgeInsets.all(16), child: ShimmerList());
    if (_myPosts.isEmpty) {
      return const EmptyState(icon: Icons.post_add_rounded,
        title: 'No posts yet', subtitle: 'Post a lost or found item from the Post tab');
    }
    return AdaptiveList(padding: EdgeInsetsDirectional.fromSTEB(16, 16, 16, 16 + NavInsets.of(context)), itemCount: _myPosts.length,
        itemBuilder: (ctx, i) {
          final p = _myPosts[i];
          final type = p['type'] as String? ?? 'lost';
          final color = type == 'lost' ? AppColors.red : AppColors.green;
          return Container(margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: AppDepth.radius(1),
                  border: Border.all(color: AppColors.borderOf(context), width: 0.5)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 10, height: 50, decoration: BoxDecoration(
                    color: color, borderRadius: BorderRadius.circular(LiquidGlass.radiusPill))),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p['title'] ?? '', style: AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimaryOf(context))),
                  // Raw status strings leaked to the user ('awaiting_handover'),
                  // and 'returned' said nothing about whether anyone actually
                  // proved they collected it -- which is the whole question
                  // this feature now answers.
                  Row(children: [
                    Text(_statusLabel(p), style: TextStyle(color: color, fontSize: 12)),
                    if (p['status'] == 'returned' && p['handover_verified'] == true) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.verified_rounded, size: 13, color: AppColors.green),
                    ],
                  ]),
                ])),
                // WAS a one-tap "Mark Found" that set the post to 'returned'
                // on the poster's word alone -- no counterparty, no evidence,
                // and no record of who received the item. An item could be
                // closed with nobody having claimed it.
                //
                // Now the button only appears once a claim has been accepted,
                // and it opens the VR-ID scan. The database refuses to mark
                // anything returned any other way.
                // The action itself moved into _HandoverPanel below the row,
                // because it is no longer one button: contacting the other
                // person is half the job, and WHO confirms depends on which
                // way the item is travelling.
                IconButton(
                    icon: const Icon(Icons.delete_outline, color: AppColors.red, size: 20),
                    tooltip: 'Delete post',
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (dctx) => AlertDialog(
                                title: const Text('Delete post?'),
                                content: const Text('This removes it permanently for everyone.'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Cancel')),
                                  TextButton(onPressed: () => Navigator.pop(dctx, true), child: const Text('Delete')),
                                ],
                              ));
                      if (confirmed == true) {
                        AppHaptics.warning();
                        await SupabaseConfig.client.from('lost_found_posts').delete().eq('id', p['id']);
                        _load();
                      }
                    }),
              ]),
              _ClaimsPanel(postId: p['id'], onResolved: _load),
              // On MY posts, I am the receiver only when I am the one who lost
              // the item. If I posted a `found` item, the claimant collects it
              // from me and confirms on their own My Claims tab — so I get
              // Call and Message here, and no confirm button, because
              // confirming would be me signing for my own handover.
              if (p['status'] == 'awaiting_handover')
                _HandoverPanel(
                  postId: p['id'] as String,
                  itemTitle: p['title'] as String? ?? 'this item',
                  postType: p['type'] as String? ?? 'lost',
                  iAmReceiver: (p['type'] as String? ?? 'lost') == 'lost',
                  onChanged: _load,
                ),
              ]));
        });
  }
}

class _ClaimsPanel extends StatefulWidget {
  final dynamic postId; final VoidCallback onResolved;
  const _ClaimsPanel({required this.postId, required this.onResolved});
  @override State<_ClaimsPanel> createState() => _ClaimsPanelState();
}

class _ClaimsPanelState extends State<_ClaimsPanel> {
  List<Map<String, dynamic>> _claims = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      // Fetch every non-rejected claim (not just pending) so an accepted
      // claim stays visible after the post moves to 'returned' — the poster
      // needs to keep seeing who they matched with to arrange handover and
      // to clean the record up afterward.
      final res = await SupabaseConfig.client.from('lost_found_claims').select()
          .eq('post_id', widget.postId).neq('status', 'rejected')
          .order('created_at', ascending: false) as List;
      if (mounted) setState(() { _claims = res.cast(); _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _respond(Map<String, dynamic> claim, String status) async {
    // Accepting goes through the RPC, not a bare status update.
    //
    // The two used to be separate: the client set the claim's status, and a
    // trigger independently decided the POST was 'returned' the same instant —
    // before the two people had met, with nothing recording who received the
    // item. Accepting now means "this is the person", and the item is only
    // returned once their VR-ID has been scanned.
    if (status == 'accepted') {
      await SupabaseConfig.client.rpc('accept_lost_found_claim',
          params: {'p_claim_id': claim['id']});
    } else {
      await SupabaseConfig.client.from('lost_found_claims')
          .update({'status': status}).eq('id', claim['id']);
    }
    // Accepting hands someone their property back and is not undoable from
    // here; rejecting is a refusal. Different weights, same commit point.
    if (status == 'accepted') {
      AppHaptics.success();
    } else {
      AppHaptics.warning();
    }
    final claimantId = claim['claimant_id'] as String?;
    if (claimantId != null) {
      NotificationService.sendToUsers(
        userIds: [claimantId],
        title: 'Lost & Found update',
        message: status == 'accepted'
            ? 'Your claim was accepted! Check the item\'s details to arrange handover.'
            : 'Your claim was declined by the poster.',
        deepLink: '/lost-found',
        category: 'lost_found',
      );
    }
    if (status == 'accepted') widget.onResolved();
    _load();
  }

  Future<void> _deleteClaim(String claimId) async {
    await SupabaseConfig.client.from('lost_found_claims').delete().eq('id', claimId);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _claims.isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(top: 10), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Claims (${_claims.length})', style: AppTextStyles.labelSmall.copyWith(
          color: AppColors.textSecondaryOf(context), fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      ..._claims.map((c) {
        final accepted = c['status'] == 'accepted';
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: AppColors.blue.withValues(alpha: 0.06), borderRadius: AppDepth.radius(0)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(c['message'] ?? '', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimaryOf(context)))),
              if (accepted) const Padding(padding: EdgeInsetsDirectional.only(start: 6),
                  child: Icon(Icons.check_circle_rounded, color: AppColors.green, size: 16)),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              if (!accepted) ...[
                TextButton(onPressed: () => _respond(c, 'accepted'),
                    child: const Text('Accept', style: TextStyle(fontSize: 11, color: AppColors.green))),
                TextButton(onPressed: () => _respond(c, 'rejected'),
                    child: const Text('Reject', style: TextStyle(fontSize: 11, color: AppColors.red))),
              ] else
                TextButton(onPressed: () => _deleteClaim(c['id']),
                    child: Text('Clear record', style: TextStyle(fontSize: 11, color: AppColors.textMutedOf(context)))),
            ]),
          ]));
      }),
    ]));
  }
}

/// Everything the two people in a handover can do, in one place.
///
/// WHO CONFIRMS DEPENDS ON WHICH WAY THE ITEM IS TRAVELLING. This is the rule
/// the whole flow now turns on, and it was previously wrong:
///
///   type    | receiver (confirms, and is recorded) | giver (is scanned)
///   --------+--------------------------------------+---------------------------
///   lost    | poster   — they lost it              | claimant — they found it
///   found   | claimant — they own it               | poster   — they found it
///
/// The receiver scans the giver. Before this, the POSTER always confirmed and
/// the CLAIMANT was always recorded as having received the item — so on a
/// `lost` post, the log said the finder walked away with someone else's
/// property. The button therefore has to appear on My Posts for a lost item
/// and on My Claims for a found one, which is why this is a shared widget
/// rather than something living in one tab.
///
/// Contact is deliberately unavailable until a claim is accepted. Before that
/// point the two people have no established relationship, and handing out a
/// phone number to anyone who taps "claim" is how a lost-and-found board
/// becomes a directory.
class _HandoverPanel extends StatefulWidget {
  final String postId;
  final String itemTitle;
  final String postType;      // 'lost' | 'found'
  final bool iAmReceiver;
  final VoidCallback onChanged;

  const _HandoverPanel({
    required this.postId,
    required this.itemTitle,
    required this.postType,
    required this.iAmReceiver,
    required this.onChanged,
  });

  @override
  State<_HandoverPanel> createState() => _HandoverPanelState();
}

class _HandoverPanelState extends State<_HandoverPanel> {
  Map<String, dynamic>? _other;
  bool _loading = true;
  String? _closedReason;

  @override
  void initState() {
    super.initState();
    _loadContact();
  }

  Future<void> _loadContact() async {
    try {
      // Through the RPC, not a profiles select. The RPC is the only path that
      // also enforces the 24-hour window — `accepted_claim_parties_read_profiles`
      // would happily keep serving the number forever.
      final res = await SupabaseConfig.client.rpc(
          'lost_found_counterparty_contact',
          params: {'p_post_id': widget.postId}) as List;
      if (!mounted) return;
      setState(() {
        _other = res.isEmpty ? null : res.first as Map<String, dynamic>;
        _loading = false;
      });
    } catch (e) {
      // An expired window raises rather than returning empty, and that is a
      // sentence worth showing rather than an error to swallow.
      if (mounted) setState(() { _closedReason = friendlyError(e); _loading = false; });
    }
  }

  Future<void> _call() async {
    final phone = _other?['phone'] as String?;
    if (phone == null || phone.isEmpty) return;
    // Same launcher pattern as sos_alert_detail_screen.
    await launchUrl(Uri.parse('tel:$phone'));
  }

  void _message() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => LostFoundChatScreen(
        postId: widget.postId,
        itemTitle: widget.itemTitle,
        otherName: _other?['full_name'] as String? ?? 'the other person',
      ),
    ));
  }

  Future<void> _confirmReceipt() async {
    final done = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => HandoverScanScreen(
        postId: widget.postId,
        itemTitle: widget.itemTitle,
        giverName: _other?['full_name'] as String? ?? 'the other person',
        postType: widget.postType,
      ),
    ));
    if (done == true && mounted) {
      // Both people are told, not just the one holding the phone that scanned.
      final otherId = _other?['profile_id'] as String?;
      if (otherId != null) {
        await NotificationService.sendToUsers(
          userIds: [otherId],
          title: 'Handover confirmed',
          message: '"${widget.itemTitle}" is recorded as returned, verified by '
              'a campus ID scan.',
          category: 'general',
        );
      }
      widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: SizedBox(height: 2, child: LinearProgressIndicator()),
      );
    }

    if (_closedReason != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(_closedReason!,
            style: AppTextStyles.labelSmall
                .copyWith(color: AppColors.textMutedOf(context))),
      );
    }

    final phone = _other?['phone'] as String?;
    final name = _other?['full_name'] as String? ?? 'the other person';

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 10),
      Divider(height: 1, color: AppColors.borderOf(context)),
      const SizedBox(height: 10),
      Text(
        widget.iAmReceiver
            ? 'Arrange to meet $name. When they hand it over, confirm below by '
              'scanning their campus ID.'
            : 'Arrange to meet $name. They confirm the handover by scanning '
              'YOUR campus ID, so have it ready.',
        style: AppTextStyles.labelSmall
            .copyWith(color: AppColors.textSecondaryOf(context)),
      ),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (phone != null && phone.isNotEmpty)
          OutlinedButton.icon(
            onPressed: _call,
            style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.green,
                side: const BorderSide(color: AppColors.green),
                // 48dp minimum touch target.
                minimumSize: const Size(0, 48)),
            icon: const Icon(Icons.call_rounded, size: 18),
            label: const Text('Call'),
          ),
        OutlinedButton.icon(
          onPressed: _message,
          style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.holoBlue,
              side: const BorderSide(color: AppColors.holoBlue),
              minimumSize: const Size(0, 48)),
          icon: const Icon(Icons.forum_rounded, size: 18),
          label: const Text('Message'),
        ),
        if (widget.iAmReceiver)
          FilledButton.icon(
            onPressed: _confirmReceipt,
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.green,
                minimumSize: const Size(0, 48)),
            icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
            label: const Text('I received it'),
          ),
      ]),
    ]);
  }
}

class _MyClaimsTab extends StatefulWidget {
  const _MyClaimsTab();
  @override State<_MyClaimsTab> createState() => _MyClaimsTabState();
}

class _MyClaimsTabState extends State<_MyClaimsTab> {
  List<Map<String, dynamic>> _claims = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final uid = SupabaseConfig.uid;
    if (uid == null) { setState(() => _loading = false); return; }
    try {
      final res = await SupabaseConfig.client.from('lost_found_claims')
          .select('*, lost_found_posts(title, type, status, poster_id)')
          .eq('claimant_id', uid).order('created_at', ascending: false) as List;
      if (mounted) setState(() { _claims = res.cast(); _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _withdraw(String claimId) async {
    await SupabaseConfig.client.from('lost_found_claims').delete().eq('id', claimId);
    _load();
  }

  Future<void> _showContact(BuildContext context, String posterId) async {
    try {
      final poster = await SupabaseConfig.client.from('profiles')
          .select('full_name, phone, email').eq('id', posterId).single();
      if (!context.mounted) return;
      showDialog(context: context, builder: (dctx) => AlertDialog(
          title: const Text('Contact the poster'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            // AppTextStyles.titleMedium is hardcoded to the DARK-mode text
            // colour (near-white, meant to sit on a dark canvas) with no
            // theme override — this AlertDialog's background comes from
            // Material's own theme (near-white in light mode), so this was
            // near-white text on a near-white dialog: invisible in light mode.
            Text(poster['full_name'] ?? '', style: AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimaryOf(dctx))),
            if ((poster['phone'] as String? ?? '').isNotEmpty) Text('Phone: ${poster['phone']}'),
            Text('Email: ${poster['email'] ?? ''}'),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Close'))]));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
  }

  // ^ _showContact is kept only for a claim whose post is already CLOSED, where
  // there is no live handover panel but the two people may still need to reach
  // each other about it. It is not the contact path any more: _HandoverPanel
  // is, for two reasons beyond this dialog being tedious to use.
  //
  // First, this reads the profile DIRECTLY, which relies on
  // `accepted_claim_parties_read_profiles` -- a policy with no expiry. The
  // number stays readable long after the item changed hands. The RPC the panel
  // calls enforces the same 24-hour window as the message thread.
  //
  // Second, showing a number is not contacting someone. `tel:` and a message
  // thread are what a person standing in a corridor actually needs.

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Padding(padding: EdgeInsets.all(16), child: ShimmerList());
    if (_claims.isEmpty) {
      return const EmptyState(icon: Icons.inbox_outlined,
        title: 'No claims filed', subtitle: 'Claims you send from the Feed tab will appear here');
    }
    return AdaptiveList(padding: EdgeInsetsDirectional.fromSTEB(16, 16, 16, 16 + NavInsets.of(context)), itemCount: _claims.length,
        itemBuilder: (ctx, i) {
          final c = _claims[i];
          final post = c['lost_found_posts'] as Map<String, dynamic>? ?? {};
          final status = c['status'] as String? ?? 'pending';
          final statusColor = status == 'accepted' ? AppColors.green
              : status == 'rejected' ? AppColors.red : AppColors.amber;
          return Container(margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: AppDepth.radius(1),
                  border: Border.all(color: AppColors.borderOf(context), width: 0.5)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(post['title'] ?? 'Post removed',
                      style: AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimaryOf(context)),
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.12), borderRadius: AppDepth.radius(1)),
                      child: Text(status.toUpperCase(), textHeightBehavior: const TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
                          style: TextStyle(color: statusColor, fontSize: 10, height: 1.0, fontWeight: FontWeight.w700))),
                ]),
                const SizedBox(height: 4),
                Text(c['message'] ?? '', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(context)),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 8),
                Row(children: [
                  // Only once the handover panel is gone: while it is showing,
                  // Call and Message are right there and better.
                  if (status == 'accepted' &&
                      post['status'] != 'awaiting_handover' &&
                      post['poster_id'] != null)
                    TextButton(
                        onPressed: () => _showContact(context, post['poster_id']),
                        child: const Text('Contact poster',
                            style: TextStyle(fontSize: 11, color: AppColors.blue))),
                  TextButton(onPressed: () => _withdraw(c['id']),
                      child: Text(status == 'pending' ? 'Withdraw' : 'Clear record',
                          style: TextStyle(fontSize: 11, color: AppColors.textMutedOf(context)))),
                ]),
                // THE HALF THAT WAS MISSING ENTIRELY.
                //
                // A claimant used to get one thing here: a dialog showing the
                // poster's phone and email as text to copy out by hand. No
                // call, no message, and -- on a `found` post, where THEY are
                // the one collecting the item -- no way to confirm they
                // received it. The poster confirmed on their behalf, and the
                // record said the poster had received their own item back.
                if (status == 'accepted' &&
                    (post['status'] == 'awaiting_handover'))
                  _HandoverPanel(
                    postId: c['post_id'] as String,
                    itemTitle: post['title'] as String? ?? 'this item',
                    postType: post['type'] as String? ?? 'found',
                    // I claimed a `found` post => the item comes to me.
                    iAmReceiver: (post['type'] as String? ?? 'found') == 'found',
                    onChanged: _load,
                  ),
              ]));
        });
  }
}
