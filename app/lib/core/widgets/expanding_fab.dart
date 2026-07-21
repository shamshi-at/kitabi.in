import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// One action in the [ExpandingFab]'s fan: an icon, a label pill (always
/// visible when open — no icon-guessing), an optional count badge, and what
/// tapping it does.
class ExpandingFabAction {
  const ExpandingFabAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.badge,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  /// A small gold count on the mini button (e.g. active filter count).
  final int? badge;
}

/// The floating library control (owner pick, 17 Jul 2026 — "expanding
/// button"): one quiet oxblood circle at rest, which fans up into labelled
/// actions — Search, Filter, Sort — and folds back. It exists so a reader
/// nine hundred rows into a shelf never scrolls back up to reach search or
/// filter; the header is free to scroll away.
///
/// Drop it as the last child of a full-screen `Stack` — it sizes itself to
/// the whole area so its tap-away scrim can cover the screen, but only the
/// button (and, when open, the scrim) actually take touches.
///
/// The sum of the actions' badges shows on the collapsed circle too, so "2
/// filters are on" is visible without opening the fan. Honours reduced
/// motion (states jump instead of animating).
class ExpandingFab extends StatefulWidget {
  const ExpandingFab({super.key, required this.actions, this.semanticLabel});

  final List<ExpandingFabAction> actions;

  /// Accessibility label for the collapsed button.
  final String? semanticLabel;

  @override
  State<ExpandingFab> createState() => _ExpandingFabState();
}

class _ExpandingFabState extends State<ExpandingFab> with SingleTickerProviderStateMixin {
  // Created in initState, not as a `late final` initializer: lazily creating a
  // ticker on first touch means a fab that was never opened would create it in
  // dispose() — an ancestor lookup on a deactivated element, which throws on
  // every teardown of the host screen.
  late final AnimationController _controller;
  bool _open = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 180));
  }

  void _toggle() {
    setState(() => _open = !_open);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _controller.value = _open ? 1 : 0;
    } else if (_open) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  void _close() {
    if (_open) _toggle();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalBadge =
        widget.actions.fold<int>(0, (sum, a) => sum + (a.badge ?? 0));

    return SizedBox.expand(
      child: Stack(
        children: [
          // Tap-away scrim — a whisper of ink so the fan reads as a layer,
          // and any outside tap folds it back.
          if (_open)
            Positioned.fill(
              child: GestureDetector(
                onTap: _close,
                behavior: HitTestBehavior.opaque,
                child: FadeTransition(
                  opacity: _controller,
                  child: ColoredBox(color: AppColors.ink.withValues(alpha: 0.08)),
                ),
              ),
            ),
          Positioned(
            right: 14,
            bottom: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (_open)
                  for (final (i, action) in widget.actions.indexed)
                    _FanRow(
                      action: action,
                      controller: _controller,
                      // Rows nearer the button arrive first — a fan, not a list.
                      interval: Interval(
                        0.12 * (widget.actions.length - 1 - i),
                        1,
                        curve: Curves.easeOut,
                      ),
                      onPressed: () {
                        _close();
                        action.onPressed();
                      },
                    ),
                SizedBox(height: 2),
                Semantics(
                  button: true,
                  expanded: _open,
                  label: widget.semanticLabel,
                  child: Material(
                    color: AppColors.oxblood,
                    shape: const CircleBorder(),
                    elevation: 6,
                    shadowColor: AppColors.oxbloodDeep,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _toggle,
                      child: SizedBox(
                        width: 52,
                        height: 52,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Center(
                              // Cross-fade tune ⇄ close as the fan opens.
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 140),
                                child: Icon(
                                  // Closed, this button hides *both* search
                                  // and filter; a plain slider icon read as
                                  // filter-only and search went unfound
                                  // (owner report, 21 Jul 2026).
                                  _open ? Icons.close : Icons.manage_search,
                                  key: ValueKey(_open),
                                  color: AppColors.paper,
                                  size: 22,
                                ),
                              ),
                            ),
                            if (!_open && totalBadge > 0)
                              Positioned(top: 1, right: 1, child: _Badge(count: totalBadge)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FanRow extends StatelessWidget {
  const _FanRow({
    required this.action,
    required this.controller,
    required this.interval,
    required this.onPressed,
  });

  final ExpandingFabAction action;
  final AnimationController controller;
  final Interval interval;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final anim = CurvedAnimation(parent: controller, curve: interval);
    return FadeTransition(
      opacity: anim,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.35), end: Offset.zero).animate(anim),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: onPressed,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: AppColors.line),
                      boxShadow: [
                        BoxShadow(color: Color(0x332B2118), blurRadius: 8, offset: Offset(0, 2)),
                      ],
                    ),
                    child: Text(
                      action.label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.line),
                      boxShadow: [
                        BoxShadow(color: Color(0x3D2B2118), blurRadius: 9, offset: Offset(0, 3)),
                      ],
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Center(child: Icon(action.icon, size: 17, color: AppColors.oxblood)),
                        if ((action.badge ?? 0) > 0)
                          Positioned(top: -3, right: -3, child: _Badge(count: action.badge!)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The little gold count — same meaning wherever it appears: something here
/// is active.
class _Badge extends StatelessWidget {
  const _Badge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.gold,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: AppColors.card, width: 1.5),
      ),
      constraints: const BoxConstraints(minWidth: 15),
      child: Text(
        '$count',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, color: Color(0xFF241811)),
      ),
    );
  }
}
