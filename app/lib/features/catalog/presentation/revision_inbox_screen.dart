import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/haptics.dart';
import '../../../core/quiet_error.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/async_states.dart';
import '../../../data/api/api_client.dart';
import '../../../l10n/app_localizations.dart';
import '../providers/catalog_providers.dart';
import 'picker_widgets.dart';

/// Pending edits to books this reader contributed (wiki moderation, V1: the
/// contributor is the approver — proper moderation comes with the community
/// layer). Each card shows what would change; Approve applies it to the live
/// catalog, Reject discards it.
///
/// A card is an edit to the book, or — since 5 Sep 2026 — to one of its
/// printings, which is where the ISBN, page count, format, publisher and
/// covers live. Those used to bypass this screen entirely.
final _pendingRevisionsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  return ref.watch(apiClientProvider).pendingRevisions();
});

/// The reader's own "This is me" author claims. Filing one used to be a dead
/// end — the button said "pending review" and this screen, the only place a
/// reader would think to look, listed work revisions only (owner report,
/// 23 Jul 2026).
final _myClaimsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  return ref.watch(apiClientProvider).myAuthorClaims();
});

class RevisionInboxScreen extends ConsumerWidget {
  const RevisionInboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final revisions = ref.watch(_pendingRevisionsProvider);
    final claims = ref.watch(_myClaimsProvider);

    // Both lists live on one screen because both answer "what did I send in,
    // and where has it got to?" — the question that brought the reader here.
    final claimItems = claims.valueOrNull ?? const <Map<String, dynamic>>[];

    // A claims fetch failure surfaces as a quiet inline row — silently hiding
    // the section read as "no claims", which is a different answer.
    final claimsErrored = claims.hasError;

    return Scaffold(
      backgroundColor: AppColors.paper,
      // The same back-arrow header row the sibling catalog screens use,
      // instead of a stock Material AppBar.
      body: SafeArea(
        child: Column(
          children: [
            PickerHeader(title: l10n.revisionsTitle),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(_pendingRevisionsProvider);
                  ref.invalidate(_myClaimsProvider);
                },
                child: revisions.when(
                  loading: () => ListSkeleton(),
                  error: (err, _) =>
                      ErrorRetry(onRetry: () => ref.invalidate(_pendingRevisionsProvider)),
                  data: (items) => (items.isEmpty && claimItems.isEmpty && !claimsErrored)
                      ? ListView(
                          children: [
                            Padding(
                              padding: EdgeInsets.fromLTRB(32, 96, 32, 32),
                              child: Text(
                                l10n.revisionsEmpty,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AppColors.inkSoft,
                                  fontSize: 13.5,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        )
                      : ListView(
                          padding: EdgeInsets.all(14),
                          children: [
                            if (claimsErrored) ...[
                              _SectionHeader(label: l10n.claimsSectionTitle),
                              _ClaimsErrorRow(
                                onRetry: () => ref.invalidate(_myClaimsProvider),
                              ),
                              SizedBox(height: 10),
                            ] else if (claimItems.isNotEmpty) ...[
                              _SectionHeader(label: l10n.claimsSectionTitle),
                              for (final claim in claimItems) ...[
                                _ClaimCard(claim: claim),
                                SizedBox(height: 10),
                              ],
                            ],
                            if (items.isNotEmpty) ...[
                              if (claimItems.isNotEmpty || claimsErrored) SizedBox(height: 8),
                              _SectionHeader(label: l10n.revisionsSectionTitle),
                              for (final revision in items) ...[
                                _RevisionCard(revision: revision),
                                SizedBox(height: 10),
                              ],
                            ],
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The claims section's quiet inline failure — a sentence and a retry, in
/// place of the cards, never in place of the whole screen.
class _ClaimsErrorRow extends StatelessWidget {
  const _ClaimsErrorRow({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined, size: 16, color: AppColors.inkSoft),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              l10n.claimsLoadFailed,
              style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
            ),
          ),
          TextButton(onPressed: onRetry, child: Text(l10n.commonRetry)),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 10, left: 2),
      child: Text(
        label,
        style: TextStyle(
          color: AppColors.inkSoft,
          fontSize: 11,
          letterSpacing: 1.1,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// One claim, with the way back out of it. Withdraw shows only while the claim
/// is still pending — a decided one is not the claimant's to undo.
class _ClaimCard extends ConsumerStatefulWidget {
  const _ClaimCard({required this.claim});

  final Map<String, dynamic> claim;

  @override
  ConsumerState<_ClaimCard> createState() => _ClaimCardState();
}

class _ClaimCardState extends ConsumerState<_ClaimCard> {
  bool _busy = false;

  Future<void> _withdraw() async {
    final l10n = AppLocalizations.of(context)!;
    final name = widget.claim['author_name'] as String? ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.claimsWithdrawTitle),
        content: Text(l10n.claimsWithdrawBody(name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.bookCancel)),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.claimsWithdraw)),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(apiClientProvider).withdrawAuthorClaim(widget.claim['id'] as String);
      Haptics.success();
      ref.invalidate(_myClaimsProvider);
      messenger.showSnackBar(SnackBar(content: Text(l10n.claimsWithdrawn)));
    } catch (err) {
      if (mounted) {
        showQuietError(context, l10n.claimsWithdrawFailed, err);
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final status = widget.claim['status'] as String? ?? 'pending';
    final pending = status == 'pending';
    final statusLabel = switch (status) {
      'approved' => l10n.claimsApproved,
      'rejected' => l10n.claimsRejected,
      _ => l10n.claimsPending,
    };

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.claim['author_name'] as String? ?? '',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink),
                ),
                SizedBox(height: 3),
                Text(
                  statusLabel,
                  style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
                ),
              ],
            ),
          ),
          if (pending)
            TextButton(
              onPressed: _busy ? null : _withdraw,
              child: Text(l10n.claimsWithdraw),
            ),
        ],
      ),
    );
  }
}

class _RevisionCard extends ConsumerStatefulWidget {
  const _RevisionCard({required this.revision});

