import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../config/app_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../config/theme/motion.dart';
import '../../../config/theme/spacing.dart';
import '../../../core/layout/nav_insets.dart';
import '../../../core/utils/responsive.dart';
import '../../shell/presentation/top_app_bar.dart';
import 'widgets/about_content.dart';
import 'widgets/about_ink.dart';
import 'widgets/flip_profile_card.dart';

/// Who built AFOS, and why it exists at all.
///
/// This is the one screen in the app that is not a feature. It carries the
/// dedication, the two people behind the project, and an honest account of
/// where they were standing when they built it. It reads top to bottom in the
/// order the story actually happened: the sentence that started it, the person
/// who said it, the person who wrote the code, and then — last, and never as a
/// demand — how to put something behind the work.
///
/// Reached from Settings → App Info, and from the version line in the slide
/// menu, which is where people actually go looking for this.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  // ------------------------------------------------------------------- copy
  //
  // The prose lives here rather than in a database because it is authored
  // content, not data: nobody edits it from an admin screen, and a release is
  // the right unit of change for it.

  static const _quote =
      'Iss, protidin notun notun website ar app hoy, ar notun notun app '
      'download, install, log-in er jhamela.';

  static const _quoteTranslation =
      'Every day it\'s another website, another app. And every time, the same '
      'hassle: download it, install it, log in all over again.';

  static const _dedication =
      'She said it as a complaint. I took it as a spec.\n\n'
      'AFOS is one login for the whole campus, and it only exists because of '
      'that one sentence. Two and a half years of academic life, handed back '
      'as something that actually works, and dedicated to her by name.';

  static const _evaStory =
      '**Israt Habiba Eva.** The person this entire application is dedicated '
      'to.\n\n'
      'This application originally came into the developer\'s mind because of '
      'something she said. It was just a simple sentence from her. But '
      'sometimes a simple sentence stays in someone\'s mind longer than '
      'expected.\n\n'
      'That sentence caught the developer\'s attention and made him think '
      'differently. Instead of building another ordinary application, he '
      'thought: **why not build something for her?** And that thought slowly '
      'became this application. What started from a simple conversation '
      'eventually became a **two and a half year academic gift dedicated to '
      'Eva**, carrying her name, her contribution, and a part of the journey '
      'they shared.\n\n'
      'But Eva is not here simply because the application is dedicated to '
      'her. She is part of the reason the developer was able to keep moving '
      'forward.\n\n'
      'Eva is a fellow member of the developer team, **Exterminators**. '
      'Alongside the developer, she helped find the resources available for '
      'the team\'s work and contributions. She helped with academic '
      'materials, she helped the developer learn, read, understand and solve '
      'mathematics, and she became someone he could turn to when the academic '
      'side of the journey became difficult.\n\n'
      'The developer has always been somewhat of an outsider to academic '
      'life. Eva became a bridge: a bridge to the academic help, knowledge '
      'and understanding that he could not always reach on his own.\n\n'
      'Her contribution was not always something that could be measured by a '
      'line of code, a project submission, or a position on a team. Sometimes '
      'contribution is simply being there when someone needs help '
      'understanding something. Sometimes it is finding the right resource. '
      'Sometimes it is sitting beside someone and helping them solve a '
      'problem. And sometimes it is simply making someone believe that they '
      'can continue. **Eva did those things.**\n\n'
      'She is a **Computer Science and Engineering major** and an **FDE '
      '(Forward Deployed Engineer)**, with an excellent academic record and a '
      'CGPA close to **3.90**. Despite that achievement, she could not '
      'continue her FYDP because of medical and financial difficulties. She '
      'also reached out to the administration and requested help, but '
      'unfortunately she could not find the support she needed to continue.\n\n'
      'That part of her story should not be remembered as a failure, because '
      'a person\'s contribution is not erased simply because circumstances '
      'forced them to stop. Her work, her effort, her knowledge and the help '
      'she gave throughout this journey still remain. And that is why this '
      'application carries her name.\n\n'
      'If anyone chooses to contribute through this application, whatever is '
      'received will be sent to Eva. **Not because she needs to be remembered '
      'as someone who received a donation.** But because she deserves to be '
      'recognised for what she actually contributed. It is a small way of '
      'saying: I saw what you did. I remember the help you gave. And this '
      'exists because you were part of the journey.\n\n'
      'So if you contribute anything, let it be understood as **respect for '
      'her effort, recognition of her contribution, and motivation for the '
      'journey ahead.** Nobody is obliged to give anything. If you do not '
      'feel like it, do not, and nothing changes.\n\n'
      'Because behind this application there is a developer who built it. But '
      'behind the reason **why he chose to dedicate it**, there is Eva.\n\n'
      '**This application carries her name. Her effort is part of its story. '
      'And her contribution is the reason this dedication exists.**\n\n'
      'Let us wish **Israt Habiba Eva** well for everything she has '
      'contributed, everything she has overcome, and everything that is still '
      'waiting for her ahead.';

  static const _rakibStory =
      '**CGPA lower than 2.79, failed in a course, barely managed to pass.** '
      'The reason? Memorizing things is not my style. I can only do things '
      'when I understand them and can see them with my own eyes.\n\n'
      'I missed so many quizzes, missed too many club activities and '
      'organization events, and was kicked out of clubs for telling the truth '
      'and standing up for the rights of new members and trying to do something '
      'new. I was criticized by the whole batch because I could not copy '
      'others and could not manage my CGPA like them.\n\n'
      'And I come from down, very down. You cannot even imagine how far down '
      'I came from. At the same time, I had to manage both office and '
      'university problems. Quizzes, assignments, deadlines, and projects '
      'were my best competitors throughout this journey. I had to handle all '
      'of them with my bare hands. If I did not earn, I could not manage to '
      'get food, shelter, and so on.\n\n'
      'Still, I am not perfect, and I do not need to be, because you guys are '
      'going to help me get better. Tell me what is wrong and how I can do '
      'things better.\n\n'
      'I am not arrogant. I just think differently than you. Instead of '
      'memorizing, I prefer to learn things the hard way. I lost everyone. I '
      'learned the reality faster than my age. I skipped the razzle.\n\n'
      'These are not my weaknesses. **They are my strengths.**';

  /// What Eva actually did, as work items rather than as sentiment. The point
  /// of listing it this way is that a reader can check each line against
  /// somebody.
  static const _evaDid = <({String title, String detail})>[
    (
      title: 'Found the resources',
      detail: 'Worked out what the university and the team actually had '
          'available, and where it was kept. None of it was obvious from '
          'outside.'
    ),
    (
      title: 'Taught the mathematics',
      detail: 'Sat with the work until mathematics that could not be read '
          'became mathematics that could be solved. Repeatedly, and without '
          'being asked twice.'
    ),
    (
      title: 'Was the bridge to academic life',
      detail: 'For someone who came into it from outside and had nobody else '
          'to ask. That is the contribution this application is named for.'
    ),
  ];

  static const _evaCreds = <({String short, String long})>[
    (short: 'CSE', long: 'Computer Science and Engineering, her major'),
    (short: 'FDE', long: 'Forward Deployed Engineer'),
    (short: 'CGPA', long: 'Close to 3.90, carried the whole way'),
    (
      short: 'FYDP',
      long: 'Final Year Design Project, which she could not '
          'continue'
    ),
    (short: 'Exterminators', long: 'Team member, alongside the developer'),
  ];

  /// Given as a list, in this order, and kept that way. See AboutFactList
  /// for why this is not a table.
  static const _rakibCv = <String>[
    '**CSE Major in Cyber Security**',
    '**Intern, Kaspersky Lab** as a Security & System Engineer in '
        'Russia, 2026',
    '**CISA, CompTIA, CEH L4, NSDA L4**',
    '**Web, Software & Game Developer**',
    '**Requested Candidate, Russia Nuclear University** as a Quantum '
        'Computer Research Assistant, Anthology, 2025',
    '**BracIT**, Associate Security Engineer, 2024-2025',
    '**Dcorn**, Backend Developer, 2024',
    '**Shared Investor, Tasty Treat**, 2022-2024. Burned and faced a '
        'loss of about 20 lakhs.',
    '**Foodpanda Delivery Boy**, worked at night in Mohammadpur, 2020',
    '**Server / Hotel Boy** at several Bangla hotels',
    '**Kicked out from BAFA**, 83/155 Board, 2221, 2019',
  ];

  static const _exterminators = 'Exterminators is two people on this one.\n\n'
      'Eva found the way through the academic side. I wrote the code. Neither '
      'half of that ships on its own, which is the only reason this screen has '
      'two cards on it instead of one.';

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);

    // ONE orchestrated entrance for the screen (Law 6). Steps are spaced on
    // the 40ms grid and deliberately non-contiguous, so the dedication lands
    // clearly before the people do.
    int step = 0;
    Widget staged(Widget child, {int jump = 2}) {
      step += jump;
      return child
          .animate(delay: AppMotion.sequenceDelay(context, step))
          .fadeIn(duration: AppMotion.durationOf(context, AppMotion.base))
          .slideY(begin: 0.06, curve: AppMotion.standard);
    }

    return Scaffold(
      backgroundColor: AppColors.surfaceOf(context),
      appBar: const AfosAppBar(title: 'Who built this'),
      body: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxWidth:
                    Responsive.isDesktop(context) ? 720 : double.infinity),
            child: Padding(
              padding: EdgeInsetsDirectional.fromSTEB(AppSpace.lg, AppSpace.lg,
                  AppSpace.lg, AppSpace.xxl + NavInsets.of(context)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  staged(
                      const AboutDedication(
                          quote: _quote, translation: _quoteTranslation),
                      jump: 0),
                  const SizedBox(height: AppSpace.lg),
                  staged(Text(_dedication,
                      style: AppTextStyles.bodyLarge
                          .copyWith(color: textSecondary, height: 1.6))),
                  const SizedBox(height: AppSpace.xxl),

                  // ── The people ────────────────────────────────────────────
                  staged(_SectionLabel('The two of us', color: textPrimary)),
                  const SizedBox(height: AppSpace.md),
                  staged(const FlipProfileCard(
                    name: 'Israt Habiba Eva',
                    role:
                        'Computer Science & Engineering · Forward Deployed Engineer',
                    photoAsset: 'assets/profile/eva_512.jpg',
                    accent: AppColors.green,
                    tags: ['Exterminators', 'CSE', 'FDE'],
                    flipLabel: 'Why this app is hers',
                    back: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AboutProse(_evaStory),
                        SizedBox(height: AppSpace.xl),
                        AboutPoints('WHAT SHE ACTUALLY DID', _evaDid,
                            accent: AppColors.green),
                        SizedBox(height: AppSpace.xl),
                        AboutGlossary('THE SHORT FORM', _evaCreds),
                      ],
                    ),
                  )),
                  const SizedBox(height: AppSpace.md),
                  staged(const FlipProfileCard(
                    name: 'Rakib Hassan',
                    role:
                        'Founder, Exterminators · CSE, Cyber Security · builds AFOS',
                    photoAsset: 'assets/profile/rakib_512.jpg',
                    accent: AppColors.blueLight,
                    tags: [
                      'CISA',
                      'CompTIA',
                      'CEH L4',
                      'NSDA L4',
                      'Web · Software · Games'
                    ],
                    flipLabel: 'The unflattering version',
                    back: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AboutProse(_rakibStory),
                        SizedBox(height: AppSpace.xl),
                        AboutFactList(
                            'EDUCATION, CAREER & EXPERIENCE', _rakibCv,
                            accent: AppColors.blueLight),
                      ],
                    ),
                  )),
                  const SizedBox(height: AppSpace.xxl),

                  // ── The team ──────────────────────────────────────────────
                  staged(_SectionLabel('Exterminators', color: textPrimary)),
                  const SizedBox(height: AppSpace.md),
                  staged(Text(_exterminators,
                      style: AppTextStyles.bodyLarge
                          .copyWith(color: textSecondary, height: 1.65))),
                  const SizedBox(height: AppSpace.xxl),

                  // ── Backing the work ──────────────────────────────────────
                  staged(_SectionLabel('If you want to put something behind it',
                      color: textPrimary)),
                  const SizedBox(height: AppSpace.md),
                  staged(const AboutSupportCard()),
                  const SizedBox(height: AppSpace.xxl),

                  // The sign-off carries the build and the university, and
                  // NOT the team name. It used to repeat "Exterminators" in
                  // letterspaced caps about four hundred pixels below the
                  // section heading that already says it — which reads as a
                  // template filling its slots rather than as someone signing
                  // their work.
                  staged(Column(children: [
                    // The page ends here; without a rule it merely stops.
                    Divider(
                        height: 1,
                        thickness: 1,
                        color: AppColors.borderOf(context)),
                    const SizedBox(height: AppSpace.lg),
                    Center(
                      child: Text(
                          'AFOS v${AppConfig.appVersion} · ${AppConfig.university}',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.monoSmall
                              .copyWith(color: aboutMuted(context))),
                    ),
                  ])),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════ pieces

/// A heading that sits above a group without pretending to be a card.
///
/// The short rule above it is structural, not ornamental: this page is a column
/// of prose and surfaces with no other marker of where one part ends and the
/// next begins, and a reader scrolling past needs somewhere for the eye to
/// catch. Two pixels tall and one spacing step wide, in the brand accent, at
/// every section start -- the same mark in the same place, which is what makes
/// it read as structure instead of as a flourish.
class _SectionLabel extends StatelessWidget {
  final String text;
  final Color color;
  const _SectionLabel(this.text, {required this.color});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: AppSpace.xl,
            height: 2,
            decoration: BoxDecoration(
              color: AppColors.green,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          AppSpace.vGapMd,
          Text(text, style: AppTextStyles.headlineMed.copyWith(color: color)),
        ],
      );
}
