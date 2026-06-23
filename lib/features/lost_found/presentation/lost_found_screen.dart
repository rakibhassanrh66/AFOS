import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import '../../../config/app_config.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../../shared/widgets/afos_text_field.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../shell/presentation/top_app_bar.dart';

class LostFoundScreen extends StatefulWidget {
  const LostFoundScreen({super.key});
  @override State<LostFoundScreen> createState() => _LFState();
}

class _LFState extends State<LostFoundScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<Map<String, dynamic>> _posts = [];
  bool _loading = true;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      var q = SupabaseConfig.client.from('lost_found_posts').select();
      if (_filter != 'all') q = q.eq('type', _filter);
      final res = await q.order('created_at', ascending: false) as List;
      if (mounted) setState(() => _posts = res.cast());
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AfosAppBar(title: 'Lost & Found'),
      body: Column(children: [
        Container(color: AppColors.surface, child: TabBar(
            controller: _tab,
            labelColor: AppColors.blue,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.blue,
            tabs: const [Tab(text: 'Feed'), Tab(text: 'Post'), Tab(text: 'My Posts')])),
        Expanded(child: TabBarView(controller: _tab, children: [
          _FeedTab(posts: _posts, loading: _loading, filter: _filter,
              onFilter: (f) { setState(() => _filter = f); _load(); },
              onRefresh: _load),
          _PostTab(onPosted: () { _load(); _tab.animateTo(0); }),
          _MyPostsTab(),
        ])),
      ]),
    );
  }
}

class _FeedTab extends StatelessWidget {
  final List<Map<String, dynamic>> posts;
  final bool loading; final String filter;
  final ValueChanged<String> onFilter; final VoidCallback onRefresh;
  const _FeedTab({required this.posts, required this.loading,
      required this.filter, required this.onFilter, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: SingleChildScrollView(scrollDirection: Axis.horizontal,
              child: Row(children: ['all', 'lost', 'found', 'returned'].map((f) {
                final sel = filter == f;
                return Padding(padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(onTap: () => onFilter(f),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                              color: sel ? AppColors.blue : AppColors.card,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: sel ? AppColors.blue : AppColors.border, width: 0.5)),
                          child: Text(f.substring(0, 1).toUpperCase() + f.substring(1),
                              style: TextStyle(color: sel ? Colors.white : AppColors.textSecondary,
                                  fontSize: 13, fontWeight: sel ? FontWeight.w600 : FontWeight.normal)),
                        )));
              }).toList()))),
      Expanded(child: loading
          ? const Padding(padding: EdgeInsets.all(16), child: ShimmerGrid())
          : posts.isEmpty
              ? EmptyState(icon: Icons.search_off_rounded, title: 'No posts yet',
                  subtitle: 'Be the first to report a lost or found item')
              : RefreshIndicator(onRefresh: () async => onRefresh(), color: AppColors.blue,
                  child: GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12,
                          childAspectRatio: 0.78),
                      itemCount: posts.length,
                      itemBuilder: (ctx, i) => _PostCard(post: posts[i], index: i)))),
    ]);
  }
}

class _PostCard extends StatelessWidget {
  final Map<String, dynamic> post; final int index;
  const _PostCard({required this.post, required this.index});