  final Map<String, dynamic> revision;

  @override
  ConsumerState<_RevisionCard> createState() => _RevisionCardState();
}

class _RevisionCardState extends ConsumerState<_RevisionCard> {
  bool _busy = false;

  Future<void> _decide({required bool approve}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final api = ref.read(apiClientProvider);
      final id = widget.revision['id'] as String;
      approve ? await api.approveRevision(id) : await api.rejectRevision(id);
      if (approve) Haptics.success();
      messenger.showSnackBar(
        SnackBar(content: Text(approve ? l10n.revisionsApproved : l10n.revisionsRejected)),
      );
      ref.invalidate(_pendingRevisionsProvider);
    } catch (err) {
      messenger.showSnackBar(SnackBar(
        duration: const Duration(seconds: 5),
        content: Text(
          briefError(err).isEmpty
              ? l10n.revisionsDecideFailed
              : '${l10n.revisionsDecideFailed}\n${briefError(err)}',
        ),
      ));
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Human labels for the payload's field keys — reusing the form's own labels
  /// so the diff reads in the user's language. Edition keys sit in the same
  /// map: a revision names either a Work's fields or a printing's, never both,
  /// and the keys don't collide.
  String _fieldLabel(AppLocalizations l10n, String key) => switch (key) {
        'title' => l10n.formFieldTitle,
        'description' => l10n.formFieldDescription,
        'language' => l10n.formFieldLanguage,
        'genre_names' => l10n.formFieldGenres,
        'isbn' => l10n.formFieldIsbn,
        'page_count' => l10n.formFieldPages,
        'format' => l10n.formFieldFormat,
        'publisher_name' || 'publisher_id' => l10n.formFieldPublisher,
        'series_name' || 'series_id' => l10n.formFieldSeries,
        'cover_url' => l10n.revisionsFieldCover,
        'back_cover_url' => l10n.revisionsFieldBackCover,
        _ => key.replaceAll('_', ' '),
      };

  String _fieldValue(dynamic value) =>
      value is List ? value.join(', ') : (value?.toString() ?? '—');

  /// What the live Work currently holds for a payload key — null when the key
  /// can't be mapped (author/translator ids), which falls back to showing the
  /// proposed value alone.
  dynamic _currentValue(Map<String, dynamic>? work, String key) {
    if (work == null) return null;
    return switch (key) {
      'title' => work['title'],
      'subtitle' => work['subtitle'],
      'description' => work['description'],
      'language' => work['language'],
      'first_publish_year' => work['first_publish_year'],
      'form' => work['form'],
      'genre_names' => [
          for (final g in (work['genres'] as List? ?? const []))
            (g as Map)['name'],
        ],
      _ => null,
    };
  }

  /// The same, for a revision that names one printing. The old value has to
  /// come off the *edition* — read off the Work every one of these keys is
  /// null, and a diff that shows no old value invites approving a change
  /// nobody could see the size of.
  dynamic _currentEditionValue(Map<String, dynamic>? edition, String key) {
    if (edition == null) return null;
    return switch (key) {
      'isbn' => edition['isbn'],
      'page_count' => edition['page_count'],
      'format' => edition['format'],
      'language' => edition['language'],
      'pub_date' => edition['pub_date'],
      'cover_url' => edition['cover_url'],
      'back_cover_url' => edition['back_cover_url'],
      'publisher_name' => (edition['publisher'] as Map?)?['name'],
      'series_name' => (edition['series'] as Map?)?['name'],
      'series_number' => edition['series_number'],
      _ => null,
    };
  }

  /// The printing this revision targets, out of the live Work — matched by id,
  /// never `editions[0]`: a Work with several printings would otherwise diff
  /// the edit against whichever one happens to be listed first (CLAUDE.md,
  /// 13 Aug 2026).
  Map<String, dynamic>? _targetEdition(Map<String, dynamic>? work, String? editionId) {
    if (work == null || editionId == null) return null;
    for (final e in (work['editions'] as List? ?? const [])) {
      if (e is Map<String, dynamic> && e['id'] == editionId) return e;
    }
    return null;
  }

  /// How a printing names itself on the card — an ISBN if it has one, else its
  /// format and page count. A contributor deciding an edit to "the 2019
  /// paperback" needs to know it is not the one they hold.
  String _editionLabel(AppLocalizations l10n, Map<String, dynamic>? edition) {
    if (edition == null) return l10n.revisionsEditionScope;
    final parts = [
      if (edition['isbn'] != null) edition['isbn'] as String,
      if (edition['format'] != null) edition['format'] as String,
      if (edition['page_count'] != null) l10n.revisionsEditionPages(edition['page_count'] as int),
    ];
    return parts.isEmpty
        ? l10n.revisionsEditionScope
        : '${l10n.revisionsEditionScope} · ${parts.join(' · ')}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final payload = (widget.revision['payload'] as Map).cast<String, dynamic>();
    final proposer = widget.revision['proposed_by_name'] as String?;
    // M6 — a revision is a *diff*, so fetch the live Work and show old → new.
    // Best-effort: while it loads (or if it can't), the proposed values alone
    // still render, exactly as before.
    final workId = widget.revision['work_id'] as String?;
    final currentWork =
        workId == null ? null : ref.watch(workProvider(workId)).valueOrNull;
    // A revision names the Work, or one of its printings. The queue is shared
    // (one inbox, one approve/reject) — `edition_id` is what tells them apart,
    // and the diff has to be read off whichever row the payload describes.
    final editionId = widget.revision['edition_id'] as String?;
    final targetEdition = _targetEdition(currentWork, editionId);

    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.revision['work_title'] as String? ?? '',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
          ),
          if (editionId != null)
            Padding(
              padding: EdgeInsets.only(top: 3),
              child: Text(
                _editionLabel(l10n, targetEdition),
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 0.6,
                  color: AppColors.oxbloodDeep,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (proposer != null && proposer.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: 2),
              child: Text(
                l10n.revisionsProposedBy(proposer),
                style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft),
              ),
            ),
          SizedBox(height: 8),
          for (final entry in payload.entries)
            Builder(builder: (context) {
              final proposed = _fieldValue(entry.value);
              final current = editionId == null
                  ? _currentValue(currentWork, entry.key)
                  : _currentEditionValue(targetEdition, entry.key);
              final currentText = current == null ? null : _fieldValue(current);
              final unchanged = currentText != null && currentText == proposed;
              return Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(
                      fontSize: 12.5,
                      // A field the revision doesn't actually change is dimmed
                      // — the eye goes to what would move.
                      color: unchanged ? AppColors.inkSoft : AppColors.ink,
                      height: 1.4,
                    ),
                    children: [
                      TextSpan(
                        text: '${_fieldLabel(l10n, entry.key)}  ',
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 0.8,
                          color: AppColors.inkSoft,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (currentText != null && !unchanged) ...[
                        TextSpan(
                          text: currentText,
                          style: TextStyle(
                            color: AppColors.inkSoft,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        TextSpan(
                          text: '  →  ',
                          style: TextStyle(color: AppColors.inkSoft),
                        ),
                      ],
                      TextSpan(text: proposed),
                    ],
                  ),
                ),
              );
            }),
          SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _decide(approve: false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.oxbloodDeep,
                    side: BorderSide(color: AppColors.line),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(l10n.revisionsReject),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: _busy ? null : () => _decide(approve: true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.moss,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: _busy
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.paper,
                          ),
                        )
                      : Text(l10n.revisionsApprove),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
