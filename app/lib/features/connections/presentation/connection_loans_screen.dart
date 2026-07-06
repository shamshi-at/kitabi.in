import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/async_states.dart';
import '../../../core/widgets/typeset_cover.dart';
import '../../../data/db/database.dart';
import '../../../l10n/app_localizations.dart';
import '../../lending/lending_format.dart';
import '../../library/providers/library_providers.dart';

/// The loans you have with one connection — books you've lent them and books
/// you've borrowed from them. Reached by tapping a connected reader in the
/// connections inbox.
class ConnectionLoansScreen extends ConsumerWidget {
  const ConnectionLoansScreen({super.key, required this.userId, required this.name});

  final String userId;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final ledger = ref.watch(allLendingProvider);

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        elevation: 0,
        foregroundColor: AppColors.ink,
        title: Text(name, style: Theme.of(context).textTheme.titleLarge),
      ),
      body: ledger.when(
        loading: () => ListSkeleton(),
        error: (err, _) => ErrorRetry(onRetry: () => ref.invalidate(allLendingProvider)),
        data: (all) {
          // borrower_user_id is the counterparty on both directions: the borrower
          // on a lent row, the lender on a borrowed row — so this catches both.
          final loans = all.where((r) => r.record.borrowerUserId == userId).toList();
          final lent = loans.where((r) => r.record.direction != 'borrowed').toList();
          final borrowed = loans.where((r) => r.record.direction == 'borrowed').toList();

          if (loans.isEmpty) {
            return EmptyState(icon: Icons.swap_horiz, title: name, body: l10n.connectionLoansEmpty);
          }
          return ListView(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              if (lent.isNotEmpty) ...[
                _SectionLabel(l10n.connectionLoansLent),
                for (final item in lent) _LoanRow(item: item),
                SizedBox(height: 14),
              ],
              if (borrowed.isNotEmpty) ...[
                _SectionLabel(l10n.connectionLoansBorrowed),
                for (final item in borrowed) _LoanRow(item: item),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: 8, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: AppColors.inkSoft,
        ),
      ),
    );
  }
}

class _LoanRow extends StatelessWidget {
  const _LoanRow({required this.item});

  final LendingWithBook item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final r = item.record;
    final book = item.book;
    final returned = r.returnedDate != null;

    return Container(
      margin: EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          TypesetCover(
            title: book?.title ?? '…',
            author: book?.authorNames,
            coverUrl: book?.coverUrl,
            width: 32,
            height: 47,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  book?.title ?? '…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                Text(
                  fmtLendingDate(r.lentDate),
                  style: TextStyle(color: AppColors.inkSoft, fontSize: 11),
                ),
              ],
            ),
          ),
          if (returned)
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.moss.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                l10n.connectionLoanReturned,
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.moss),
              ),
            ),
        ],
      ),
    );
  }
}
