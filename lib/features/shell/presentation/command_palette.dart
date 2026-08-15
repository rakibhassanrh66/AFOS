import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../config/theme/depth.dart';
import '../../../config/theme/motion.dart';
import '../../../core/navigation/nav_destinations.dart';

/// Ctrl/Cmd+K — jump to anywhere in the app from the keyboard.
///
/// WHY THIS IS WEB-ONLY, and why that is not laziness. A command palette is
/// worth building only where there is a keyboard to summon it and a pointer to
/// abandon. On a phone, the same job is done better by the bottom bar and the
/// slide menu, which are already there and already one thumb away. Shipping a
/// palette to Android would add a code path nobody can open.
///
/// It is mounted behind `kIsWeb`, which is a compile-time constant, so the AOT
/// Android build eliminates the branch and this file's cost to the APK is zero.
/// Phase 6's rule is that the APK must not grow, and it is verified by
/// measuring the APK, not by asserting it here.
///
/// WHAT IT DELIBERATELY IS NOT. It does not search data — no notices, no books,
/// no students. That is `/search`, which already exists and already runs the
/// cross-module queries; a second implementation of it here would be a second
/// place for those queries to drift. This is a NAVIGATION palette: it answers
/// "where can I go and how fast can I get there", instantly and offline,
/// and it hands anything else off to `/search` with the query intact.
///
/// The destinations come from [navDestinations], which the slide menu publishes
/// after applying the role matrix and the delegated grants — so the palette can
/// never offer a route the router would refuse.
class CommandPalette extends StatefulWidget {
  const CommandPalette({super.key});

  /// Opens the palette. Safe to call when one is already open — the shortcut
  /// action guards against that so Ctrl+K twice does not stack two dialogs.
  static Future<void> show(BuildContext context) => showGeneralDialog(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Dismiss',
        barrierColor: Colors.black.withValues(alpha: 0.45),
        // Fast: a palette that fades in slowly defeats the point of a keyboard
        // shortcut, which is that it is quicker than reaching for the menu.
        transitionDuration: AppMotion.tight,
        pageBuilder: (_, __, ___) => const CommandPalette(),
        transitionBuilder: (ctx, anim, __, child) {
          final curved = CurvedAnimation(parent: anim, curve: AppMotion.standard);
          return FadeTransition(
            opacity: curved,
            // Drops in a little rather than scaling: a palette that grows out
            // of the centre reads as a modal interruption; one that arrives
            // from above reads as a tool being pulled down.
            child: SlideTransition(
              position: Tween(begin: const Offset(0, -0.04), end: Offset.zero)
                  .animate(curved),
              child: child,
            ),
          );
        },
      );

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  int _selected = 0;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<NavDestination> get _results =>
      rankDestinations(navDestinations.value, _controller.text);

  void _move(int delta) {
    final results = _results;
    if (results.isEmpty) return;
    setState(() {
      // Wraps. Holding Down at the end of a short list and having nothing
      // happen is the kind of dead end a keyboard user notices immediately.
      _selected = (_selected + delta) % results.length;
      if (_selected < 0) _selected += results.length;
    });
    // Keep the highlighted row on screen. 44 is the row height below; using
    // the real extent rather than a guess is why this does not drift.
    if (_scroll.hasClients) {
      _scroll.animateTo(
        (_selected * 44.0).clamp(0, _scroll.position.maxScrollExtent),
        duration: AppMotion.instant,
        curve: AppMotion.standard,
      );
    }
  }

