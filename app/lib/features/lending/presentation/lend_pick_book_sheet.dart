import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/typeset_cover.dart';
import '../../../l10n/app_localizations.dart';
import '../../catalog/providers/catalog_providers.dart';
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

class _LendPickBookSheet extends ConsumerStatefulWidget {
  const _LendPickBookSheet();

  @override
  ConsumerState<_LendPickBookSheet> createState() => _LendPickBookSheetState();
}

class _LendPickBookSheetState extends ConsumerState<_LendPickBookSheet> {
  // Filters the list live as the user types — a big library shouldn't mean
  // scrolling the whole shelf to lend one book.
  String _query = '';

  // Debounced 300ms — feeds the same books-only, transliteration-aware
  // catalog search global search uses (S4/S6), so "kayar" also matches a
  // "കയർ" title in your own library. Local substring match still runs on
  // every keystroke, so search never blocks offline.
  String _remoteQuery = '';
  Timer? _debounce;

  void _onChanged(String value) {
    setState(() => _query = value);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _remoteQuery = value);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final hits = ref.watch(libraryHitsProvider).valueOrNull ?? const [];
    // Entries already out (a lent, not-yet-returned record) can't be lent again.
    final lentOutEntryIds = (ref.watch(allLendingProvider).valueOrNull ?? [])
        .where((r) => r.record.direction != 'borrowed' && r.record.returnedDate == null)
        .map((r) => r.record.libraryEntryId)
        .toSet();
    final q = _query.trim().toLowerCase();
    final remoteQuery = _remoteQuery.trim();
    final crossScriptWorkIds = remoteQuery.length < 2
        ? const <String>{}
        : (ref.watch(catalogSearchProvider(remoteQuery)).valueOrNull ?? const [])
            .map((w) => w['id'] as String)
            .toSet();
    final lendable = hits
        .where((h) => h.entry.status != 'wishlist' && !lentOutEntryIds.contains(h.entry.id))
        .where((h) =>
            q.isEmpty ||
            h.book.title.toLowerCase().contains(q) ||
            h.book.authorNames.toLowerCase().contains(q) ||
            crossScriptWorkIds.contains(h.book.workId))
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
            SizedBox(height: 10),
            TextField(
              textCapitalization: TextCapitalization.sentences,
              autofocus: false,
              onChanged: _onChanged,
              decoration: InputDecoration(
                hintText: l10n.lendingPickSearchHint,
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 18, color: AppColors.inkSoft),
                filled: true,
                fillColor: AppColors.paper,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
            SizedBox(height: 10),
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
