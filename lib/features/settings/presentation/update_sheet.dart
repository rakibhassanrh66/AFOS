import 'package:flutter/material.dart';

import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../config/theme/depth.dart';
import '../../../config/theme/motion.dart';
import '../../../core/haptics/app_haptics.dart';
import '../../../core/services/app_update_service.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../../shared/widgets/glass_sheet.dart';

/// The update experience, as one surface instead of a tile and a snackbar.
///
/// WHY THIS REPLACES WHAT WAS THERE. Updating used to be: a small banner in
/// Settings, a tap, a percentage, and then Android's installer appearing with
/// no explanation. Every part worked; none of it told the user what they were
/// getting or what was happening to them. Sideloading already asks a lot of
/// trust from someone — an unsigned-looking prompt, a Play Protect warning, a
/// permission screen — and the app going quiet in the middle of that is what
/// makes people abandon the install.
///
/// So this states, in order: what version, what changed, how big the download
/// got, that the file was verified, and that Android is about to ask. The
/// motion exists to carry that progression, not to decorate it: each stage
/// animates because the stage genuinely changed.
///
/// WHAT IT DOES NOT DO. It does not promise the update is installed. Tapping
/// through to Android's installer is the last thing this app controls; the
/// user still confirms there. Claiming success at hand-off would be a lie the
/// user discovers ten seconds later.
enum _Stage { idle, downloading, verifying, handedOff, failed }

Future<void> showUpdateSheet(BuildContext context, AppUpdateInfo update) =>
    showGlassModal<void>(
      context,
      builder: (_) => _UpdateSheet(update: update),
    );

class _UpdateSheet extends StatefulWidget {
  final AppUpdateInfo update;
  const _UpdateSheet({required this.update});

  @override
  State<_UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends State<_UpdateSheet> {
  _Stage _stage = _Stage.idle;
  double _progress = 0;
  String? _error;

  Future<void> _start() async {
    setState(() {
      _stage = _Stage.downloading;
      _progress = 0;
      _error = null;
    });
    try {
      await AppUpdateService.downloadAndInstall(
        widget.update,
        onProgress: (p) {
          if (!mounted) return;
          setState(() {
            _progress = p;
            // The verify step is real work the service does after the bytes
            // land — a length check and a magic-number check. Showing it means
            // the pause at 100% has a name instead of looking like a freeze.
            if (p >= 1.0) _stage = _Stage.verifying;
          });
        },
      );
      if (!mounted) return;
      AppHaptics.success();
      setState(() => _stage = _Stage.handedOff);
    } catch (e) {
      if (!mounted) return;
      AppHaptics.warning();
      setState(() {
        _stage = _Stage.failed;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);

    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
          20, 8, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Grab handle — this sheet is dismissible, and a sheet that looks
        // modal but is not reads as a trap.
        Container(
          width: 44,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.borderOf(context),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 20),

        _UpdateBadge(stage: _stage, progress: _progress),
        const SizedBox(height: 20),

        Text(widget.update.title,
            textAlign: TextAlign.center,
            style: AppTextStyles.headlineLarge.copyWith(color: textPrimary)),
        const SizedBox(height: 6),
        Text('Version ${AppUpdateService.releasePart(widget.update.version)}',
            style: AppTextStyles.labelSmall.copyWith(color: textSecondary)),

        if (widget.update.highlights.isNotEmpty) ...[
          const SizedBox(height: 20),
          // Capped and scrollable: a release with fifteen highlights must not
          // push the Update button off a short phone.
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < widget.update.highlights.length; i++)
                    _Highlight(
                      text: widget.update.highlights[i],
                      // Staggered, capped, reduced-motion aware — the shared
                      // rule, not a local invention.
                      delay: AppMotion.staggerFor(context, i),
                    ),
                ],
              ),
            ),
          ),
        ],

        const SizedBox(height: 24),
        _StageFooter(
          stage: _stage,
          progress: _progress,
          error: _error,
          onStart: _start,
          onClose: () => Navigator.of(context).maybePop(),
        ),
      ]),
    );
  }
}

/// The badge at the top. One widget, four states, so the transition between
/// them is a single animation rather than a swap between unrelated widgets.
class _UpdateBadge extends StatelessWidget {
  final _Stage stage;
  final double progress;
  const _UpdateBadge({required this.stage, required this.progress});

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (stage) {
      _Stage.failed => (AppColors.red, Icons.error_outline_rounded),
      _Stage.handedOff => (AppColors.green, Icons.check_rounded),
      _Stage.verifying => (AppColors.amber, Icons.verified_outlined),
      _ => (AppColors.blue, Icons.system_update_alt_rounded),
    };