  @override
  Widget build(BuildContext context) {
    final type = post['type'] as String? ?? 'lost';
    final typeColor = type == 'lost' ? AppColors.red : AppColors.green;
    return Container(
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border, width: 0.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Stack(children: [
          Container(height: 110, decoration: BoxDecoration(
              color: typeColor.withOpacity(0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16))),
              child: post['photo_url'] != null
                  ? ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                      child: Image.network(post['photo_url'], fit: BoxFit.cover,
                          width: double.infinity,
                          errorBuilder: (_, __, ___) => const Center(
                              child: Icon(Icons.image_not_supported_outlined,
                                  color: AppColors.textMuted, size: 32))))
                  : Center(child: Icon(Icons.search, color: typeColor, size: 36))),
          Positioned(top: 8, right: 8, child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: typeColor, borderRadius: BorderRadius.circular(10)),
              child: Text(type.toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)))),
        ]),
        Padding(padding: const EdgeInsets.all(10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(post['title'] ?? '', style: AppTextStyles.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 3),
          Text(post['description'] ?? '', style: AppTextStyles.bodyMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.location_on_outlined, size: 11, color: AppColors.textSecondary),
            const SizedBox(width: 3),
            Expanded(child: Text(post['location_text'] ?? '', style: AppTextStyles.labelSmall,
                maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
        ])),
      ]),
    ).animate(delay: Duration(milliseconds: index * 60)).fadeIn().scale(begin: const Offset(0.95, 0.95));
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
  String _type = 'lost', _category = 'Electronics';
  XFile? _image;
  bool _loading = false;

  Future<void> _pickImage() async {
    final img = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (img != null) setState(() => _image = img);
  }

  Future<String?> _uploadToImgBB(XFile img) async {
    final bytes = await img.readAsBytes();
    final b64 = base64Encode(bytes);
    final res = await Dio().post(AppConfig.imgBBUrl,
        data: FormData.fromMap({'key': AppConfig.imgBBApiKey, 'image': b64}));
    return res.data['data']['url'] as String?;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      String? photoUrl;
      if (_image != null) photoUrl = await _uploadToImgBB(_image!);
      await SupabaseConfig.client.from('lost_found_posts').insert({
        'poster_id': SupabaseConfig.uid, 'type': _type,
        'title': _titleCtrl.text.trim(), 'description': _descCtrl.text.trim(),
        'category': _category, 'location_text': _locCtrl.text.trim(),
        'photo_url': photoUrl, 'status': 'active',
      });
      widget.onPosted();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AppColors.red));
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
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
            decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _image != null ? AppColors.green : AppColors.border)),
            child: _image != null
                ? ClipRRect(borderRadius: BorderRadius.circular(12),
                    child: Image.file(File(_image!.path), fit: BoxFit.cover))
                : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.add_photo_alternate_outlined, color: AppColors.textSecondary, size: 32),
                    const SizedBox(height: 6),
                    Text('Add photo (optional)', style: AppTextStyles.bodyMedium),
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
    return GestureDetector(onTap: () => onTap(value), child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(color: sel ? color.withOpacity(0.15) : AppColors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: sel ? color : AppColors.border)),
        child: Center(child: Text(label,
            style: TextStyle(color: sel ? color : AppColors.textSecondary, fontSize: 12,
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
      final res = await SupabaseConfig.client.from('lost_found_posts').select()
          .eq('poster_id', uid).order('created_at', ascending: false) as List;
      if (mounted) setState(() => _myPosts = res.cast());
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Padding(padding: EdgeInsets.all(16), child: ShimmerList());
    if (_myPosts.isEmpty) return EmptyState(icon: Icons.post_add_rounded,
        title: 'No posts yet', subtitle: 'Post a lost or found item from the Post tab');
    return ListView.builder(padding: const EdgeInsets.all(16), itemCount: _myPosts.length,
        itemBuilder: (ctx, i) {
          final p = _myPosts[i];
          final type = p['type'] as String? ?? 'lost';
          final color = type == 'lost' ? AppColors.red : AppColors.green;
          return Container(margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border, width: 0.5)),
              child: Row(children: [
                Container(width: 10, height: 50, decoration: BoxDecoration(
                    color: color, borderRadius: BorderRadius.circular(5))),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p['title'] ?? '', style: AppTextStyles.titleMedium),
                  Text(p['status'] ?? '', style: TextStyle(color: color, fontSize: 12)),
                ])),
                if (p['status'] == 'active') TextButton(
                    onPressed: () async {
                      await SupabaseConfig.client.from('lost_found_posts')
                          .update({'status': 'returned'}).eq('id', p['id']);
                      _load();
                    },
                    child: const Text('Mark Returned', style: TextStyle(fontSize: 11))),
              ]));
        });
  }
}
