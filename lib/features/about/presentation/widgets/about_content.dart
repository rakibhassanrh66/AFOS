import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import '../../../../config/theme/app_text_styles.dart';

import '../../../../config/theme/app_colors.dart';
import '../../../../config/theme/liquid_glass_tokens.dart';
import '../../../../config/theme/spacing.dart';
import '../../../../core/haptics/app_haptics.dart';
import 'about_ink.dart';
import 'flip_profile_card.dart';

/// The typographic pieces the About screen is assembled from.
///
/// WHY THESE ARE PUBLIC AND IN THEIR OWN FILE. They were private classes inside
/// `about_screen.dart`, which meant the only way to reach them was to build the
/// whole screen — and the screen needs an app bar that needs a signed-in role,
/// so in practice nothing reached them at all. Three of them pair a
/// FIXED-WIDTH column with an `Expanded` sibling, which is precisely the shape
/// this project's layout probe exists to catch: at 2.0x text scale on a 320px
/// phone the fixed column does not shrink, and the text beside it is handed
/// what is left. `layout_probe.dart` opens with the note that this exact fault
/// "shipped twice". Being reachable from a test is the whole point.

/// Splits `**bold**` runs out of [text] into styled spans.
///
/// WHY A MARKER AND NOT A LIST OF SPANS AT THE CALL SITE. The copy on this
/// screen is somebody's account of their own life, and it was written as prose
/// with emphasis in it. Storing that as `['plain', 'bold', 'plain']` makes the
/// source unreadable and turns an edit into a refactor. One marker keeps the
/// paragraph legible in the file, which is where it will actually be revised.
///
/// Deliberately NOT a Markdown parser: `**` is the only thing understood, and
/// an odd number of markers renders the tail emphasised rather than throwing.
/// A test asserts that the copy this screen ships is balanced.
List<TextSpan> emphasisSpans(String text, TextStyle base, TextStyle strong) {
  final parts = text.split('**');
  return [
    for (var i = 0; i < parts.length; i++)
      if (parts[i].isNotEmpty)
        TextSpan(text: parts[i], style: i.isOdd ? strong : base),
  ];
}

/// Body copy at reading measure, with `**emphasis**` honoured.
///
/// Paragraphs are separated by blank lines inside one string rather than by a
/// Column of Texts, which keeps the passage selectable and searchable as a
/// single block -- it is somebody's account of their life, not a list.
///
/// Emphasis lifts BOTH weight and colour. Bold alone, in the same muted
/// secondary ink the paragraph uses, barely registers; the emphasised run steps
/// up to the primary text colour, which is what makes a lede or a closing line
/// actually land.
class AboutProse extends StatelessWidget {
  final String text;
  const AboutProse(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final base = AppTextStyles.bodyLarge
        .copyWith(color: AppColors.textSecondaryOf(context), height: 1.65);
    return Text.rich(TextSpan(
      children: emphasisSpans(
        text,
        base,
        base.copyWith(
            color: AppColors.textPrimaryOf(context),
            fontWeight: FontWeight.w700),
      ),
    ));
  }
}

