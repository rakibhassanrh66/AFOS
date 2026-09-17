import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../config/theme/app_colors.dart';
import '../../../../config/theme/app_text_styles.dart';
import '../../../../config/theme/depth.dart';
import '../../../../config/theme/liquid_glass_tokens.dart';
import '../../../../config/theme/motion.dart';
import '../../../../config/theme/spacing.dart';
import '../../../../core/haptics/app_haptics.dart';
import '../../../../shared/widgets/signature_shape.dart';
import 'about_ink.dart';

/// The About screen's card surface.
///
/// DELIBERATELY NOT [AppDepth.surface]. That helper pairs a *directional*
/// [AppDepth.rim] — a lit top-left edge against a darker bottom-right, which is
/// the constitution's single-light-source rule expressed as a border — with a
/// `borderRadius`. Flutter refuses that combination outright ("A borderRadius
/// can only be given on uniform borders") and throws on first paint, at every
/// screen size and text scale. Both `AppDepth.surface` and `AppDepth.rim` have
/// **no call sites in `lib/`**, so nothing in the app had ever painted one and
/// nothing had ever caught it; the layout sweep on this card is what found it.
/// Fixing depth.dart is outside this change's file scope, so this routes around
/// it instead — see REDESIGN_LOG.
///
/// What this uses is the same ShapeDecoration + [SignatureBorder] route
/// [GlassCard] already takes for its own border, so the AFOS silhouette (three
/// round corners, top-right cut tight) survives and the shadow still falls
/// down-and-right from AppDepth's one light.
ShapeDecoration aboutSurface(BuildContext context,
        {Color? color, Color? rim, int level = 2}) =>
    ShapeDecoration(
      color: color ?? AppColors.surfaceOf(context),
      shape: SignatureBorder(
        // RADIUS ENCODES ELEVATION, which is the whole reason the scale exists.
        // The dedication is the hero surface on this page and sits at the sheet
        // tier (28); the two profile cards are ordinary cards (22). Before
        // this, every surface on the screen was the same radius and the same
        // shadow, so nothing said which one to read first.
        radius: level >= 3 ? LiquidGlass.radiusSheet : LiquidGlass.radiusCard,
        side: BorderSide(color: rim ?? AppColors.borderOf(context), width: 1),
      ),
      shadows: AppDepth.shadow(level, isDark: AppColors.isDark(context)),
    );

/// [child] wrapped so a change in its height is tweened — or handed straight
/// back, unwrapped, when the reader has asked for no motion.
///
/// The second case is the point. `RenderAnimatedSize` drives its own
/// controller from inside `performLayout`; handed `Duration.zero` that
/// controller completes synchronously and marks the render object dirty while
/// it is still laying itself out, tripping "A RenderAnimatedSize was mutated in
/// its own performLayout implementation." So the usual
/// [AppMotion.durationOf] treatment is wrong here — a zero-length animation and
/// no animation are not the same thing, and only the second is legal.
Widget animatedHeight(BuildContext context, Widget child) =>
    AppMotion.isReduced(context)
        ? child
        : AnimatedSize(
            duration: AppMotion.base,
            curve: AppMotion.inOut,
            alignment: Alignment.topCenter,
            child: child,
          );

/// A portrait that arrives the way a photograph develops: grey first, then
/// colour.
///
/// WHY NOT A PLAIN FADE. A fade says "this element loaded". A desaturation
/// ramp says "this is a photograph of a person", which is the only thing on
/// this screen that is neither UI nor copy. It is one gesture, on mount, on the
/// motion ladder — not a loop, so it costs nothing after the first 380ms.
///
/// The frame is [SignatureBorder], the same silhouette every card in the app
/// uses, rather than the circle every other credits screen reaches for. That is
/// the cheapest way to make this page read as drawn by the same hand as the
/// rest of AFOS.
class DevelopingPhoto extends StatelessWidget {
  final String asset;
  final double size;
  final Color accent;

  const DevelopingPhoto({
    super.key,
    required this.asset,
    required this.size,
    required this.accent,
  });

