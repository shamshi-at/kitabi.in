import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/format_duration.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';

/// Why a typed page can't be saved. Null means it can.
enum PageEntryError { belowOne, aboveTotal, belowStart }

/// R1/R2 — the page-reached entry, shared by every surface that asks for it.
///
/// This block used to be a 56-pixel `TextField` wedged into a single `Row`
/// (with a *second* box crammed in beside it when the catalogue had no page
/// count), duplicated between the timer's wax-seal face and the quick-stop
/// dialog. It lives here once because CLAUDE.md's standing lesson is that the
/// four progress surfaces drift apart the moment they're built separately.
///
/// Three things earn their place:
/// * **The number is the screen** — big, tappable, and focusing it selects the
///   whole value so typing replaces it. Correcting "260" to "302" is two taps,
///   not five backspaces.
/// * **−/+** for the far commoner case of being a page or two out.
/// * **An anchor** — where this session began — because that's the fact that
///   makes the number easy to judge without going to find the book.
///
/// Validation exists to stop a session logging *backwards*: a page below where
/// the session started is almost always a typo, and silently accepting it
/// would walk the reader's progress down. Genuine corrections have a home (the
/// book page's progress editor), and the message says so.
class SessionPageEntry extends StatefulWidget {
  const SessionPageEntry({
    super.key,
    required this.pageController,
    required this.totalController,
    required this.pageFocusNode,
    required this.pageCount,
    required this.pageStart,
    required this.duration,
    this.onValidityChanged,
    this.onOpenLog,
    this.lastSessionLine,
    this.pageHint,
  });

  final TextEditingController pageController;

  /// Only used when [pageCount] is null — the book's length, which the reader
  /// is uniquely placed to supply while holding it.
  final TextEditingController totalController;
  final FocusNode pageFocusNode;

  /// The catalogue's page count, or null when nobody has filled it in.
  final int? pageCount;

  /// Where this sitting began — the floor for validation and the anchor line.
  final int? pageStart;

  final Duration duration;

  /// Fired whenever the typed page's validity changes, so the caller can gate
  /// its own Save button.
  final ValueChanged<PageEntryError?>? onValidityChanged;

  /// Opens the sittings log (R3). Hidden when null.
  final VoidCallback? onOpenLog;

  /// Pre-formatted "Last time · …" line, when there's a previous sitting.
  final String? lastSessionLine;

  /// Placeholder for the empty numeral — callers that keep the field empty
  /// (the manual-log sheet) show the current page here instead of "0", so an
  /// untouched save can't quietly log a zero-page sitting.
  final String? pageHint;

  @override
  State<SessionPageEntry> createState() => _SessionPageEntryState();
}

class _SessionPageEntryState extends State<SessionPageEntry> {
  PageEntryError? _error;

  @override
  void initState() {
    super.initState();
    widget.pageFocusNode.addListener(_onFocusChanged);
    widget.pageController.addListener(_onTextChanged);
    // Publish the starting validity so a caller that opens with a pre-filled
    // value doesn't begin with a stale "valid" assumption.
    WidgetsBinding.instance.addPostFrameCallback((_) => _onTextChanged());
  }

  @override
  void dispose() {
    widget.pageFocusNode.removeListener(_onFocusChanged);
    widget.pageController.removeListener(_onTextChanged);
    super.dispose();
  }

