import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/haptics.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/async_states.dart';
import '../../../core/widgets/typeset_cover.dart';
import '../../../data/db/database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../library/providers/library_providers.dart';
import '../lending_format.dart';
import '../reminder.dart';
import 'log_borrowed_sheet.dart';

/// S8 — the lending ledger, "the wedge styled as what it is: a ledger."
/// Both directions: **Lent out** (books with someone else) and **Borrowed**
/// (someone's book with me, self-logged). Records, not flags — borrower/lender,
/// dates, an optional due date, and a "Returned ✓" pill to close each one.
class LendingLedgerScreen extends ConsumerWidget {
  const LendingLedgerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final ledger = ref.watch(allLendingProvider);

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: ledger.when(
          loading: () => ListSkeleton(),
          error: (err, _) => ErrorRetry(onRetry: () => ref.invalidate(allLendingProvider)),
          data: (all) {
            final lent = all.where((r) => r.record.direction != 'borrowed').toList();
            final borrowed = all.where((r) => r.record.direction == 'borrowed').toList();

            return DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(l10n.lendingLedgerTitle,
                          style: Theme.of(context).textTheme.titleLarge),
                    ),
                  ),
                  TabBar(
                    labelColor: AppColors.oxblood,
                    unselectedLabelColor: AppColors.inkSoft,
                    indicatorColor: AppColors.oxblood,
                    labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                    tabs: [
                      Tab(text: l10n.lendingLentOutTab(lent.length)),
                      Tab(text: l10n.lendingBorrowedTab(borrowed.length)),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _LentView(records: lent),
                        _BorrowedView(records: borrowed),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LentView extends StatelessWidget {
  const _LentView({required this.records});

  final List<LendingWithBook> records;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final outNow = records.where((r) => r.record.returnedDate == null).toList();
    final returned = records.where((r) => r.record.returnedDate != null).toList();

    if (records.isEmpty) {
      return _EmptyState(text: l10n.lendingEmpty);
    }
    return ListView(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        if (outNow.isNotEmpty) ...[
          _SectionLabel(l10n.lendingOutNowSection),
          for (final item in outNow)
            _LoanCard(item: item, borrowed: false),
        ],
        if (returned.isNotEmpty) ...[
          SizedBox(height: 12),
          _SectionLabel(l10n.lendingReturnedSection),
          for (final item in returned) _ReturnedCard(item: item),
        ],
      ],
    );
  }
}

class _BorrowedView extends StatelessWidget {
  const _BorrowedView({required this.records});

  final List<LendingWithBook> records;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final withYou = records.where((r) => r.record.returnedDate == null).toList();
    final returned = records.where((r) => r.record.returnedDate != null).toList();

    return ListView(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        if (records.isEmpty)
          Padding(
            padding: EdgeInsets.only(top: 40, bottom: 20),
            child: Text(
              l10n.lendingBorrowedEmpty,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkSoft),
            ),
          )
        else ...[
          if (withYou.isNotEmpty) ...[
            _SectionLabel(l10n.lendingWithYouNowSection),
            for (final item in withYou) _LoanCard(item: item, borrowed: true),
          ],
          if (returned.isNotEmpty) ...[
            SizedBox(height: 12),
            _SectionLabel(l10n.lendingReturnedSection),
            for (final item in returned) _ReturnedCard(item: item),
          ],
        ],
        SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: () => showLogBorrowedSheet(context),
            child: Text(
              l10n.lendingLogBorrowed,
              style: TextStyle(color: AppColors.oxblood, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkSoft),
        ),
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
      padding: EdgeInsets.only(top: 8, bottom: 6),
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

class _Stamp extends StatelessWidget {
  const _Stamp({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

Widget _dueStamp(BuildContext context, DateTime? due) {
  final l10n = AppLocalizations.of(context)!;
  if (due == null) return _Stamp(label: l10n.lendingNoDueDate, color: AppColors.stampGrey);
  final days = DateUtils.dateOnly(due).difference(DateUtils.dateOnly(DateTime.now())).inDays;
  if (days < 0) return _Stamp(label: l10n.lendingOverdue, color: AppColors.oxblood);
  if (days <= 7) return _Stamp(label: l10n.lendingDueInDays(days), color: AppColors.gold);
  return _Stamp(label: l10n.lendingDueOn(fmtLendingDate(due)), color: AppColors.slate);
}

/// One "out now" / "with you now" card — the two sides share a shape, differing
/// only in the "to X" vs "from X" subtitle, the self-logged note, and the
/// close-out verb.
class _LoanCard extends ConsumerWidget {
  const _LoanCard({required this.item, required this.borrowed});

  final LendingWithBook item;
  final bool borrowed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final r = item.record;
    final book = item.book;

    return Container(
      margin: EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TypesetCover(
                title: book?.title ?? '…',
                author: book?.authorNames,
                coverUrl: book?.coverUrl,
                width: 34,
                height: 50,
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
                      borrowed
                          ? l10n.lendingFromPersonSince(r.borrowerName, fmtLendingDate(r.lentDate))
                          : l10n.lendingToPersonSince(r.borrowerName, fmtLendingDate(r.lentDate)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.inkSoft, fontSize: 11),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8),
              _dueStamp(context, r.dueDate),
            ],
          ),
          if (borrowed)
            Padding(
              padding: EdgeInsets.only(top: 6, left: 44),
              child: Text(
                l10n.lendingSelfLogged,
                style: TextStyle(color: AppColors.inkSoft, fontSize: 10, height: 1.2),
              ),
            ),
          SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () async {
                Haptics.success();
                final repo = await ref.read(lendingRepositoryProvider.future);
                await repo.markReturned(r.id, DateTime.now());
                await ref.read(notificationServiceProvider).cancel(reminderIdForRecord(r.id));
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.moss,
                side: BorderSide(color: AppColors.line),
                padding: EdgeInsets.symmetric(vertical: 8),
              ),
              child: Text(
                borrowed ? l10n.lendingReturnedIt : l10n.lendingMarkReturned,
                style: TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReturnedCard extends StatelessWidget {
  const _ReturnedCard({required this.item});

  final LendingWithBook item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final r = item.record;
    final book = item.book;

    return Opacity(
      opacity: 0.72,
      child: Container(
        margin: EdgeInsets.only(bottom: 6),
        padding: EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book?.title ?? '…',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                  Text(
                    l10n.lendingReturnedRange(
                      r.borrowerName,
                      fmtLendingDate(r.lentDate),
                      fmtLendingDate(r.returnedDate!),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.inkSoft, fontSize: 10.5),
                  ),
                ],
              ),
            ),
            SizedBox(width: 8),
            _Stamp(label: l10n.lendingReturnedStamp, color: AppColors.moss),
          ],
        ),
      ),
    );
  }
}