    return SizedBox(
      width: 96,
      height: 96,
      child: Stack(alignment: Alignment.center, children: [
        // The ring is the progress. It only appears while there IS progress —
        // an indeterminate ring during the idle state would imply the app is
        // already doing something.
        if (stage == _Stage.downloading || stage == _Stage.verifying)
          SizedBox(
            width: 96,
            height: 96,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: stage == _Stage.verifying ? 1 : progress),
              duration: AppMotion.durationOf(context, AppMotion.tight),
              curve: AppMotion.standard,
              builder: (_, value, __) => CircularProgressIndicator(
                value: stage == _Stage.verifying ? null : value,
                strokeWidth: 3,
                backgroundColor: AppColors.borderOf(context),
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
        AnimatedContainer(
          duration: AppMotion.durationOf(context, AppMotion.base),
          curve: AppMotion.standard,
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: AppDepth.radius(2),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: AnimatedSwitcher(
            duration: AppMotion.durationOf(context, AppMotion.tight),
            // Scale, not just fade: the icon changing meaning should feel like
            // a different thing arriving, not the same thing flickering.
            transitionBuilder: (child, anim) => ScaleTransition(
              scale: CurvedAnimation(parent: anim, curve: AppMotion.standard),
              child: FadeTransition(opacity: anim, child: child),
            ),
            child: Icon(icon, key: ValueKey(icon), color: color, size: 32),
          ),
        ),
      ]),
    );
  }
}

class _Highlight extends StatelessWidget {
  final String text;
  final Duration delay;
  const _Highlight({required this.text, required this.delay});

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(top: 6, end: 10),
          child: Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
                color: AppColors.green, shape: BoxShape.circle),
          ),
        ),
        Expanded(
          child: Text(text,
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textSecondaryOf(context))),
        ),
      ]),
    );

    if (AppMotion.isReduced(context)) return row;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppMotion.base + delay,
      curve: Interval(
        // Turns the delay into the leading dead zone of one tween, so a list of
        // highlights arrives in sequence without one controller per row.
        (delay.inMilliseconds / (AppMotion.base + delay).inMilliseconds)
            .clamp(0.0, 0.9),
        1,
        curve: AppMotion.standard,
      ),
      builder: (_, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, (1 - v) * 8), child: child),
      ),
      child: row,
    );
  }
}

/// The button row, which says something different at every stage.
class _StageFooter extends StatelessWidget {
  final _Stage stage;
  final double progress;
  final String? error;
  final VoidCallback onStart;
  final VoidCallback onClose;

  const _StageFooter({
    required this.stage,
    required this.progress,
    required this.error,
    required this.onStart,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final textSecondary = AppColors.textSecondaryOf(context);

    return AnimatedSize(
      duration: AppMotion.durationOf(context, AppMotion.base),
      curve: AppMotion.standard,
      child: switch (stage) {
        _Stage.idle => Column(children: [
            AfosButton(
                label: 'Download & install',
                icon: Icons.download_rounded,
                onTap: onStart),
            const SizedBox(height: 8),
            TextButton(
              onPressed: onClose,
              child: Text('Not now', style: TextStyle(color: textSecondary)),
            ),
          ]),
        _Stage.downloading => Column(children: [
            Text('${(progress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                style: AppTextStyles.headlineLarge
                    .copyWith(color: AppColors.textPrimaryOf(context))),
            const SizedBox(height: 4),
            Text('Downloading — you can leave this open',
                style: AppTextStyles.labelSmall.copyWith(color: textSecondary)),
          ]),
        _Stage.verifying => Column(children: [
            Text('Checking the file',
                style: AppTextStyles.titleMedium
                    .copyWith(color: AppColors.textPrimaryOf(context))),
            const SizedBox(height: 4),
            Text('Making sure the download finished and is a real app file',
                textAlign: TextAlign.center,
                style: AppTextStyles.labelSmall.copyWith(color: textSecondary)),
          ]),
        // The honest end state. The installer is open; this app does not know
        // and must not claim what happens next.
        _Stage.handedOff => Column(children: [
            Text('Android is asking now',
                style: AppTextStyles.titleMedium
                    .copyWith(color: AppColors.textPrimaryOf(context))),
            const SizedBox(height: 6),
            Text(
              'Tap Install, then Open. Your account stays signed in — only the '
              'cached copies of pages are cleared, and they come straight back.',
              textAlign: TextAlign.center,
              style: AppTextStyles.labelSmall.copyWith(color: textSecondary),
            ),
            const SizedBox(height: 12),
            // The one refusal the app cannot catch for you.
            //
            // A signature mismatch is rejected by Android's package installer
            // AFTER we hand off, so `downloadAndInstall` returns success and
            // nothing here ever hears about it — the user is left on a dead end
            // reading "App not installed as package conflicts with an existing
            // package" with no idea that it means "you have a differently
            // signed build". It only happens to someone who installed a debug
            // or profile copy at some point, but for them it is unfixable
            // guesswork without this sentence.
            DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.amber.withValues(alpha: 0.10),
                borderRadius: AppDepth.radius(1),
                border: Border.all(color: AppColors.amber.withValues(alpha: 0.3)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Text(
                  'If Android says the package conflicts with an existing one, '
                  'a differently signed copy of AFOS is installed. Uninstall it '
                  'first, then install this — you will sign in once, and nothing '
                  'on the server is lost.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.labelSmall.copyWith(color: textSecondary),
                ),
              ),
            ),
            const SizedBox(height: 14),
            AfosButton(label: 'Done', outlined: true, onTap: onClose),
          ]),
        _Stage.failed => Column(children: [
            Text(error ?? 'That did not work.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.red)),
            const SizedBox(height: 14),
            AfosButton(
                label: 'Try again', icon: Icons.refresh_rounded, onTap: onStart),
            const SizedBox(height: 8),
            TextButton(
              onPressed: onClose,
              child: Text('Close', style: TextStyle(color: textSecondary)),
            ),
          ]),
      },
    );
  }
}