/// The one heading style used INSIDE a card, so the reverse has a rhythm of its
/// own without competing with the page headings outside it.
class AboutMicroHeading extends StatelessWidget {
  final String text;
  const AboutMicroHeading(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Text(text,
      style: AppTextStyles.labelSmall.copyWith(
          color: aboutMuted(context),
          letterSpacing: 1.4,
          fontWeight: FontWeight.w700));
}

/// A numbered list of things somebody did, a title and a sentence each.
///
/// Numbered rather than bulleted because these are a COUNT — a few specific
/// contributions, not an open-ended set of nice qualities. A reader can hold
/// three things and go and check them.
class AboutPoints extends StatelessWidget {
  final String heading;
  final List<({String title, String detail})> points;
  final Color accent;
  const AboutPoints(this.heading, this.points,
      {required this.accent, super.key});

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textMuted = aboutMuted(context);
    final ink = readableOn(accent, AppColors.surfaceOf(context));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AboutMicroHeading(heading),
        AppSpace.vGapMd,
        for (var i = 0; i < points.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The ordinal column does not grow with text scale, so it is
                // kept to one on-scale step rather than sized for the glyph.
                SizedBox(
                  width: AppSpace.xl,
                  child: Text('${i + 1}',
                      style: AppTextStyles.numericSmall
                          .copyWith(color: ink, fontWeight: FontWeight.w700)),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(points[i].title,
                          style: AppTextStyles.titleMedium
                              .copyWith(color: textPrimary)),
                      Text(points[i].detail,
                          style: AppTextStyles.bodyMedium
                              .copyWith(color: textMuted, height: 1.5)),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A plain list of facts, in the order they were given, with `**emphasis**`.
///
/// WHY THIS REPLACED A TIMELINE. The first version of this screen sorted the
/// same material into a `when / where / what` table, which looks tidy and is
/// the wrong shape for it: half the entries have no year (a major, a set of
/// certifications), one is an ending rather than a role, and the ORDER the
/// author put them in is itself information. Forcing them into columns meant
/// inventing a taxonomy for somebody else's life. A list keeps their sequence
/// and their emphasis exactly as written.
class AboutFactList extends StatelessWidget {
  final String heading;
  final List<String> items;
  final Color accent;
  const AboutFactList(this.heading, this.items,
      {required this.accent, super.key});

  @override
  Widget build(BuildContext context) {
    final base = AppTextStyles.bodyMedium
        .copyWith(color: aboutMuted(context), height: 1.5);
    final strong = base.copyWith(
        color: AppColors.textPrimaryOf(context), fontWeight: FontWeight.w700);
    final ink = readableOn(accent, AppColors.surfaceOf(context));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AboutMicroHeading(heading),
        AppSpace.vGapMd,
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The marker sits on the FIRST line rather than centring on the
                // row, so a three-line entry does not push it halfway down the
                // paragraph. The top inset is optical alignment to a glyph, not
                // a gap between things, which is why it is not on the spacing
                // scale.
                Padding(
                  padding: const EdgeInsetsDirectional.only(top: 7),
                  child: Container(
                    width: AppSpace.xs,
                    height: AppSpace.xs,
                    decoration: BoxDecoration(
                      color: ink,
                      borderRadius: BorderRadius.circular(AppSpace.xs),
                    ),
                  ),
                ),
                AppSpace.gapMd,
                Expanded(
                  child: Text.rich(
                      TextSpan(children: emphasisSpans(item, base, strong))),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Acronyms, spelled out.
///
/// The front of each card carries these as bare chips, which is right for a
/// glance and useless to anyone who does not already know what NSDA is. The
/// reverse has room to say. Someone who wants to check a claim needs the words
/// behind the initials in order to have something to search for.
class AboutGlossary extends StatelessWidget {
  final String heading;
  final List<({String short, String long})> entries;
  const AboutGlossary(this.heading, this.entries, {super.key});

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textMuted = aboutMuted(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AboutMicroHeading(heading),
        AppSpace.vGapMd,
        for (final e in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Wide enough for 'Exterminators' at 1.0x and allowed to wrap
                // rather than starve its neighbour beyond that. A fixed column
                // is the right call here — the whole value of the layout is
                // that the short forms line up — but it is sized against the
                // longest real entry, not guessed.
                SizedBox(
                  width: 88,
                  child: Text(e.short,
                      style: AppTextStyles.monoSmall.copyWith(
                          color: textPrimary, fontWeight: FontWeight.w600)),
                ),
                AppSpace.gapMd,
                Expanded(
                  child: Text(e.long,
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: textMuted, height: 1.45)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The sentence the whole app came out of.
///
/// Set against a vertical accent rule rather than a giant quotation glyph: the
/// rule is a typographic convention for reported speech, costs no glyph
/// metrics, and does not read as a decorative sticker the way an oversized “
/// does.
class AboutDedication extends StatelessWidget {
  final String quote;
  final String translation;
  const AboutDedication(
      {required this.quote, required this.translation, super.key});

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textMuted = aboutMuted(context);
    // The colour this block actually paints on, so contrast is measured
    // against the real background rather than the theme's plain surface.
    final surface = Color.alphaBlend(
      AppColors.green.withValues(alpha: 0.06),
      AppColors.surfaceOf(context),
    );

    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpace.lg, AppSpace.lg, AppSpace.lg, AppSpace.lg),
      decoration: aboutSurface(
        context,
        color: surface,
        rim: AppColors.green.withValues(alpha: 0.22),
        level: 3,
      ),
      // IntrinsicHeight: see AboutPullQuote. The accent rule below has no
      // height of its own, and `stretch` inside a scroll view resolves against
      // an infinite cross-axis constraint.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The rule. Radius 4 is the flush tier on the scale.
            Container(
              width: AppSpace.xs,
              decoration: BoxDecoration(
                color: AppColors.green,
                borderRadius: BorderRadius.circular(AppSpace.xs),
              ),
            ),
            AppSpace.gapLg,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('For Israt Habiba Eva',
                      style: AppTextStyles.labelSmall.copyWith(
                          color: readableOn(AppColors.green, surface),
                          letterSpacing: 1.4,
                          fontWeight: FontWeight.w700)),
                  AppSpace.vGapMd,
                  // The largest type on the page, deliberately. This one
                  // sentence is the reason the app exists; setting it at the
                  // same size as a section heading made it read as an epigraph
                  // rather than as the point.
                  Text(quote,
                      style: AppTextStyles.displayMedium
                          .copyWith(color: textPrimary, height: 1.35)),
                  AppSpace.vGapMd,
                  Text(translation,
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: textMuted, height: 1.55)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The support block.
///
/// TWO THINGS THIS IS BUILT TO AVOID, both asked for explicitly. It must not
/// read as begging — so the copy says plainly that nothing is being asked for,
/// and the numbers are not on screen until someone deliberately asks to see
/// them. And it must not become a vector for someone impersonating AFOS — so
/// the block states, in the app itself, that nobody from AFOS will ever message
/// you asking for money. A person who has read that line once is much harder to
/// defraud with a copy of it.
class AboutSupportCard extends StatefulWidget {
  const AboutSupportCard({super.key});

  @override
  State<AboutSupportCard> createState() => _AboutSupportCardState();
}

class _AboutSupportCardState extends State<AboutSupportCard> {
  bool _revealed = false;

  void _toggle() {
    AppHaptics.selection();
    setState(() => _revealed = !_revealed);
  }

  Future<void> _copy(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    AppHaptics.success();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$label copied',
            style: TextStyle(color: AppColors.foregroundOn(AppColors.green))),
        backgroundColor: AppColors.green));
  }

  @override
  Widget build(BuildContext context) {
    final textSecondary = AppColors.textSecondaryOf(context);
    final textMuted = aboutMuted(context);
    // The button paints a 10% green tint over the card, so contrast is
    // measured against that rather than against the card alone.
    final buttonFill = Color.alphaBlend(
      AppColors.green.withValues(alpha: 0.10),
      AppColors.surfaceOf(context),
    );
    final ink = readableOn(AppColors.green, buttonFill);

    return Container(
      padding: AppSpace.allLg,
      // Tinted toward the same green as the dedication and Eva's card. Not
      // decoration: green is HER thread through this page, and what this block
      // is for is her. Rakib's card is the only blue surface on the screen,
      // which is what makes the pairing legible at a glance.
      decoration: aboutSurface(context,
          color: Color.alphaBlend(
            AppColors.green.withValues(alpha: 0.04),
            AppColors.surfaceOf(context),
          ),
          rim: AppColors.green.withValues(alpha: 0.18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Nobody is being asked for anything. AFOS is free, and it stays '
            'free.\n\n'
            'But it cost something to build: time, nights, and a stretch of '
            'two people\'s lives. If you got something out of it and you want '
            'to put a little weight behind that, even one taka lands as a '
            'thank-you. Read it as recognition that a developer\'s effort is '
            'real work, not as charity. And whatever arrives, Eva has the '
            'first claim on it.\n\n'
            'No one is forced to give anything. Contribute only if you '
            'genuinely feel like it. If you do not, nothing changes and '
            'nothing is lost.',
            style: AppTextStyles.bodyLarge
                .copyWith(color: textSecondary, height: 1.65),
          ),
          AppSpace.vGapLg,
          Semantics(
            button: true,
            child: InkWell(
              onTap: _toggle,
              borderRadius: BorderRadius.circular(LiquidGlass.radiusControl),
              child: Container(
                constraints:
                    const BoxConstraints(minHeight: AppSpace.minTouchTarget),
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.lg, vertical: AppSpace.md),
                decoration: BoxDecoration(
                  color: AppColors.green.withValues(alpha: 0.10),
                  borderRadius:
                      BorderRadius.circular(LiquidGlass.radiusControl),
                  border: Border.all(
                      color: AppColors.green.withValues(alpha: 0.30), width: 1),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                        _revealed
                            ? Icons.visibility_off_rounded
                            : Icons.volunteer_activism_rounded,
                        size: 18,
                        color: ink),
                    AppSpace.gapSm,
                    // Flexible, because this Row is centred and therefore lays
                    // its children out at their natural width. At 1.6x on a
                    // 320px phone the label plus the icon is 18px wider than
                    // the button, and an un-flexed Text in a Row does not wrap
                    // -- it overflows. Caught by the layout sweep the moment
                    // this widget became reachable from a test.
                    Flexible(
                      child: Text(
                          _revealed ? 'Hide the details' : 'Show where it goes',
                          textAlign: TextAlign.center,
                          style:
                              AppTextStyles.titleMedium.copyWith(color: ink)),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Removed rather than zero-length under reduced motion, for the
          // reason documented on animatedHeight().
          animatedHeight(
            context,
            !_revealed
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: AppSpace.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _AccountRow(
                          label: 'Brac Bank',
                          value: '1065237910001',
                          onCopy: () =>
                              _copy('Account number', '1065237910001'),
                        ),
                        AppSpace.vGapSm,
                        _AccountRow(
                          label: 'Dutch-Bangla (DBBL)',
                          value: '1671070005769',
                          onCopy: () =>
                              _copy('Account number', '1671070005769'),
                        ),
                        AppSpace.vGapSm,
                        _AccountRow(
                          label: 'bKash · Nagad · Rocket · Upay',
                          value: '01643537724',
                          onCopy: () => _copy('Number', '01643537724'),
                        ),
                        AppSpace.vGapMd,
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.shield_outlined,
                                size: 14, color: textMuted),
                            AppSpace.gapSm,
                            Expanded(
                              child: Text(
                                'Send something only if you actually want to. '
                                'Nobody from AFOS will ever message you asking '
                                'for money. If someone does, it is not us.',
                                style: AppTextStyles.labelSmall
                                    .copyWith(color: textMuted, height: 1.5),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// One payable destination, with the number in the tabular-numeric role so the
/// digits are readable as digits, and a copy action big enough to hit.
class _AccountRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onCopy;
  const _AccountRow(
      {required this.label, required this.value, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    final textMuted = aboutMuted(context);
    final ink = readableOn(AppColors.green, AppColors.surfaceOf(context));

    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpace.md, AppSpace.sm, AppSpace.sm, AppSpace.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(LiquidGlass.radiusControl),
        border: Border.all(color: AppColors.borderOf(context), width: 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: AppTextStyles.labelSmall.copyWith(color: textMuted)),
                // An account number is one unbreakable token: it has no spaces, so
                // Text cannot wrap it, and at 2.0x on a 320px phone
                // '1065237910001' is wider than the space left beside the copy
                // button. A Text simply CLIPS in that case -- no overflow stripe,
                // no exception, nothing for the layout probe to catch -- and a
                // silently truncated account number is the worst failure this
                // screen has available. scaleDown shrinks it only when it would
                // not otherwise fit.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(value,
                      style: AppTextStyles.monoMedium.copyWith(
                          color: AppColors.textPrimaryOf(context),
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onCopy,
            icon: const Icon(Icons.copy_rounded, size: 18),
            color: ink,
            tooltip: 'Copy $label',
            constraints: const BoxConstraints(
                minWidth: AppSpace.minTouchTarget,
                minHeight: AppSpace.minTouchTarget),
          ),
        ],
      ),
    );
  }
}