  void _commit() {
    final results = _results;
    if (results.isEmpty) {
      // Nothing matched a destination — hand the typed text to the real search
      // rather than dead-ending on "no results".
      final q = _controller.text.trim();
      Navigator.of(context).pop();
      context.go(q.isEmpty ? '/search' : '/search?q=${Uri.encodeComponent(q)}');
      return;
    }
    final target = results[_selected.clamp(0, results.length - 1)];
    Navigator.of(context).pop();
    context.go(target.route);
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    final surface = AppColors.surfaceOf(context);
    final border = AppColors.borderOf(context);

    return Align(
      // Near the top, not centred: this is a tool you summon, use and dismiss,
      // and the eye is already at the top of a page.
      alignment: const Alignment(0, -0.55),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 460),
          child: Material(
            color: Colors.transparent,
            child: Shortcuts(
              shortcuts: const {
                SingleActivator(LogicalKeyboardKey.arrowDown): _MoveIntent(1),
                SingleActivator(LogicalKeyboardKey.arrowUp): _MoveIntent(-1),
                // Ctrl+N/P, because anyone who reaches for Ctrl+K also has
                // these in their fingers from every other palette.
                SingleActivator(LogicalKeyboardKey.keyN, control: true): _MoveIntent(1),
                SingleActivator(LogicalKeyboardKey.keyP, control: true): _MoveIntent(-1),
                SingleActivator(LogicalKeyboardKey.enter): _CommitIntent(),
                SingleActivator(LogicalKeyboardKey.escape): _CloseIntent(),
              },
              child: Actions(
                actions: {
                  _MoveIntent: CallbackAction<_MoveIntent>(
                      onInvoke: (i) => _move(i.delta)),
                  _CommitIntent:
                      CallbackAction<_CommitIntent>(onInvoke: (_) => _commit()),
                  _CloseIntent: CallbackAction<_CloseIntent>(
                      onInvoke: (_) => Navigator.of(context).maybePop()),
                },
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: AppDepth.radius(3),
                    border: Border.all(color: border),
                    boxShadow: AppDepth.shadow(4, isDark: AppColors.isDark(context)),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                      child: Row(children: [
                        Icon(Icons.search_rounded,
                            size: 20, color: AppColors.textSecondaryOf(context)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            focusNode: _focus,
                            autofocus: true,
                            style: AppTextStyles.bodyMedium
                                .copyWith(color: AppColors.textPrimaryOf(context)),
                            decoration: InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              hintText: 'Go to…',
                              hintStyle: AppTextStyles.bodyMedium.copyWith(
                                  color: AppColors.textMutedOf(context)),
                            ),
                            onChanged: (_) => setState(() => _selected = 0),
                            onSubmitted: (_) => _commit(),
                          ),
                        ),
                        const _Key(label: 'Esc'),
                      ]),
                    ),
                    Divider(height: 1, color: border),
                    Flexible(
                      child: results.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                'No destination matches that. Press Enter to '
                                'search everything instead.',
                                textAlign: TextAlign.center,
                                style: AppTextStyles.labelSmall.copyWith(
                                    color: AppColors.textSecondaryOf(context)),
                              ),
                            )
                          : ListView.builder(
                              controller: _scroll,
                              shrinkWrap: true,
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              itemCount: results.length,
                              itemExtent: 44,
                              itemBuilder: (_, i) => _Row(
                                destination: results[i],
                                selected: i == _selected,
                                onTap: () {
                                  setState(() => _selected = i);
                                  _commit();
                                },
                              ),
                            ),
                    ),
                    Divider(height: 1, color: border),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      child: Row(children: [
                        const _Key(label: '↑↓'),
                        const SizedBox(width: 6),
                        Text('navigate',
                            style: AppTextStyles.labelSmall
                                .copyWith(color: AppColors.textMutedOf(context))),
                        const SizedBox(width: 14),
                        const _Key(label: '↵'),
                        const SizedBox(width: 6),
                        Text('open',
                            style: AppTextStyles.labelSmall
                                .copyWith(color: AppColors.textMutedOf(context))),
                        const Spacer(),
                        Text('${results.length} destination${results.length == 1 ? '' : 's'}',
                            style: AppTextStyles.labelSmall
                                .copyWith(color: AppColors.textMutedOf(context))),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final NavDestination destination;
  final bool selected;
  final VoidCallback onTap;
  const _Row({required this.destination, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected
            ? AppColors.accentOf(context).withValues(alpha: 0.12)
            : Colors.transparent,
        padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 0),
        child: Row(children: [
          Icon(destination.icon, size: 18, color: destination.color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(destination.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textPrimaryOf(context),
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
          ),
          Text(destination.route,
              style: AppTextStyles.labelSmall
                  .copyWith(color: AppColors.textMutedOf(context))),
        ]),
      ),
    );
  }
}

/// A keycap. Small, quiet, and the thing that teaches the shortcut exists.
class _Key extends StatelessWidget {
  final String label;
  const _Key({required this.label});

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.glassFill(context),
          borderRadius: AppDepth.radius(0),
          border: Border.all(color: AppColors.borderOf(context)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Text(label,
              style: AppTextStyles.labelSmall
                  .copyWith(color: AppColors.textSecondaryOf(context))),
        ),
      );
}

class _MoveIntent extends Intent {
  final int delta;
  const _MoveIntent(this.delta);
}

class _CommitIntent extends Intent {
  const _CommitIntent();
}

class _CloseIntent extends Intent {
  const _CloseIntent();
}
