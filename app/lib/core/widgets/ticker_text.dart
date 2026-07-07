import 'package:flutter/material.dart';

/// The "ticker" from docs/screen-design.md — text too long for a generated
/// cover scrolls gently, music-player style, instead of truncating: a pause,
/// a slide that reveals the clipped end, a hold, then a settle back. Mirrors
/// the mockups' `.tick` keyframes (7s ease-in-out, 1.2s lead-in) but runs
/// **once** per mount — grids may scroll once on first render, never in loops.
///
/// Overflow-only: text that fits inside [maxLines] renders as a plain wrapped
/// [Text]. Under reduced motion (`MediaQuery.disableAnimations`) it never
/// animates and falls back to the static ellipsis. The nowrap run cannot
/// widen layout — the text paints at natural width inside a [ClipRect].
class TickerText extends StatefulWidget {
  const TickerText(
    this.text, {
    super.key,
    this.style,
    this.maxLines = 1,
    this.startDelay = const Duration(milliseconds: 1200),
  });

  final String text;
  final TextStyle? style;

  /// Line budget for the static rendering (and the overflow test).
  final int maxLines;

  /// Lead-in before the single run — callers stagger this so a shelf of
  /// covers doesn't move in lockstep.
  final Duration startDelay;

  @override
  State<TickerText> createState() => _TickerTextState();
}

class _TickerTextState extends State<TickerText> with SingleTickerProviderStateMixin {
  // Created only when text actually overflows — most instances never animate.
  AnimationController? _c;
  Animation<double>? _t;
  bool _runScheduled = false;

  /// The mockup timeline (of the 7s run): 0–12% hold at the start, →55% slide
  /// out, →70% hold on the revealed end, →100% ease back and settle. The
  /// lead-in is part of the timeline (a leading hold segment) rather than a
  /// Timer — no dangling timers in widget tests.
  Animation<double> _timeline() {
    final c = _c ??= AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7) + widget.startDelay,
    );
    return _t ??= TweenSequence<double>([
      TweenSequenceItem(
        tween: ConstantTween(0.0),
        weight: widget.startDelay.inMilliseconds + 840,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 3010,
      ),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 1050),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 2100,
      ),
    ]).animate(c);
  }

  @override
  void didUpdateWidget(TickerText old) {
    super.didUpdateWidget(old);
    // A recycled element showing new text (grid cells swap books) is a fresh
    // first render for that title — settle and allow one new run.
    if (old.text != widget.text) {
      _runScheduled = false;
      if (old.startDelay != widget.startDelay) {
        // The timeline bakes the lead-in into its weights — rebuild it.
        _c?.dispose();
        _c = null;
        _t = null;
      } else {
        _c?.stop();
        _c?.value = 0;
      }
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  void _scheduleRun() {
    if (_runScheduled) return;
    _runScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _c?.forward();
    });
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final fits = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          textDirection: direction,
          textScaler: scaler,
          maxLines: widget.maxLines,
        )..layout(maxWidth: maxW);
        if (!fits.didExceedMaxLines || reduceMotion || !maxW.isFinite) {
          return Text(
            widget.text,
            maxLines: widget.maxLines,
            overflow: TextOverflow.ellipsis,
            style: widget.style,
          );
        }

        // Overflow → one gentle nowrap run, then settle showing the start.
        final single = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          textDirection: direction,
          textScaler: scaler,
          maxLines: 1,
        )..layout();
        final distance = (single.width - maxW).clamp(0.0, double.infinity);
        final t = _timeline();
        _scheduleRun();
        return ClipRect(
          child: SizedBox(
            width: maxW,
            height: single.height,
            child: AnimatedBuilder(
              animation: t,
              builder: (context, child) => Transform.translate(
                offset: Offset(-distance * t.value, 0),
                child: child,
              ),
              child: OverflowBox(
                maxWidth: double.infinity,
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.text,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  style: widget.style,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