  /// The radius tier this box belongs to.
  ///
  /// [LiquidGlass.radiusCard] is 22. On the 96px portrait that reads as the
  /// AFOS silhouette. On the 40px thumbnail on the reverse, 22 is more than
  /// half the box, so all three "rounded" corners collapse into one another and
  /// the shape stops being the silhouette and becomes a blob — visibly a
  /// different family from every other surface on the page. The control tier
  /// (14) is the right answer at that size, and it is already on the radius
  /// scale.
  double get _radius =>
      size >= 64 ? LiquidGlass.radiusCard : LiquidGlass.radiusControl;

  /// Every instance decodes at the SAME extent, whatever it is drawn at.
  ///
  /// `cacheWidth` is part of the image cache key, so a 96px portrait and a 40px
  /// thumbnail of the same file are two separate decodes. The thumbnail only
  /// appears once the card has been turned over — at which point it decodes
  /// from cold and the header shows an empty box for a frame or two, right in
  /// the middle of a deliberate animation. Decoding both at the larger extent
  /// costs one cache entry instead of two and makes the thumbnail instant.
  static const double _decodeExtent = 96;

  /// Luminance-weighted saturation matrix. [s] of 0 is fully grey, 1 is the
  /// untouched image. The coefficients are Rec. 709, so the grey stage keeps
  /// the face's tonal structure instead of flattening it the way a naive
  /// average does.
  static List<double> _saturation(double s) {
    const lr = 0.2126, lg = 0.7152, lb = 0.0722;
    final r = (1 - s) * lr, g = (1 - s) * lg, b = (1 - s) * lb;
    return <double>[
      r + s, g, b, 0, 0, //
      r, g + s, b, 0, 0, //
      r, g, b + s, 0, 0, //
      0, 0, 0, 1, 0, //
    ];
  }

  @override
  Widget build(BuildContext context) {
    // Law: images decode at the size they are drawn. rakib.jpg is 1414px
    // square; without this it would hold ~8 MB of decoded ARGB for a 96px box.
    final cacheWidth =
        (math.max(size, _decodeExtent) * MediaQuery.devicePixelRatioOf(context))
            .round();

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: AppMotion.durationOf(context, AppMotion.slow),
      curve: AppMotion.standard,
      builder: (context, t, child) => Transform.scale(
        scale:
            AppMotion.entranceScaleFrom + (1 - AppMotion.entranceScaleFrom) * t,
        child: ColorFiltered(
          colorFilter: ColorFilter.matrix(_saturation(t)),
          child: child,
        ),
      ),
      child: Container(
        width: size,
        height: size,
        decoration: ShapeDecoration(
          shape: SignatureBorder(
            radius: _radius,
            side: BorderSide(color: accent.withValues(alpha: 0.45), width: 1),
          ),
          shadows: AppDepth.shadow(2, isDark: AppColors.isDark(context)),
        ),
        child: ClipPath(
          clipper: ShapeBorderClipper(
            shape: SignatureBorder(radius: _radius),
          ),
          child: Image.asset(
            asset,
            width: size,
            height: size,
            fit: BoxFit.cover,
            cacheWidth: cacheWidth,
            // A missing asset must not take the whole screen down with it.
            errorBuilder: (context, _, __) => ColoredBox(
              color: accent.withValues(alpha: 0.12),
              child:
                  Icon(Icons.person_rounded, size: size * 0.5, color: accent),
            ),
          ),
        ),
      ),
    );
  }
}

/// A person, as a card you turn over.
///
/// The front is who they are at a glance. The back is the long version — the
/// part someone only reads if they chose to. Putting the story on the reverse
/// is not decoration: it means the page can carry several hundred words of
/// someone's life without the screen opening as a wall of text.
///
/// MOTION. One Y-rotation over [AppMotion.slow], swapping faces at the
/// half-turn where the card is edge-on, with the height change riding the same
/// moment so the card appears to turn and unfold together. Reduced motion
/// collapses both to zero and the faces simply swap — the control still works,
/// it just does not spin.
///
/// DELIBERATELY NOT GLASS. Every other card in AFOS is a [GlassCard]. This one
/// is an opaque [aboutSurface], because a `BackdropFilter` inside a widget
/// being rotated in 3D has to re-sample the blurred backdrop every frame of the
/// turn, on a surface whose projected geometry changes each frame — the exact
/// shape of this project's documented per-row-blur jank. The shell's blur is
/// still behind it, so the page reads as glass; the moving part does not add
/// another.
class FlipProfileCard extends StatefulWidget {
  final String name;
  final String role;
  final String photoAsset;
  final Color accent;
  final List<String> tags;

