import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import '../../../config/supabase_config.dart';
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
                ? ClipRRect(borderRadius: AppDepth.radius(1),
                    child: kIsWeb
                        ? Image.network(_image!.path, fit: BoxFit.cover)
                        : Image.file(File(_image!.path), fit: BoxFit.cover))
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

  Future<void> _load() async {
    final uid = SupabaseConfig.uid;
    if (uid == null) { setState(() => _loading = false); return; }
    try {
      final res = await SupabaseConfig.client.from('lost_found_posts')
          .select('id, poster_id, title, description, type, photo_url, location_text, status')
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
    return ListView.builder(padding: EdgeInsetsDirectional.fromSTEB(16, 16, 16, 16 + NavInsets.of(context)), itemCount: _myPosts.length,
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
                  Text(p['status'] ?? '', style: TextStyle(color: color, fontSize: 12)),
                ])),
                if (p['status'] == 'active') Flexible(
                  child: TextButton(
                      onPressed: () async {
                        await SupabaseConfig.client.from('lost_found_posts')
                            .update({'status': 'returned'}).eq('id', p['id']);
                        AppHaptics.success();
                        _load();
                      },
                      child: Text(type == 'lost' ? 'Mark Found' : 'Mark Claimed',
                          maxLines: 1, style: const TextStyle(fontSize: 11))),
                ),
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
    await SupabaseConfig.client.from('lost_found_claims').update({'status': status}).eq('id', claim['id']);
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

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Padding(padding: EdgeInsets.all(16), child: ShimmerList());
    if (_claims.isEmpty) {
      return const EmptyState(icon: Icons.inbox_outlined,
        title: 'No claims filed', subtitle: 'Claims you send from the Feed tab will appear here');
    }
    return ListView.builder(padding: EdgeInsetsDirectional.fromSTEB(16, 16, 16, 16 + NavInsets.of(context)), itemCount: _claims.length,
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
                  if (status == 'accepted' && post['poster_id'] != null) TextButton(
                      onPressed: () => _showContact(context, post['poster_id']),
                      child: const Text('Contact poster', style: TextStyle(fontSize: 11, color: AppColors.blue))),
                  TextButton(onPressed: () => _withdraw(c['id']),
                      child: Text(status == 'pending' ? 'Withdraw' : 'Clear record',
                          style: TextStyle(fontSize: 11, color: AppColors.textMutedOf(context)))),
                ]),
              ]));
        });
  }
}
