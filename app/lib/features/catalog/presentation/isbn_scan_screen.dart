import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/haptics.dart';
import '../../../core/quiet_error.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/action_plates.dart';
import '../../../core/widgets/status_pill.dart';
import '../../../core/widgets/typeset_cover.dart';
import '../../../data/api/api_client.dart';
import '../../../data/db/catalog_cache.dart';
import '../../../data/db/database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../data/sync/sync_providers.dart';
import '../../../l10n/app_localizations.dart';
import '../work_editions.dart';

/// S7 — point the camera at a barcode; on a decode, resolve it through
/// `GET /catalog/isbn/{isbn}` (local match, else OpenLibrary, cached either
/// way) and show the result.
///
/// **The Bookplate** (owner pick, 14 Aug 2026 — docs/scan-result-mockups.html,
/// direction B, plus its Round 2): the camera has done its job, so it leaves,
/// and the result takes the whole screen as a small book page — rendered in
/// the **app's own theme**, light or dark, because that is what it is. Only
/// the camera state keeps [buildNightOverlayTheme]; a live preview looks the
/// same in any theme, a book page does not, and this screen used to be the one
/// place that ignored the reader's setting.
/// The three things that made the old confirm strip fail were all structural:
/// nothing on screen changed when a book was found (a 56px strip appeared
/// under a still-lit camera), the card was dead text with no way into the
/// book, and its button said only "Add" — naming neither its object nor its
/// consequence, on a screen titled "Add a book" whose neighbour adds to the
/// *shared catalogue*.
///
/// So: the result announces itself by replacing what came before, the whole
/// plate opens the book page that already exists for a book you don't own, and
/// the primary is the book page's own `Add to my library` leather plate with
/// `Wishlist` beside it — the contrast is what makes the primary unambiguous.
/// The printing is named on the face of the card, because a scan resolves an
/// *edition* and `editions.first` shelved a 55-page first printing for a reader
/// holding a 240-page reprint (CLAUDE.md, 13 Aug 2026).
///
/// Every outcome is the same object, not four: found, already-yours, nothing
/// catalogued, couldn't-check. A scanner with one good path and three grey
/// ones is the screen this replaced.
///
/// Two modes:
/// - default (`returnResult == false`): the primary creates a library entry
///   and opens the book — the standalone scan-to-shelf flow.
/// - `returnResult == true`: opened from the manual add-book form. The primary
///   instead pops with the looked-up work (carrying the reader's printing
///   choice as `scanned_edition_id`) so the form can prefill itself; if
///   nothing is found, the user can still pop with just the raw ISBN.
class IsbnScanScreen extends ConsumerStatefulWidget {
  const IsbnScanScreen({super.key, this.returnResult = false});

  final bool returnResult;

  @override
  ConsumerState<IsbnScanScreen> createState() => _IsbnScanScreenState();
}

// The *camera's* constant-dark palette — deliberately not theme-aware: a live
// camera preview looks the same in any theme, and a brightness-aware token on
// a constant surface is how the cream-on-cream bugs happened (AppColors.onDark).
// Nothing below the camera uses these: the result states render in the app's
// own theme (see build()).
const _nightText = Color(0xFFEFE6C8);
const _nightMuted = Color(0xFFA08D6E);
const _nightLine = Color(0xFF4A3A28);
const _nightHi = Color(0xFFF0E2C2);
const _nightInk = Color(0xFF241811);

/// What the scanner is showing. Not-found and lookup-failed are separate
/// states on purpose: only a real 404 means "no book for this ISBN", and an
/// offline moment that says so invites the exact duplicate the catalogue
/// exists to prevent.
enum _ScanState { scanning, found, notFound, failed }

class _IsbnScanScreenState extends ConsumerState<IsbnScanScreen> {
  final _controller = MobileScannerController(formats: [BarcodeFormat.ean13]);

  _ScanState _state = _ScanState.scanning;
  String? _detectedIsbn;
  Map<String, dynamic>? _work;

  /// The printing going on the shelf — the one the barcode belongs to until
  /// the reader says otherwise.
  Map<String, dynamic>? _edition;

