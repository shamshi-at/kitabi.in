import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/typeset_cover.dart';
import '../../../data/db/database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../library/providers/library_providers.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _fmtDate(DateTime d) => '${d.day} ${_months[d.month - 1]}';

/// S8 — the lending ledger, "the wedge styled as what it is: a ledger."
/// Slice A ships the **Lent out** side (Out now / Returned); the Borrowed
/// tab + due-date reminders land in the next slices (docs/tasks.md Phase 4).
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
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text('$err')),
          data: (all) {
            final outNow = all.where((r) => r.record.returnedDate == null).toList();
            final returned = all.where((r) => r.record.returnedDate != null).toList();

            return CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back, color: AppColors.ink),
                          onPressed: () => context.pop(),
                          padding: EdgeInsets.zero,
                        ),
                        Text(l10n.lendingLedgerTitle,
                            style: Theme.of(context).textTheme.titleLarge),
                        const Spacer(),
                        Text(
                          l10n.lendingOutSubtitle(outNow.length),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppColors.inkSoft),
                        ),
                      ],
                    ),
                  ),
                ),
                if (all.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Text(
                          l10n.lendingEmpty,
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppColors.inkSoft),
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    sliver: SliverList.list(
                      children: [
                        if (outNow.isNotEmpty) ...[
                          _SectionLabel(l10n.lendingOutNowSection),
                          for (final item in outNow) _OutNowCard(item: item),
                        ],
                        if (returned.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _SectionLabel(l10n.lendingReturnedSection),
                          for (final item in returned) _ReturnedCard(item: item),
                        ],
                      ],
                    ),
                  ),
              ],
            );
          },
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
      padding: const EdgeInsets.only(top: 8, bottom: 6),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
  return _Stamp(label: l10n.lendingDueOn(_fmtDate(due)), color: AppColors.slate);
}

class _OutNowCard extends ConsumerWidget {
  const _OutNowCard({required this.item});

  final LendingWithBook item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final r = item.record;
    final book = item.book;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              TypesetCover(
                title: book?.title ?? '…',
                author: book?.authorNames,
                coverUrl: book?.coverUrl,
                width: 34,
                height: 50,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book?.title ?? '…',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    Text(
                      l10n.lendingToPersonSince(r.borrowerName, _fmtDate(r.lentDate)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.inkSoft, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _dueStamp(context, r.dueDate),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () async {
                final repo = await ref.read(lendingRepositoryProvider.future);
                await repo.markReturned(r.id, DateTime.now());
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.moss,
                side: const BorderSide(color: AppColors.line),
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
              child: Text(l10n.lendingMarkReturned, style: const TextStyle(fontSize: 12)),
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
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(9),
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
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                  Text(
                    l10n.lendingReturnedRange(
                      r.borrowerName,
                      _fmtDate(r.lentDate),
                      _fmtDate(r.returnedDate!),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.inkSoft, fontSize: 10.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _Stamp(label: l10n.lendingReturnedStamp, color: AppColors.moss),
          ],
        ),
      ),
    );
  }
}
