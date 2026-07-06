import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/typeset_cover.dart';
import '../../../l10n/app_localizations.dart';
import '../../library/providers/library_providers.dart';
import 'lend_sheet.dart';

/// Pick which owned book to lend, then hand off to [showLendSheet]. Lets the
/// user start a lend straight from the ledger (S8) instead of only from a book's
/// own page. Wishlist entries (not owned) and books already out are excluded.
Future<void> showLendPickBookSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.card,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _LendPickBookSheet(),
  );
}

class _LendPickBookSheet extends ConsumerWidget {
  const _LendPickBookSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final hits = ref.watch(libraryHitsProvider).valueOrNull ?? const [];
    // Entries already out (a lent, not-yet-returned record) can't be lent again.
    final lentOutEntryIds = (ref.watch(allLendingProvider).valueOrNull ?? [])
        .where((r) => r.record.direction != 'borrowed' && r.record.returnedDate == null)
        .map((r) => r.record.libraryEntryId)
        .toSet();
    final lendable = hits
        .where((h) => h.entry.status != 'wishlist' && !lentOutEntryIds.contains(h.entry.id))
        .toList();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 12,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 32,
                height: 4,
                margin: EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppColors.line,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            Text(l10n.lendingPickTitle, style: Theme.of(context).textTheme.titleLarge),
            SizedBox(height: 12),
            if (lendable.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(
                  child: Text(
                    l10n.lendingPickEmpty,
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.inkSoft),
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: lendable.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: AppColors.line),
                  itemBuilder: (context, i) {
                    final hit = lendable[i];
                    final book = hit.book;
                    return ListTile(
                      contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      leading: TypesetCover(
                        title: book.title,
                        author: book.authorNames,
                        coverUrl: book.coverUrl,
                        width: 32,
                        height: 47,
                      ),
                      title: Text(
                        book.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      subtitle: Text(
                        book.authorNames,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppColors.inkSoft, fontSize: 12),
                      ),
                      onTap: () {
                        Navigator.of(context).pop();
                        showLendSheet(
                          context,
                          libraryEntryId: hit.entry.id,
                          bookTitle: book.title,
                          author: book.authorNames,
                          coverUrl: book.coverUrl,
                        );
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