  /// Tapping the number selects all of it, so the next keystroke replaces the
  /// value instead of appending to it — the reader is overwriting a page, not
  /// editing prose.
  void _onFocusChanged() {
    if (!widget.pageFocusNode.hasFocus) return;
    widget.pageController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.pageController.text.length,
    );
  }

  void _onTextChanged() {
    final next = _validate(int.tryParse(widget.pageController.text.trim()));
    if (next == _error) {
      // Still rebuild for the live pace/progress readout below the number.
      if (mounted) setState(() {});
      return;
    }
    if (mounted) setState(() => _error = next);
    widget.onValidityChanged?.call(next);
  }

  PageEntryError? _validate(int? page) {
    // Empty is not an error — it means "no page this time", which Skip and
    // Save both handle by leaving progress alone.
    if (page == null) return null;
    if (page < 1) return PageEntryError.belowOne;
    final total = widget.pageCount;
    if (total != null && page > total) return PageEntryError.aboveTotal;
    final start = widget.pageStart;
    if (start != null && page < start) return PageEntryError.belowStart;
    return null;
  }

  void _nudge(int by) {
    final current = int.tryParse(widget.pageController.text.trim()) ??
        widget.pageStart ??
        0;
    final next = current + by;
    if (next < 1) return;
    final total = widget.pageCount;
    if (total != null && next > total) return;
    Haptics.light();
    widget.pageController.text = '$next';
    widget.pageController.selection =
        TextSelection.collapsed(offset: widget.pageController.text.length);
  }

  String? _errorText(AppLocalizations l10n) => switch (_error) {
        PageEntryError.belowOne => l10n.stopErrorBelowOne,
        PageEntryError.aboveTotal => l10n.stopErrorAboveTotal(widget.pageCount ?? 0),
        PageEntryError.belowStart => l10n.stopErrorBelowStart(widget.pageStart ?? 0),
        null => null,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final page = int.tryParse(widget.pageController.text.trim());
    final total = widget.pageCount;
    final start = widget.pageStart;
    final pagesRead = (page != null && start != null && page > start) ? page - start : null;
    final hours = widget.duration.inSeconds / 3600;
    final pace = (pagesRead != null && hours > 0) ? (pagesRead / hours).round() : null;
    final fraction = (page != null && total != null && total > 0)
        ? (page / total).clamp(0.0, 1.0)
        : null;
    final errorText = _errorText(l10n);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.stopWhereDidYouGet.toUpperCase(),
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: AppColors.inkSoft,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Stepper(
              icon: Icons.remove,
              enabled: true,
              onTap: () => _nudge(-1),
              onLongPress: () => _nudge(-10),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 96,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: widget.pageController,
                    focusNode: widget.pageFocusNode,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textAlign: TextAlign.center,
                    // GoogleFonts registers its own family names — a bare
                    // fontFamily: 'Fraunces' silently fell back to the sans.
                    // The numeral keeps its oxblood in the error state — the
                    // oxblood→oxbloodDeep swap was imperceptible; the underline
                    // and the message below carry the state.
                    style: GoogleFonts.fraunces(
                      fontSize: 34,
                      height: 1.05,
                      fontWeight: FontWeight.w500,
                      color: AppColors.oxblood,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.only(bottom: 4),
                      hintText: widget.pageHint ?? l10n.timerPageFieldHint,
                      hintStyle: GoogleFonts.fraunces(
                        fontSize: 34,
                        color: AppColors.inkSoft.withValues(alpha: .45),
                      ),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: errorText != null ? AppColors.oxbloodDeep : AppColors.gold,
                          width: 2,
                        ),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: errorText != null ? AppColors.oxbloodDeep : AppColors.gold,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  // The caption also surfaces the steppers' hidden long-press,
                  // which nothing else on the surface hints at.
                  Text(
                    '${total != null ? l10n.timerPageFieldOf(total) : l10n.stopPageUnit} · ${l10n.stopHoldForTen}',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 10.5, color: AppColors.inkSoft),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            _Stepper(
              icon: Icons.add,
              enabled: true,
              onTap: () => _nudge(1),
              onLongPress: () => _nudge(10),
            ),
          ],
        ),

        // Validation first — when the number can't be saved, the pace readout
        // is noise beside the reason why.
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Text(
              errorText,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: AppColors.oxbloodDeep,
              ),
            ),
          )
        else ...[
          if (fraction != null) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: fraction,
                  minHeight: 5,
                  backgroundColor: AppColors.paperDeep,
                  valueColor: AlwaysStoppedAnimation(AppColors.oxblood),
                ),
              ),
            ),
          ],
          if (fraction != null || pagesRead != null) ...[
            const SizedBox(height: 6),
            Text(
              [
                if (fraction != null) '${(fraction * 100).round()}%',
                if (pagesRead != null) l10n.timerSessionPages(pagesRead),
                if (pace != null) l10n.timerPagesPerHour('$pace'),
              ].join(' · '),
              style: TextStyle(fontSize: 11, color: AppColors.inkSoft),
            ),
          ],
        ],

        // The anchor: where this sitting began, and the one before it. Without
        // this the reader has to remember, or go and look.
        if (start != null || widget.lastSessionLine != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.paperDeep,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.subdirectory_arrow_left, size: 14, color: AppColors.inkSoft),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (start != null)
                        Text(
                          l10n.stopStartedAtPage(start),
                          style: TextStyle(fontSize: 11, color: AppColors.ink),
                        ),
                      if (widget.lastSessionLine != null)
                        Text(
                          widget.lastSessionLine!,
                          style: TextStyle(fontSize: 10, color: AppColors.inkSoft),
                        ),
                    ],
                  ),
                ),
                if (widget.onOpenLog != null)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onOpenLog,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            l10n.stopOpenLog,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.oxblood,
                            ),
                          ),
                          Icon(Icons.chevron_right, size: 14, color: AppColors.oxblood),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],

        // R2 — the total, only when the catalogue hasn't got one. Gold because
        // it improves the *shared* Edition, and the copy says so rather than
        // quietly harvesting it.
        if (total == null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.goldSoft,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE5D3A6)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.stopTotalQuestion,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.goldInk,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 64,
                      child: TextField(
                        controller: widget.totalController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        textAlign: TextAlign.center,
                        style: GoogleFonts.fraunces(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.oxblood,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          filled: true,
                          fillColor: AppColors.card,
                          contentPadding: const EdgeInsets.symmetric(vertical: 6),
                          hintText: l10n.timerTotalFieldHint,
                          hintStyle: TextStyle(fontSize: 12, color: AppColors.inkSoft),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Color(0xFFE5D3A6)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Color(0xFFE5D3A6)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.stopTotalUnit,
                      style: const TextStyle(fontSize: 11, color: Color(0xFF8A6F34)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.stopTotalWhy,
                  style: const TextStyle(
                    fontSize: 10,
                    height: 1.45,
                    color: Color(0xFF8A6F34),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// A −/+ around the numeral. Tap moves one page, long-press ten — the two
/// distances a reader is actually out by.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.icon,
    required this.enabled,
    required this.onTap,
    required this.onLongPress,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: InkWell(
        onTap: enabled ? onTap : null,
        onLongPress: enabled ? onLongPress : null,
        customBorder: const CircleBorder(),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.card,
            border: Border.all(color: AppColors.line),
          ),
          child: Icon(
            icon,
            size: 18,
            color: AppColors.inkSoft,
          ),
        ),
      ),
    );
  }
}

/// Formats the "Last time · 12 Jul · 38m · p. 214 → 260" line. Null when the
/// previous sitting noted no page at all — a line with a blank in it is worse
/// than no line.
///
/// A sitting with an end page but no start (the first one on a book with no
/// recorded progress) still knows the fact that matters here — where the reader
/// got to — so it gets the shorter "ended on p. 260" form rather than being
/// dropped (owner report, 31 Jul 2026: the same blind spot that made the
/// reading log say "Page not noted" for that sitting).
String? formatLastSessionLine(
  AppLocalizations l10n, {
  required DateTime? endedAt,
  required int durationSeconds,
  required int? pageStart,
  required int? pageEnd,
}) {
  if (endedAt == null || pageEnd == null) return null;
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final local = endedAt.toLocal();
  final date = '${local.day} ${months[local.month - 1]}';
  final duration = formatDuration(Duration(seconds: durationSeconds));
  if (pageStart == null || pageEnd <= pageStart) {
    return l10n.stopLastSessionTo(date, duration, pageEnd);
  }
  return l10n.stopLastSession(date, duration, pageStart, pageEnd);
}
