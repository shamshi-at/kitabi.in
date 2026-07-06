import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/brand_mark.dart';
import '../../../l10n/app_localizations.dart';

/// Shown while auth state (and, once signed in, the profile bootstrap call)
/// resolves. The router redirect leaves this location alone until then, so
/// there's no sign-in-screen flash for an already-authenticated user.
///
/// A staggered intro — the mark settles in, the name rises, the gold line draws
/// across ("The Gold Line" brand mark), the tagline fades in — then a quiet
/// three-dot loader keeps time while auth/profile resolve. Honours
/// `MediaQuery.disableAnimations` (reduced motion) by showing the settled state.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late final AnimationController _intro =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  late final AnimationController _loop =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _intro.value = 1;
    } else if (_intro.status == AnimationStatus.dismissed) {
      _intro.forward();
      _loop.repeat();
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    _loop.dispose();
    super.dispose();
  }

  // A staggered slice of the intro: [start, end] of the master timeline.
  Animation<double> _slice(double start, double end, {Curve curve = Curves.easeOut}) =>
      CurvedAnimation(parent: _intro, curve: Interval(start, end, curve: curve));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final logo = _slice(0.0, 0.55, curve: Curves.easeOutBack);
    final name = _slice(0.35, 0.72);
    final line = _slice(0.55, 0.9, curve: Curves.easeInOut);
    final tagline = _slice(0.72, 1.0);
    final footer = _slice(0.8, 1.0);

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: Stack(
        children: [
          // A faint warm vignette so the paper reads as lit, not flat.
          const _PaperGlow(),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: logo,
                  builder: (_, child) => Opacity(
                    opacity: logo.value.clamp(0.0, 1.0),
                    child: Transform.scale(scale: 0.82 + 0.18 * logo.value.clamp(0.0, 1.0), child: child),
                  ),
                  child: const BrandMark(size: 96),
                ),
                const SizedBox(height: 22),
                _RiseFade(
                  animation: name,
                  child: Text(
                    'Kitabi',
                    style: GoogleFonts.fraunces(
                      fontSize: 40,
                      height: 1.0,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                // The gold line drawing across — the signature brand gesture.
                AnimatedBuilder(
                  animation: line,
                  builder: (_, _) => Container(
                    height: 2,
                    width: 150 * line.value.clamp(0.0, 1.0),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      gradient: LinearGradient(
                        colors: [
                          AppColors.gold.withValues(alpha: 0),
                          AppColors.gold,
                          AppColors.gold.withValues(alpha: 0),
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _RiseFade(
                  animation: tagline,
                  child: Text(
                    l10n.splashTagline,
                    style: GoogleFonts.fraunces(
                      fontSize: 15,
                      fontStyle: FontStyle.italic,
                      color: AppColors.inkSoft,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // The loader + status pinned near the bottom — signals it's working.
          Positioned(
            left: 0,
            right: 0,
            bottom: 44,
            child: FadeTransition(
              opacity: footer,
              child: Column(
                children: [
                  _DotsLoader(controller: _loop),
                  const SizedBox(height: 14),
                  Text(
                    l10n.splashLoading,
                    style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
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

/// Fade + a small upward slide, keyed off a [0,1] animation.
class _RiseFade extends StatelessWidget {
  const _RiseFade({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (_, child) {
        final v = animation.value.clamp(0.0, 1.0);
        return Opacity(
          opacity: v,
          child: Transform.translate(offset: Offset(0, (1 - v) * 10), child: child),
        );
      },
      child: child,
    );
  }
}

/// Three gold dots that pulse in sequence while auth/profile resolve. The wait
/// is open-ended, so this loops rather than depending on a fixed duration.
class _DotsLoader extends StatelessWidget {
  const _DotsLoader({required this.controller});

  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++) ...[
            _dot(i),
            if (i < 2) const SizedBox(width: 7),
          ],
        ],
      ),
    );
  }

  Widget _dot(int i) {
    // Each dot's phase is offset so the pulse travels left→right.
    final phase = (controller.value - i * 0.18) % 1.0;
    // Triangle wave 0→1→0 → a smooth swell then fade.
    final t = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
    final eased = Curves.easeInOut.transform(t.clamp(0.0, 1.0));
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Color.lerp(AppColors.line, AppColors.gold, eased),
      ),
    );
  }
}

/// A barely-there radial warmth behind the mark — keeps the paper from feeling
/// like a flat fill without introducing a second colour.
class _PaperGlow extends StatelessWidget {
  const _PaperGlow();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.25),
          radius: 0.9,
          colors: [AppColors.card, AppColors.paper],
        ),
      ),
      child: const SizedBox.expand(),
    );
  }
}
