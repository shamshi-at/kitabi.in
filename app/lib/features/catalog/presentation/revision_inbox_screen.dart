import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/haptics.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/async_states.dart';
import '../../../data/api/api_client.dart';
import '../../../l10n/app_localizations.dart';

/// Pending edits to books this reader contributed (wiki moderation, V1: the
/// contributor is the approver — proper moderation comes with the community
/// layer). Each card shows what would change; Approve applies it to the live
/// catalog, Reject discards it.
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

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(title: Text(l10n.revisionsTitle)),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(_pendingRevisionsProvider);
          ref.invalidate(_myClaimsProvider);
        },
        child: revisions.when(
          loading: () => ListSkeleton(),
          error: (err, _) => ErrorRetry(onRetry: () => ref.invalidate(_pendingRevisionsProvider)),
          data: (items) => (items.isEmpty && claimItems.isEmpty)
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
                    if (claimItems.isNotEmpty) ...[
                      _SectionHeader(label: l10n.claimsSectionTitle),
                      for (final claim in claimItems) ...[
                        _ClaimCard(claim: claim),
                        SizedBox(height: 10),
                      ],
                    ],
                    if (items.isNotEmpty) ...[
                      if (claimItems.isNotEmpty) SizedBox(height: 8),
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
    } catch (_) {
      if (mounted) setState(() => _busy = false);
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
      messenger.showSnackBar(SnackBar(content: Text('$err')));
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Human labels for the payload's field keys — reusing the form's own labels
  /// so the diff reads in the user's language.
  String _fieldLabel(AppLocalizations l10n, String key) => switch (key) {
        'title' => l10n.formFieldTitle,
        'description' => l10n.formFieldDescription,
        'language' => l10n.formFieldLanguage,
        'genre_names' => l10n.formFieldGenres,
        _ => key.replaceAll('_', ' '),
      };

  String _fieldValue(dynamic value) =>
      value is List ? value.join(', ') : (value?.toString() ?? '—');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final payload = (widget.revision['payload'] as Map).cast<String, dynamic>();
    final proposer = widget.revision['proposed_by_name'] as String?;

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
            Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: RichText(
                text: TextSpan(
                  style: TextStyle(fontSize: 12.5, color: AppColors.ink, height: 1.4),
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
                    TextSpan(text: _fieldValue(entry.value)),
                  ],
                ),
              ),
            ),
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