  /// The reader's existing entry for [_edition], if this book is already on
  /// their shelf. Null in form mode, which is not about the shelf at all.
  LibraryEntry? _existing;

  bool _pickingPrinting = false;
  bool _loading = false;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_loading || _detectedIsbn != null) return;
    final isbn = capture.barcodes.firstOrNull?.rawValue;
    if (isbn == null) return;
    // Claim the scan *before* the first await: the camera keeps firing
    // detections while `stop()` is in flight, and a second one that slipped
    // through this guard would run the whole lookup twice.
    setState(() {
      _detectedIsbn = isbn;
      _loading = true;
    });
    await _controller.stop();
    await _lookup(isbn);
  }

  Future<void> _lookup(String isbn) async {
    setState(() {
      _detectedIsbn = isbn;
      _loading = true;
      _state = _ScanState.scanning;
    });

    try {
      final work = await ref.read(apiClientProvider).lookupIsbn(isbn);
      final edition = scannedEdition(work);
      // Whether it is already on the shelf is part of the answer, not a
      // snackbar after the fact — a re-scan should be able to *find* a book,
      // not just fail to file it twice.
      LibraryEntry? existing;
      if (!widget.returnResult && edition != null) {
        final repo = await ref.read(libraryRepositoryProvider.future);
        existing = await repo.getByEditionId(edition['id'] as String);
      }
      if (!mounted) return;
      Haptics.selection();
      setState(() {
        _work = work;
        _edition = edition;
        _existing = existing;
        _pickingPrinting = false;
        _state = _ScanState.found;
      });
    } on DioException catch (err) {
      if (!mounted) return;
      setState(() =>
          _state = err.response?.statusCode == 404 ? _ScanState.notFound : _ScanState.failed);
    } catch (_) {
      if (mounted) setState(() => _state = _ScanState.failed);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _reset() {
    setState(() {
      _state = _ScanState.scanning;
      _detectedIsbn = null;
      _work = null;
      _edition = null;
      _existing = null;
      _pickingPrinting = false;
    });
    _controller.start();
  }

  /// Create the entry and open the book, or — for a wishlist add — let the
  /// shelf answer back in place so the reader can carry on scanning.
  Future<void> _add(String status) async {
    final work = _work;
    final edition = _edition;
    if (work == null || edition == null || _busy) return;
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final editionId = edition['id'] as String;
      // Cache before creating the entry so the grid/home cover tiles that
      // rebuild on the insert already find the catalog data (rule 2).
      await cacheBookForOffline(ref.read(appDatabaseProvider), work, edition);
      final repo = await ref.read(libraryRepositoryProvider.future);
      await repo.add(editionId: editionId, status: status);
      if (!mounted) return;
      if (status == 'wishlist') {
        final entry = await repo.getByEditionId(editionId);
        if (!mounted) return;
        messenger.showSnackBar(SnackBar(content: Text(l10n.bookWishlistAdded)));
        setState(() {
          _existing = entry;
          _busy = false;
        });
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text(l10n.scanAddedToLibrary)));
      _openBook(replace: true);
    } catch (err) {
      if (!mounted) return;
      setState(() => _busy = false);
      showQuietError(context, l10n.quickAddFailed, err);
    }
  }

  /// The door. [replace] when the scan is finished with (the book was added,
  /// or it was already yours); a plain push when the reader is only looking,
  /// so backing out returns to the result rather than the camera.
  void _openBook({bool replace = false}) {
    final work = _work;
    final edition = _edition;
    if (work == null || edition == null) return;
    final path = Routes.bookDetailPath(work['id'] as String, edition['id'] as String);
    replace ? context.pushReplacement(path) : context.push(path);
  }

  /// Form mode's primary. The printing the reader confirmed here rides back as
  /// `scanned_edition_id`, which is what the form already resolves through —
  /// so the question is asked once, on the screen that can answer it.
  void _useDetails() {
    final work = Map<String, dynamic>.from(_work!);
    if (_edition != null) work['scanned_edition_id'] = _edition!['id'];
    context.pop(work);
  }

  /// Carry the scanned-but-unmatched number into the blank form — it was
  /// already read, never make the reader type it.
  void _addManually() {
    final isbn = _detectedIsbn;
    context.pop();
    context.push(Routes.catalogAdd, extra: <String, dynamic>{'isbn': ?isbn});
  }

  @override
  Widget build(BuildContext context) {
    // Only the camera is a camera. Once it has done its job and left the
    // screen, the result is a book page — so it renders in the app's own
    // theme, light or dark, like every other book page (owner request,
    // 14 Aug 2026; docs/scan-result-mockups.html, Round 2). The scanner was
    // otherwise the one screen that ignored the reader's theme setting.
    if (_state == _ScanState.scanning) {
      return Theme(
        data: buildNightOverlayTheme(),
        child: Scaffold(
          backgroundColor: AppColors.night,
          body: SafeArea(
            child: _CameraView(
              controller: _controller,
              onDetect: _onDetect,
              loading: _loading,
              detectedIsbn: _detectedIsbn,
              returnResult: widget.returnResult,
              onSearch: () {
                context.pop();
                context.push(Routes.catalogSearch);
              },
              onAddManually: _addManually,
              l10n: AppLocalizations.of(context)!,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: switch (_state) {
          _ScanState.found => ScanFoundView(
              work: _work!,
              edition: _edition,
              existing: _existing,
              detectedIsbn: _detectedIsbn,
              picking: _pickingPrinting,
              busy: _busy,
              returnResult: widget.returnResult,
              onPick: () => setState(() => _pickingPrinting = true),
              onChoose: (edition) => setState(() {
                _edition = edition;
                _pickingPrinting = false;
              }),
              onAdd: () => _add('pending'),
              onWishlist: () => _add('wishlist'),
              onUseDetails: _useDetails,
              onOpenBook: _openBook,
              onOpenOwned: () => _openBook(replace: true),
              onScanAgain: _reset,
            ),
          _ScanState.notFound => ScanMissView(
              isbn: _detectedIsbn ?? '',
              returnResult: widget.returnResult,
              onAdd: widget.returnResult
                  ? () => context.pop({'isbn': _detectedIsbn})
                  : _addManually,
              onSearch: () {
                context.pop();
                context.push(Routes.catalogSearch);
              },
              onScanAgain: _reset,
            ),
          _ScanState.failed => ScanFailedView(
              onRetry: () => _lookup(_detectedIsbn!),
              onScanAgain: _reset,
              onTypeItIn: widget.returnResult
                  ? () => context.pop({'isbn': _detectedIsbn})
                  : _addManually,
            ),
          // Handled above — the camera keeps its own dark theme.
          _ScanState.scanning => SizedBox.shrink(),
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Shared result furniture — app theme (paper/ink), not the camera's dark
// ─────────────────────────────────────────────────────────────────────────

/// Back arrow on the left, an outcome stamp on the right. The stamp is the
/// scan's *headline* — the reader should know what happened before reading a
/// word of the book's metadata.
class _ResultHeader extends StatelessWidget {
  const _ResultHeader({this.stamp, this.stampInk});

  final String? stamp;

  /// The stamp's own colour; its fill is the same hue at low alpha, so one
  /// token carries both and stays legible in either theme. (There is no
  /// `mossSoft`/`oxbloodSoft` token, and the status-pill tints are constants
  /// built for paper — they would glow on the dark theme.)
  final Color? stampInk;

  @override
  Widget build(BuildContext context) {
    final ink = stampInk ?? AppColors.moss;
    return Padding(
      padding: EdgeInsets.only(right: 14),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back, color: AppColors.ink),
            onPressed: () => context.pop(),
          ),
          Spacer(),
          if (stamp != null)
            Container(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: ink.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                stamp!.toUpperCase(),
                style: TextStyle(
                  color: ink,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A bordered full-width control — the third weight, under the leather and
/// paper plates: "Open the full book page", "Scan again".
class _GhostButton extends StatelessWidget {
  const _GhostButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            label,
            style: TextStyle(color: AppColors.slate, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

class _Stars extends StatelessWidget {
  const _Stars({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            value >= i - 0.25
                ? Icons.star
                : (value >= i - 0.75 ? Icons.star_half : Icons.star_border),
            size: 13,
            color: AppColors.gold,
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// The camera itself
// ─────────────────────────────────────────────────────────────────────────

class _CameraView extends StatelessWidget {
  const _CameraView({
    required this.controller,
    required this.onDetect,
    required this.loading,
    required this.detectedIsbn,
    required this.returnResult,
    required this.onSearch,
    required this.onAddManually,
    required this.l10n,
  });

  final MobileScannerController controller;
  final void Function(BarcodeCapture) onDetect;
  final bool loading;
  final String? detectedIsbn;
  final bool returnResult;
  final VoidCallback onSearch;
  final VoidCallback onAddManually;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back, color: _nightText),
                onPressed: () => context.pop(),
              ),
            ],
          ),
        ),
        Text(
          l10n.scanTitle,
          style: TextStyle(color: _nightText, fontSize: 17, fontWeight: FontWeight.w600),
        ),
        SizedBox(height: 4),
        Text(l10n.scanSubtitle, style: TextStyle(color: _nightMuted, fontSize: 12)),
        SizedBox(height: 16),
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.gold, width: 1.5),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: MobileScanner(
                        controller: controller,
                        onDetect: onDetect,
                        // The FAB lands here directly (scan-first), so a dead
                        // camera must point at the Search/Add fallbacks below,
                        // not print a raw error code.
                        errorBuilder: (context, error, child) => _CameraUnavailable(
                          message: returnResult
                              ? l10n.scanCameraUnavailableShort
                              : l10n.scanCameraUnavailable,
                        ),
                      ),
                    ),
                    // The one thing worth saying over a live camera: the
                    // number has been read and is being looked up.
                    if (loading)
                      Positioned.fill(
                        child: ColoredBox(
                          color: _nightInk.withValues(alpha: 0.74),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(color: AppColors.gold),
                              SizedBox(height: 14),
                              Text(
                                l10n.scanLookingUp,
                                style: TextStyle(color: _nightText, fontSize: 12.5),
                              ),
                              if (detectedIsbn != null) ...[
                                SizedBox(height: 6),
                                _IsbnPill(isbn: detectedIsbn!, onNight: true),
                              ],
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        SizedBox(height: 14),
        if (!returnResult)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Expanded(child: _GhostButton(label: l10n.scanSearchInstead, onTap: onSearch)),
                SizedBox(width: 10),
                Expanded(child: _GhostButton(label: l10n.scanAddManually, onTap: onAddManually)),
              ],
            ),
          ),
        SizedBox(height: 12),
      ],
    );
  }
}

/// The scanned number, shown as a fact rather than a caption. Two grounds:
/// over the live camera ([onNight]) and on the miss card, which is paper.
class _IsbnPill extends StatelessWidget {
  const _IsbnPill({required this.isbn, this.onNight = false});

  final String isbn;
  final bool onNight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: onNight ? AppColors.gold.withValues(alpha: 0.18) : AppColors.goldSoft,
        border: Border.all(color: AppColors.gold.withValues(alpha: onNight ? 0.5 : 0.45)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        isbn,
        style: TextStyle(
          color: onNight ? _nightHi : AppColors.goldInk,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

/// A refused camera permission is a first-run state, not an edge case — the
/// FAB lands here directly. The frame itself carries the message, and the two
/// routes around it are the buttons already under this box.
class _CameraUnavailable extends StatelessWidget {
  const _CameraUnavailable({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 32,
              decoration: BoxDecoration(
                border: Border.all(color: _nightLine, width: 1.5),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final width in const [2.0, 4.0, 2.0, 5.0, 2.0])
                    Container(
                      width: width,
                      height: 14,
                      margin: EdgeInsets.symmetric(horizontal: 1),
                      color: _nightLine,
                    ),
                ],
              ),
            ),
            SizedBox(height: 12),
            Text(
              message,
              style: TextStyle(color: _nightText, fontSize: 12, height: 1.5),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// The result — direction B, "The Bookplate"
// ─────────────────────────────────────────────────────────────────────────

class ScanFoundView extends StatelessWidget {
  const ScanFoundView({
    super.key,
    required this.work,
    required this.edition,
    required this.existing,
    required this.detectedIsbn,
    required this.picking,
    required this.busy,
    required this.returnResult,
    required this.onPick,
    required this.onChoose,
    required this.onAdd,
    required this.onWishlist,
    required this.onUseDetails,
    required this.onOpenBook,
    required this.onOpenOwned,
    required this.onScanAgain,
  });

  final Map<String, dynamic> work;
  final Map<String, dynamic>? edition;
  final LibraryEntry? existing;
  final String? detectedIsbn;
  final bool picking;
  final bool busy;
  final bool returnResult;
  final VoidCallback onPick;
  final void Function(Map<String, dynamic>) onChoose;
  final Future<void> Function() onAdd;
  final Future<void> Function() onWishlist;
  final VoidCallback onUseDetails;
  final VoidCallback onOpenBook;
  final VoidCallback onOpenOwned;
  final VoidCallback onScanAgain;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final editions = editionsOf(work);
    final authors = (work['authors'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final authorNames = authors.map((a) => a['name'] as String).join(', ');
    final owned = existing != null;

    return Column(
      children: [
        _ResultHeader(
          stamp: owned
              ? l10n.scanAlreadyYours
              : (editions.length > 1
                  ? l10n.scanGotItPrintings(editions.length)
                  : l10n.scanGotIt),
          stampInk: owned ? AppColors.goldInk : AppColors.moss,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(14, 2, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Frontispiece(
                  work: work,
                  edition: edition,
                  entry: existing,
                  detectedIsbn: detectedIsbn,
                  authorNames: authorNames,
                ),
                _Blurb(work: work),
                if (edition != null)
                  _PrintingBlock(
                    editions: editions,
                    chosen: edition!,
                    scannedId: work['scanned_edition_id'] as String?,
                    picking: picking,
                    onPick: onPick,
                    onChoose: onChoose,
                  )
                else
                  Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text(
                      l10n.scanNoPrinting,
                      style: TextStyle(color: AppColors.inkSoft, fontSize: 10.5, height: 1.5),
                    ),
                  ),
                _GenreChips(work: work),
                _TranslationsLine(work: work),
              ],
            ),
          ),
        ),
        _FoundActions(
          hasEdition: edition != null,
          owned: owned,
          picking: picking,
          busy: busy,
          returnResult: returnResult,
          onAdd: onAdd,
          onWishlist: onWishlist,
          onUseDetails: onUseDetails,
          onOpenBook: onOpenBook,
          onOpenOwned: onOpenOwned,
          onScanAgain: onScanAgain,
        ),
      ],
    );
  }
}

/// Cover at a size worth looking at, then everything that tells you whether
/// this is the book in your hand.
class _Frontispiece extends StatelessWidget {
  const _Frontispiece({
    required this.work,
    required this.edition,
    required this.entry,
    required this.detectedIsbn,
    required this.authorNames,
  });

  final Map<String, dynamic> work;
  final Map<String, dynamic>? edition;
  final LibraryEntry? entry;
  final String? detectedIsbn;
  final String authorNames;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final title = work['title'] as String;
    final rating = (work['aggregate_rating'] as num?)?.toDouble();
    final isbn = edition?['isbn'] as String? ?? detectedIsbn;
    final meta = [
      if (work['form'] != null) work['form'] as String,
      if (work['language'] != null) work['language'] as String,
      if (work['first_publish_year'] != null) '${work['first_publish_year']}',
    ].join(' · ');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TypesetCover(
          title: title,
          author: authorNames.isNotEmpty ? authorNames : null,
          coverUrl: edition?['cover_url'] as String?,
          width: 74,
          height: 108,
        ),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.fraunces(
                  fontSize: 17.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.ink,
                  height: 1.2,
                ),
              ),
              if (authorNames.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(top: 3),
                  child: Text(
                    authorNames,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.oxblood,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              if (meta.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(meta, style: TextStyle(color: AppColors.inkSoft, fontSize: 10.5)),
                ),
              if (rating != null)
                Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      _Stars(value: rating),
                      SizedBox(width: 6),
                      Text(
                        rating.toStringAsFixed(1),
                        style: TextStyle(
                          color: AppColors.inkSoft,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              // Already yours: the shelf answers with where you'd left it.
              if (entry != null) ...[
                SizedBox(height: 7),
                Row(
                  children: [
                    StatusPill(status: entry!.status),
                    SizedBox(width: 6),
                    Flexible(child: _ProgressLine(entry: entry!, edition: edition)),
                  ],
                ),
              ],
              if (isbn != null)
                Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    l10n.scanIsbnLine(isbn),
                    style: TextStyle(color: AppColors.stampGrey, fontSize: 9.5),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.entry, required this.edition});

  final LibraryEntry entry;
  final Map<String, dynamic>? edition;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final page = entry.currentPage;
    if (page == null || page <= 0) return SizedBox.shrink();
    final total = edition?['page_count'] as int?;
    final text = total != null && total > 0
        ? l10n.bookProgressValue(page, total, ((page / total) * 100).round())
        : l10n.bookProgressPage(page);
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: AppColors.inkSoft, fontSize: 10.5),
    );
  }
}

class _Blurb extends StatelessWidget {
  const _Blurb({required this.work});

  final Map<String, dynamic> work;

  @override
  Widget build(BuildContext context) {
    final description = (work['description'] as String?)?.trim();
    if (description == null || description.isEmpty) return SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: 10),
      child: Text(
        description,
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.fraunces(
          fontSize: 11.5,
          fontStyle: FontStyle.italic,
          color: AppColors.inkSoft,
          height: 1.5,
        ),
      ),
    );
  }
}

/// Which printing is going on the shelf, said out loud.
///
/// Collapsed it names the scanned one (the page count is the fact that makes
/// it checkable); "N others" opens the list in place rather than in a sheet,
/// because the reader is holding the book *now*. `chooseEdition`'s sheet
/// stays the pattern everywhere the answer isn't already known.
class _PrintingBlock extends StatelessWidget {
  const _PrintingBlock({
    required this.editions,
    required this.chosen,
    required this.scannedId,
    required this.picking,
    required this.onPick,
    required this.onChoose,
  });

  final List<Map<String, dynamic>> editions;
  final Map<String, dynamic> chosen;
  final String? scannedId;
  final bool picking;
  final VoidCallback onPick;
  final void Function(Map<String, dynamic>) onChoose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (!picking) {
      final label = editionLabel(chosen);
      return Container(
        margin: EdgeInsets.only(top: 10),
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (chosen['id'] == scannedId || scannedId == null
                            ? l10n.scanPrintingScanned
                            : l10n.scanPrintingChosen)
                        .toUpperCase(),
                    style: TextStyle(
                      // goldInk, not gold: gold on card is 3.4:1 in light mode.
                      color: AppColors.goldInk,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    label.isEmpty ? l10n.editionPickFallback : label,
                    style: TextStyle(color: AppColors.ink, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (editions.length > 1) ...[
              SizedBox(width: 8),
              SizedBox(
                width: 92,
                child: _GhostButton(
                  label: l10n.scanOtherPrintings(editions.length - 1),
                  onTap: onPick,
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.scanWhichPrinting.toUpperCase(),
            style: TextStyle(
              color: AppColors.inkSoft,
              fontSize: 8.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
          SizedBox(height: 7),
          for (final edition in editions)
            _PrintingRow(
              edition: edition,
              selected: edition['id'] == chosen['id'],
              scanned: edition['id'] == scannedId,
              onTap: () => onChoose(edition),
            ),
          SizedBox(height: 8),
          Text(
            l10n.scanPageCountsDiffer,
            style: TextStyle(color: AppColors.inkSoft, fontSize: 9.5, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _PrintingRow extends StatelessWidget {
  const _PrintingRow({
    required this.edition,
    required this.selected,
    required this.scanned,
    required this.onTap,
  });

  final Map<String, dynamic> edition;
  final bool selected;
  final bool scanned;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final label = editionLabel(edition);
    return Padding(
      padding: EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? AppColors.card : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              border: Border.all(color: selected ? AppColors.gold : AppColors.line),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  size: 15,
                  color: selected ? AppColors.gold : AppColors.line,
                ),
                SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label.isEmpty ? l10n.editionPickFallback : label,
                        style: TextStyle(
                          color: selected ? AppColors.ink : AppColors.inkSoft,
                          fontSize: 11,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                      if (scanned)
                        Text(
                          l10n.scanPrintingBarcodeNote,
                          style: TextStyle(color: AppColors.goldInk, fontSize: 9),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GenreChips extends StatelessWidget {
  const _GenreChips({required this.work});

  final Map<String, dynamic> work;

  @override
  Widget build(BuildContext context) {
    final genres = (work['genres'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    if (genres.isEmpty) return SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 5,
        runSpacing: 5,
        children: [
          for (final genre in genres.take(4))
            Container(
              padding: EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.card,
                border: Border.all(color: AppColors.line),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                genre['name'] as String,
                style: TextStyle(color: AppColors.inkSoft, fontSize: 9.5),
              ),
            ),
        ],
      ),
    );
  }
}

/// The wedge showing up where it costs nothing: this book already has other
/// language editions in the catalogue, and the payload already says so.
class _TranslationsLine extends StatelessWidget {
  const _TranslationsLine({required this.work});

  final Map<String, dynamic> work;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final translations = (work['translations'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    // A summary carries no language of its own — its representative edition
    // does, which is how the book page's translation rows read it too.
    final languages = <String>{};
    for (final translation in translations) {
      final edition = translation['edition'] as Map<String, dynamic>?;
      final language = edition?['language'] as String?;
      if (language != null && language != work['language']) languages.add(language);
    }
    if (languages.isEmpty) return SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Icon(Icons.swap_horiz, size: 14, color: AppColors.slate),
          SizedBox(width: 6),
          Expanded(
            child: Text(
              l10n.scanTranslatedInto(languages.join(', ')),
              style: TextStyle(color: AppColors.inkSoft, fontSize: 10.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// The offer. The primary names its object; `Wishlist` beside it is what makes
/// that primary unambiguous (want vs. have). Neither is the only way out —
/// the book page and the next barcode sit under them.
class _FoundActions extends StatelessWidget {
  const _FoundActions({
    required this.hasEdition,
    required this.owned,
    required this.picking,
    required this.busy,
    required this.returnResult,
    required this.onAdd,
    required this.onWishlist,
    required this.onUseDetails,
    required this.onOpenBook,
    required this.onOpenOwned,
    required this.onScanAgain,
  });

  final bool hasEdition;
  final bool owned;
  final bool picking;
  final bool busy;
  final bool returnResult;
  final Future<void> Function() onAdd;
  final Future<void> Function() onWishlist;
  final VoidCallback onUseDetails;
  final VoidCallback onOpenBook;
  final VoidCallback onOpenOwned;
  final VoidCallback onScanAgain;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 6, 14, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (returnResult)
            Row(
              children: [
                Expanded(
                  child: LeatherPlate(
                    label: l10n.scanUseDetails,
                    onTap: () async => onUseDetails(),
                  ),
                ),
              ],
            )
          else if (owned)
            Row(
              children: [
                Expanded(
                  child: LeatherPlate(
                    label: l10n.scanOpenIt,
                    onTap: () async => onOpenOwned(),
                  ),
                ),
              ],
            )
          else if (hasEdition)
            Row(
              children: [
                Expanded(
                  child: LeatherPlate(
                    // While the printings are open, the primary names the
                    // choice being made rather than the shelf it lands on.
                    label: picking ? l10n.scanAddThisPrinting : l10n.bookAddToLibrary,
                    onTap: busy ? () async {} : onAdd,
                  ),
                ),
                SizedBox(width: 9),
                PaperPlate(
                  label: l10n.bookWishlistShort,
                  onTap: busy ? () async {} : onWishlist,
                ),
              ],
            ),
          // The door, except where it would be a trap: an owned book's primary
          // already opens it, and in form mode it would push the book page —
          // whose own button shelves the book — on top of a half-filled add
          // form. The form has its own "already in the catalogue?" fork for
          // that; this screen's errand there is only to prefill.
          if (!owned && !returnResult) ...[
            SizedBox(height: 8),
            _GhostButton(label: l10n.scanOpenBookPage, onTap: onOpenBook),
          ],
          SizedBox(height: 6),
          TextButton(
            onPressed: onScanAgain,
            style: TextButton.styleFrom(foregroundColor: AppColors.inkSoft),
            child: Text(l10n.scanAnother, style: TextStyle(fontSize: 11.5)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Nothing found / couldn't check
// ─────────────────────────────────────────────────────────────────────────

/// The state that decides whether Kitabi's regional catalogue ever gets built.
/// A dead end reads as a broken app, so it says *why* (regional printings are
/// thinly listed) and reframes the reader as the first contributor rather than
/// the victim of a miss. The ISBN carries into the form — never retyped.
class ScanMissView extends StatelessWidget {
  const ScanMissView({
    super.key,
    required this.isbn,
    required this.returnResult,
    required this.onAdd,
    required this.onSearch,
    required this.onScanAgain,
  });

  final String isbn;
  final bool returnResult;
  final VoidCallback onAdd;
  final VoidCallback onSearch;
  final VoidCallback onScanAgain;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        _ResultHeader(stamp: l10n.scanNotFoundStamp, stampInk: AppColors.oxblood),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.card,
                border: Border.all(color: AppColors.line),
                borderRadius: BorderRadius.circular(12),
              ),
              // The accent rule is a clipped child, not a thicker left border:
              // borderRadius + a non-uniform Border throws at paint time.
              clipBehavior: Clip.antiAlias,
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(width: 3, color: AppColors.oxblood),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(12, 12, 12, 13),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.scanNotFoundTitle,
                              style: GoogleFonts.fraunces(
                                fontSize: 16.5,
                                fontWeight: FontWeight.w500,
                                color: AppColors.ink,
                                height: 1.25,
                              ),
                            ),
                            SizedBox(height: 9),
                            _IsbnPill(isbn: isbn),
                            SizedBox(height: 11),
                            Text(
                              l10n.scanNotFoundBody,
                              style:
                                  TextStyle(color: AppColors.inkSoft, fontSize: 12, height: 1.55),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(14, 0, 14, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: LeatherPlate(
                      label: returnResult ? l10n.scanUseIsbnAnyway : l10n.scanNotFoundAdd,
                      onTap: () async => onAdd(),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 5),
              Text(
                l10n.scanIsbnCarried,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.inkSoft, fontSize: 10),
              ),
              SizedBox(height: 9),
              Row(
                children: [
                  if (!returnResult) ...[
                    Expanded(child: _GhostButton(label: l10n.scanSearchByTitle, onTap: onSearch)),
                    SizedBox(width: 9),
                  ],
                  Expanded(child: _GhostButton(label: l10n.scanAgain, onTap: onScanAgain)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Deliberately *not* the not-found state: only a real 404 means "no book for
/// that ISBN". An offline moment that says "you'd be the first to add it"
/// invites the exact duplicate the catalogue exists to prevent.
class ScanFailedView extends StatelessWidget {
  const ScanFailedView({
    super.key,
    required this.onRetry,
    required this.onScanAgain,
    required this.onTypeItIn,
  });

  final Future<void> Function() onRetry;
  final VoidCallback onScanAgain;
  final VoidCallback onTypeItIn;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        _ResultHeader(),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.scanOfflineTitle,
                  style: GoogleFonts.fraunces(
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                    color: AppColors.ink,
                    height: 1.25,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  l10n.scanOfflineBody,
                  style: TextStyle(color: AppColors.inkSoft, fontSize: 12, height: 1.55),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(14, 0, 14, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(child: LeatherPlate(label: l10n.scanTryAgain, onTap: onRetry)),
                  SizedBox(width: 9),
                  Expanded(child: _GhostButton(label: l10n.scanAgain, onTap: onScanAgain)),
                ],
              ),
              SizedBox(height: 8),
              TextButton(
                onPressed: onTypeItIn,
                style: TextButton.styleFrom(foregroundColor: AppColors.slate),
                child: Text(
                  l10n.scanTypeItIn,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
