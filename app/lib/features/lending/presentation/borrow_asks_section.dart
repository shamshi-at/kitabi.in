import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/haptics.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/typeset_cover.dart';
import '../../../data/api/api_client.dart';
import '../../../data/sync/sync_providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../circle/circle_models.dart';
import '../../circle/circle_providers.dart';
import 'lend_sheet.dart';

/// Asks to borrow, at the top of the Lending tab — where a borrow-ask
/// notification lands and where the ask stays until it's answered. Before this
/// an ask was a push and nothing else: tapping it led nowhere that mentioned
/// it, and the app kept no trace of it (owner report, 14 Oct 2026).
///
/// "Lend it" opens the ordinary lend sheet already pointed at the asker; the
/// server closes the ask when that loan syncs (as it does for a loan made from
/// the book page). "Not now" declines, silently. Asks the reader *sent* show
/// as one quiet line each, so they know it went.
class BorrowAsksSection extends ConsumerStatefulWidget {
  const BorrowAsksSection({super.key});

  @override
  ConsumerState<BorrowAsksSection> createState() => _BorrowAsksSectionState();
}

class _BorrowAsksSectionState extends ConsumerState<BorrowAsksSection> {
  // Answered here and not yet re-read from the server — hidden at once rather
  // than waiting for the loan to sync and the list to refetch.
  final _answered = <String>{};

  Future<void> _lend(BorrowAsk ask) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final entry = await ref
        .read(appDatabaseProvider)
        .libraryEntriesDao
        .getByEditionId(ask.editionId);
    if (!mounted) return;
    if (entry == null) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.borrowAskNotOnShelf)));
      return;
    }
    final saved = await showLendSheet(
      context,
      libraryEntryId: entry.id,
      bookTitle: ask.title,
      author: ask.author,
      coverUrl: ask.coverUrl,
      initialBorrower: LendBorrower(
        userId: ask.personId,
        name: ask.personName,
        username: ask.personUsername,
      ),
    );
    if (saved == true && mounted) setState(() => _answered.add(ask.id));
  }

  Future<void> _decline(BorrowAsk ask) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    Haptics.selection();
    setState(() => _answered.add(ask.id));
    try {
      await ref.read(apiClientProvider).circleDeclineBorrowAsk(ask.id);
      ref.invalidate(borrowAsksProvider);
    } catch (_) {
      if (!mounted) return;
      setState(() => _answered.remove(ask.id));
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.borrowAskUpdateFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final asks = ref.watch(borrowAsksProvider).valueOrNull;
    if (asks == null) return const SizedBox.shrink();
    final incoming = asks.incoming
        .where((a) => !_answered.contains(a.id))
        .toList();
    final outgoing = asks.outgoing.take(3).toList();
    if (incoming.isEmpty && outgoing.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (incoming.isNotEmpty) ...[
            Text(
              l10n.borrowAsksLabel.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.3,
                color: AppColors.goldInk,
              ),
            ),
            const SizedBox(height: 6),
            for (final ask in incoming)
              _IncomingCard(
                ask: ask,
                onLend: () => _lend(ask),
                onDecline: () => _decline(ask),
              ),
          ],
          for (final ask in outgoing)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Icon(Icons.schedule, size: 14, color: AppColors.inkSoft),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l10n.borrowAskOutgoing(ask.personShortName, ask.title),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
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

class _IncomingCard extends StatelessWidget {
  const _IncomingCard({
    required this.ask,
    required this.onLend,
    required this.onDecline,
  });

  final BorrowAsk ask;
  final VoidCallback onLend;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final asked = ask.createdAt;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TypesetCover(
                title: ask.title,
                author: ask.author,
                coverUrl: ask.coverUrl,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.borrowAskIncoming(ask.personShortName, ask.title),
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                    if (asked != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          l10n.borrowAskAskedOn(
                            DateFormat.MMMd().format(asked.toLocal()),
                          ),
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.inkSoft,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: onDecline,
                child: Text(l10n.borrowAskNotNow),
              ),
              const SizedBox(width: 4),
              FilledButton(
                onPressed: onLend,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.oxblood,
                ),
                child: Text(l10n.borrowAskLendIt),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