  /// The reverse. Chrome (thumbnail, name, the way back) is supplied by this
  /// widget; [back] is only the body.
  final Widget back;

  /// What the front says on its bottom rule — the invitation to turn it over.
  final String flipLabel;

  const FlipProfileCard({
    super.key,
    required this.name,
    required this.role,
    required this.photoAsset,
    required this.accent,
    required this.tags,
    required this.back,
    this.flipLabel = 'Read the long version',
  });

  @override
  State<FlipProfileCard> createState() => _FlipProfileCardState();
}

class _FlipProfileCardState extends State<FlipProfileCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: AppMotion.slow,
  );

  /// Perspective divisor for the 3D turn. Not a design token — it is a camera
  /// constant, and the scale is metres-per-pixel rather than anything on the
  /// spacing ladder. Larger values exaggerate the foreshortening until the card
  /// looks like it is falling away from the reader.
  static const double _perspective = 0.0012;

  bool get _showingBack => _turn.value >= 0.5;

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  void _flip() {
    // Reduced motion is read at the moment of the gesture, not at construction,
    // so toggling the OS setting takes effect without a restart.
    _turn.duration = AppMotion.durationOf(context, AppMotion.slow);
    AppHaptics.selection();
    if (_showingBack) {
      _turn.reverse();
    } else {
      _turn.forward();
    }
  }

  /// The card's own fill: the theme surface, barely tinted toward the
  /// person's accent. Named because contrast has to be measured against what
  /// the text actually sits on, not against the plain theme surface.
  Color _surfaceColor(BuildContext context) => Color.alphaBlend(
        widget.accent.withValues(alpha: 0.05),
        AppColors.surfaceOf(context),
      );

  @override
  Widget build(BuildContext context) {
    final surface = _surfaceColor(context);

    return Semantics(
      button: true,
      label: '${widget.name}. ${widget.role}',
      value: _showingBack ? 'Showing full profile' : 'Showing summary',
      hint: _showingBack ? 'Turn the card back' : 'Turn the card over',
      onTap: _flip,
      child: ExcludeSemantics(
        // The tap target is NOT the whole card any more. On the front it is —
        // the whole surface is the invitation. On the back only the header row
        // turns it over, because the body below it now scrolls, and a surface
        // that both scrolls and flips under the same finger will eventually
        // flip when someone meant to scroll. Reading must not be interruptible
        // by accident.
        // Under reduced motion the AnimatedSize is REMOVED, not given a zero
        // duration. `RenderAnimatedSize` drives its own controller from
        // inside `performLayout`; with `Duration.zero` that controller
        // completes synchronously and marks the render object dirty while it
        // is still laying itself out, which trips
        // "A RenderAnimatedSize was mutated in its own performLayout
        // implementation." A zero-length animation and no animation are not
        // the same thing here — only the second one is legal.
        child: animatedHeight(
          context,
          AnimatedBuilder(
            animation: _turn,
            builder: (context, _) {
              final angle = _turn.value * math.pi;
              final back = _showingBack;
              return Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, _perspective)
                  ..rotateY(angle),
                child: Transform(
                  // The reverse is drawn mirrored so that, once the card has
                  // turned past edge-on, its text reads the right way round.
                  alignment: Alignment.center,
                  transform: back
                      ? (Matrix4.identity()..rotateY(math.pi))
                      : Matrix4.identity(),
                  child: Container(
                    width: double.infinity,
                    padding: AppSpace.allLg,
                    decoration: aboutSurface(context,
                        color: surface,
                        rim: widget.accent.withValues(alpha: 0.22)),
                    child: back
                        ? _buildBack(context, surface)
                        : _buildFront(context),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------- front

  Widget _buildFront(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    final ink = readableOn(widget.accent, _surfaceColor(context));

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _flip,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DevelopingPhoto(
                  asset: widget.photoAsset, size: 96, accent: widget.accent),
              AppSpace.gapLg,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.name,
                        style: AppTextStyles.headlineMed
                            .copyWith(color: textPrimary)),
                    AppSpace.vGapXs,
                    Text(widget.role,
                        style: AppTextStyles.bodyMedium
                            .copyWith(color: textSecondary, height: 1.45)),
                  ],
                ),
              ),
            ],
          ),
          if (widget.tags.isNotEmpty) ...[
            AppSpace.vGapMd,
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                for (final tag in widget.tags) _Tag(tag, accent: widget.accent),
              ],
            ),
          ],
          AppSpace.vGapMd,
          Divider(height: 1, thickness: 1, color: AppColors.borderOf(context)),
          AppSpace.vGapMd,
          Row(
            children: [
              Expanded(
                child: Text(widget.flipLabel,
                    style: AppTextStyles.labelSmall
                        .copyWith(color: ink, letterSpacing: 0.3)),
              ),
              Icon(Icons.flip_to_back_rounded, size: 16, color: ink),
            ],
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------- back

  Widget _buildBack(BuildContext context, Color surface) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textMuted = aboutMuted(context);
    final ink = readableOn(widget.accent, surface);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The header is the whole of the way back, and it is a full-width
        // target rather than just the small icon at its end.
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _flip,
          // The header is the ONLY way back from the reverse, so it has to
          // clear the 48dp floor by itself. The photo inside it is 40, and at
          // 1.0x with a short name the row would otherwise land at exactly 40.
          child: Container(
            constraints:
                const BoxConstraints(minHeight: AppSpace.minTouchTarget),
            alignment: AlignmentDirectional.centerStart,
            child: Row(
              children: [
                DevelopingPhoto(
                    asset: widget.photoAsset, size: 40, accent: widget.accent),
                AppSpace.gapMd,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.name,
                          style: AppTextStyles.titleLarge
                              .copyWith(color: textPrimary)),
                      Text('Tap here to turn back',
                          style: AppTextStyles.labelSmall
                              .copyWith(color: textMuted)),
                    ],
                  ),
                ),
                Icon(Icons.flip_to_front_rounded, size: 16, color: ink),
              ],
            ),
          ),
        ),
        AppSpace.vGapMd,
        Divider(height: 1, thickness: 1, color: AppColors.borderOf(context)),
        AppSpace.vGapLg,
        // The reverse lays out at its FULL height and the PAGE scrolls it.
        //
        // It used to be capped at a fraction of the viewport with its own
        // scroll view inside, which was wrong in a way that only shows up on a
        // real device. Two scrollables sharing one surface do not chain in
        // Flutter: once the card's inner scroll reached its end, a drag
        // starting on the card was consumed and the page underneath never
        // moved. On a screen inside the app shell — where a floating nav bar
        // covers the bottom ~80px — that left the last lines of the card
        // wedged under the bar with no gesture that could free them. The
        // content was there and unreachable.
        //
        // One scroll axis, one gesture owner. The page's bottom padding already
        // clears the nav bar (NavInsets), so growing the card is what makes the
        // whole of it readable.
        widget.back,
      ],
    );
  }
}

/// A credential, at label size. Pill radius, because the radius scale encodes
/// elevation class and a chip is flush with its parent.
class _Tag extends StatelessWidget {
  final String label;
  final Color accent;
  const _Tag(this.label, {required this.accent});

  @override
  Widget build(BuildContext context) {
    // The chip fill is a 10% tint of the accent and the label is the accent
    // itself -- the lowest-contrast pairing on the screen (1.80:1 in light
    // mode before this). Measured against the FILL, since that is what is
    // actually behind the glyphs.
    final ink = readableOn(
      accent,
      Color.alphaBlend(
        accent.withValues(alpha: 0.10),
        AppColors.surfaceOf(context),
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.md, vertical: AppSpace.xs),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(LiquidGlass.radiusPill),
        border: Border.all(color: accent.withValues(alpha: 0.28), width: 1),
      ),
      child: Text(label,
          style: AppTextStyles.labelSmall
              .copyWith(color: ink, fontWeight: FontWeight.w600)),
    );
  }
}
