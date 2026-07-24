import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A small dot that gently blinks to draw the eye — used to nudge the reader
/// toward an unfinished bit of setup (e.g. "you haven't picked a username
/// yet"). The swell mirrors the splash screen's `_dot` pulse (triangle wave +
/// ease-in-out) so the motion feels of a piece with the rest of the app.
///
/// Honours reduced motion: when `MediaQuery.disableAnimations` is set it holds
/// a solid dot instead of pulsing, same convention as [TickerText].
class PulsingDot extends StatefulWidget {
  const PulsingDot({
    super.key,
    this.size = 8,
    this.color,
  });

  final double size;

  /// Defaults to [AppColors.gold] (not a compile-time const, so resolved lazily).
  final Color? color;

  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      return _dot(1);
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, _) {
        // Triangle wave 0→1→0 → a smooth swell then fade.
        final v = _controller.value;
        final t = v < 0.5 ? v * 2 : (1 - v) * 2;
        final eased = Curves.easeInOut.transform(t.clamp(0.0, 1.0));
        // Never fully vanish — floor the opacity so it reads as a pulse, not a
        // flash, and stays legible against the busy icon behind it.
        return _dot(0.4 + eased * 0.6);
      },
    );
  }

  Widget _dot(double opacity) {
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: (widget.color ?? AppColors.gold).withValues(alpha: opacity),
      ),
    );
  }
}
