import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/haptics.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/typeset_cover.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../data/sync/sync_providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../catalog/providers/catalog_providers.dart';
import '../providers/library_providers.dart';

/// Dedicated rate & review page — one place to set the star rating (Work-level,
/// rule 17) and write the text review with its visibility flag (rule 13,
/// default private). Everything saves together on the one Save button; reads
/// and writes go through the offline-first repositories only.
class ReviewEditorScreen extends ConsumerStatefulWidget {
  const ReviewEditorScreen({
    super.key,
    required this.workId,
    this.title,
    this.author,
    this.coverUrl,
  });

  final String workId;
  final String? title;
  final String? author;
  final String? coverUrl;

  @override
  ConsumerState<ReviewEditorScreen> createState() => _ReviewEditorScreenState();
}

class _ReviewEditorScreenState extends ConsumerState<ReviewEditorScreen> {
  final _body = TextEditingController();
  int _stars = 0;
  bool _visible = false;
  bool _loaded = false;
  bool _saving = false;

  /// What existed when the editor opened — the difference between "nothing to
  /// save" and "the reader took it back".
  bool _hadReview = false;
  bool _hadRating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // Straight off the repositories — reading an autoDispose provider's
    // .future without a listener can dispose it before it resolves.
    final reviewsRepo = await ref.read(reviewsRepositoryProvider.future);
    final ratingsRepo = await ref.read(ratingsRepositoryProvider.future);
    final review = await reviewsRepo.watchForWork(widget.workId).first;
    final rating = await ratingsRepo.watchForWork(widget.workId).first;
    if (!mounted) return;
    setState(() {
      _body.text = review?.body ?? '';
      _visible = review?.visible ?? false;
      _stars = rating?.value ?? 0;
      _hadReview = review != null;
      _hadRating = rating != null;
      _loaded = true;
    });
  }

  /// Saves what's here and takes back what was emptied — and says which one
  /// actually happened. An emptied body deletes the review; zero stars where
  /// a rating existed clears it. Never claims "saved" when nothing was written.
  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    // Outlives this screen — the sync kick below runs after the pop unmounts
    // it, when `ref` is no longer usable (the quick-stop lesson, CLAUDE.md).
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      final ratingsRepo = await ref.read(ratingsRepositoryProvider.future);
      final reviewsRepo = await ref.read(reviewsRepositoryProvider.future);
      final body = _body.text.trim();

      var ratingCleared = false;
      var ratingWritten = false;
      if (_stars > 0) {
        await ratingsRepo.setRating(widget.workId, _stars);
        ratingWritten = true;
      } else if (_hadRating) {
        await ratingsRepo.clearRating(widget.workId);
        ratingCleared = true;
      }

      var reviewDeleted = false;
      var reviewWritten = false;
      if (body.isNotEmpty) {
        await reviewsRepo.upsert(widget.workId, body: body, visible: _visible);
        reviewWritten = true;
      } else if (_hadReview) {
        await reviewsRepo.removeForWork(widget.workId);
        reviewDeleted = true;
      }

      ref.invalidate(ratingProvider(widget.workId));
      ref.invalidate(reviewProvider(widget.workId));

      // Name what actually happened. Nothing at all changed → just leave,
      // claiming nothing.
      final message = reviewDeleted
          ? l10n.reviewDeleted
          : reviewWritten
              ? l10n.reviewSaved
              : ratingCleared
                  ? l10n.ratingCleared
                  : ratingWritten
                      ? l10n.ratingSaved
                      : null;
      if (message != null) {
        Haptics.success();
        messenger.showSnackBar(SnackBar(content: Text(message)));
      }
      // Offline-first: pop on the LOCAL write. The server aggregate refresh
      // (publicReviewsProvider reads the pushed state) rides a background
      // sync round-trip instead of holding the reader on a spinner.
      if (navigator.canPop()) navigator.pop(true);
      if (message != null) {
        unawaited(container.read(syncNowProvider)().then((_) {
          container.invalidate(publicReviewsProvider(widget.workId));
        }));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(title: Text(l10n.reviewPageTitle)),
      body: !_loaded
          ? Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.title != null) ...[
                      Row(
                        children: [
                          TypesetCover(
                            title: widget.title!,
                            author: widget.author,
                            coverUrl: widget.coverUrl,
                            width: 40,
                            height: 58,
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.title!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.ink,
                                  ),
                                ),
                                if (widget.author != null)
                                  Text(
                                    widget.author!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 18),
                    ],
                    Text(
                      l10n.reviewRatingLabel,
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1,
                        color: AppColors.inkSoft,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 6),
                    Row(
                      children: [
                        for (var i = 1; i <= 5; i++)
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              Haptics.selection();
                              // A second tap on the selected star takes the
                              // rating back to none.
                              setState(() => _stars = _stars == i ? 0 : i);
                            },
                            // ≥44px target: 36px glyph + 4px vertical padding.
                            child: Padding(
                              padding: EdgeInsets.only(right: 8, top: 4, bottom: 4),
                              child: Icon(
                                i <= _stars ? Icons.star : Icons.star_border,
                                size: 36,
                                color: AppColors.gold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: 18),
                    Text(
                      l10n.bookReviewLabel,
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1,
                        color: AppColors.inkSoft,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 6),
                    Expanded(
                      child: TextField(
                        controller: _body,
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        keyboardType: TextInputType.multiline,
                        textCapitalization: TextCapitalization.sentences,
                        // The review is the home of the literary voice —
                        // Fraunces italic, matching the card it lands on.
                        style: GoogleFonts.fraunces(
                          fontStyle: FontStyle.italic,
                          fontSize: 14.5,
                          color: AppColors.ink,
                          height: 1.5,
                        ),
                        decoration: InputDecoration(
                          hintText: l10n.reviewBodyHint,
                          filled: true,
                          fillColor: AppColors.card,
                          contentPadding: EdgeInsets.all(12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: AppColors.line),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: AppColors.line),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _visible
                                ? l10n.bookReviewVisibilityPublic
                                : l10n.bookReviewVisibilityPrivate,
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                        Switch(
                          value: _visible,
                          activeThumbColor: AppColors.gold,
                          onChanged: (v) => setState(() => _visible = v),
                        ),
                      ],
                    ),
                    Text(
                      l10n.reviewVisibilityHint,
                      style: TextStyle(fontSize: 11, color: AppColors.inkSoft, height: 1.25),
                    ),
                    SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.paper,
                                ),
                              )
                            : Text(l10n.bookSave),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
