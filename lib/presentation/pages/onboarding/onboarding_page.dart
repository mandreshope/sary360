import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/constellation_colors.dart';
import '../../../core/widgets/constellation_orb.dart';
import '../../../core/widgets/starfield_background.dart';
import '../../providers/settings_providers.dart';
import 'onboarding_illustrations.dart';

/// Contenu d'une étape d'onboarding.
class _Step {
  const _Step({
    required this.kicker,
    required this.title,
    required this.body,
    required this.illustration,
  });

  final String kicker;
  final String title;
  final String body;
  final Widget Function(double size) illustration;
}

final _steps = <_Step>[
  _Step(
    kicker: '01 — LE GESTE',
    title: 'Tournez sur\nvous-même',
    body:
        'Restez au même endroit et pivotez lentement. Chaque étoile que vous '
        'visez devient une photo, prise automatiquement.',
    illustration: (s) => TurnAroundIllustration(size: s),
  ),
  _Step(
    kicker: '02 — LE POINT FIXE',
    title: 'Le téléphone\nreste au centre',
    body:
        'Faites pivoter l\'appareil autour de son objectif, sans le déplacer. '
        'Inclinez-le pour viser les étoiles du haut et du bas.',
    illustration: (s) => PivotIllustration(size: s),
  ),
  _Step(
    kicker: '03 — LA CONSTELLATION',
    title: 'Complétez\nvotre ciel',
    body:
        'Chaque capture relie les étoiles entre elles. Une fois la '
        'constellation complète, Sary360 assemble votre sphère 360°.',
    illustration: (s) => ConstellationOrb(size: s),
  ),
];

/// Onboarding animé en 3 écrans expliquant le geste de capture.
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _controller = PageController();

  /// Position continue de la page (0.0 → 2.0), pour la parallaxe.
  double _page = 0;

  int get _index => _page.round();
  bool get _isLast => _index == _steps.length - 1;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      setState(() => _page = _controller.page ?? 0);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    HapticFeedback.mediumImpact();
    await ref.read(settingsControllerProvider.notifier).completeOnboarding();
    if (mounted) context.go(AppRoutes.home);
  }

  void _next() {
    if (_isLast) {
      _finish();
    } else {
      _controller.nextPage(duration: AppMotion.slow, curve: AppMotion.standard);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final illustrationSize = (MediaQuery.sizeOf(context).shortestSide * 0.72)
        .clamp(200.0, 320.0);

    return Scaffold(
      body: StarfieldBackground(
        child: SafeArea(
          child: Column(
            children: [
              // Barre supérieure : marque + « Passer ».
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 8, 0),
                child: Row(
                  children: [
                    Text('SARY360', style: text.labelSmall),
                    const Spacer(),
                    AnimatedOpacity(
                      opacity: _isLast ? 0 : 1,
                      duration: AppMotion.fast,
                      child: TextButton(
                        onPressed: _isLast ? null : _finish,
                        child: const Text('Passer'),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _steps.length,
                  onPageChanged: (_) => HapticFeedback.selectionClick(),
                  itemBuilder: (context, i) {
                    // Décalage relatif de la page (−1..1) pour la parallaxe.
                    final delta = (i - _page).clamp(-1.0, 1.0);
                    return _StepView(
                      step: _steps[i],
                      delta: delta,
                      illustrationSize: illustrationSize,
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Row(
                  children: [
                    _PageDots(
                      count: _steps.length,
                      page: _page,
                      color: c.accent,
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: _next,
                      child: AnimatedSwitcher(
                        duration: AppMotion.medium,
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: ScaleTransition(scale: anim, child: child),
                        ),
                        child: Row(
                          key: ValueKey(_isLast),
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_isLast ? 'Commencer' : 'Suivant'),
                            const SizedBox(width: 8),
                            Icon(
                              _isLast
                                  ? Icons.auto_awesome_rounded
                                  : Icons.arrow_forward_rounded,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepView extends StatelessWidget {
  const _StepView({
    required this.step,
    required this.delta,
    required this.illustrationSize,
  });

  final _Step step;
  final double delta;
  final double illustrationSize;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.colors;
    final fade = 1 - delta.abs();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // L'illustration glisse plus lentement que le texte (parallaxe)
          // et se réduit si la hauteur disponible est faible.
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) => Center(
                child: Transform.translate(
                  offset: Offset(delta * 80, 0),
                  child: Opacity(
                    opacity: fade.clamp(0.0, 1.0),
                    child: Transform.scale(
                      scale: 0.85 + 0.15 * fade,
                      child: step.illustration(
                        illustrationSize.clamp(0.0, box.maxHeight),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Transform.translate(
            offset: Offset(delta * 40, 0),
            child: Opacity(
              opacity: fade.clamp(0.0, 1.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.kicker,
                    style: text.labelSmall?.copyWith(color: c.accent),
                  ),
                  const SizedBox(height: 12),
                  Text(step.title, style: text.displaySmall),
                  const SizedBox(height: 16),
                  Text(
                    step.body,
                    style: text.bodyLarge?.copyWith(color: c.textSecondary),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

/// Indicateur de pages : la pastille active s'étire en douceur.
class _PageDots extends StatelessWidget {
  const _PageDots({
    required this.count,
    required this.page,
    required this.color,
  });

  final int count;
  final double page;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final dim = context.colors.starDim.withValues(alpha: 0.4);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(count, (i) {
        final active = (1 - (page - i).abs()).clamp(0.0, 1.0);
        return Container(
          margin: const EdgeInsets.only(right: 8),
          width: 8 + 20 * active,
          height: 8,
          decoration: BoxDecoration(
            color: Color.lerp(dim, color, active),
            borderRadius: BorderRadius.circular(AppRadii.pill),
          ),
        );
      }),
    );
  }
}
