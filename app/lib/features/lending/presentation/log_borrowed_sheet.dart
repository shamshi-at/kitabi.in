import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/notification_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/typeset_cover.dart';
import '../../../data/db/catalog_cache.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../data/sync/sync_providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../catalog/providers/catalog_providers.dart';
import '../lending_format.dart';
import '../reminder.dart';
import 'sheet_fields.dart';

/// S8c — log a book you've borrowed. The other entry point to the ledger:
/// you add it yourself, no waiting on a friend to use the app. Same shape as
/// the lend flow — book, person, dates, note.
Future<void> showLogBorrowedSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.card,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _LogBorrowedSheet(),
  );
}

class _LogBorrowedSheet extends ConsumerStatefulWidget {
  const _LogBorrowedSheet();

  @override
  ConsumerState<_LogBorrowedSheet> createState() => _LogBorrowedSheetState();
}

class _LogBorrowedSheetState extends ConsumerState<_LogBorrowedSheet> {
  final _lender = TextEditingController();
  final _note = TextEditingController();
  final _searchController = TextEditingController();
  String _query = '';
  Map<String, dynamic>? _selected;
  DateTime _borrowedOn = DateTime.now();
  DateTime? _remindOn;
  bool _saving = false;

  @override
  void dispose() {
    _lender.dispose();
    _note.dispose();
    _searchController.dispose();
    super.dispose();
  }

  bool get _canSave => _selected != null && _lender.text.trim().isNotEmpty && !_saving;

  Future<void> _save() async {
    final work = _selected;
    if (work == null || _lender.text.trim().isEmpty) return;
    setState(() => _saving = true);
    final l10n = AppLocalizations.of(context)!;
    final lender = _lender.text.trim();
    final edition = work['edition'] as Map<String, dynamic>;
    await cacheBookForOffline(ref.read(appDatabaseProvider), work, edition);
    final repo = await ref.read(lendingRepositoryProvider.future);
    final id = await repo.logBorrowed(
      editionId: edition['id'] as String,
      lenderName: lender,
      borrowedDate: _borrowedOn,
      dueDate: _remindOn,
      note: _note.text,
    );
    final due = _remindOn;
    if (due != null) {
      await ref.read(notificationServiceProvider).scheduleReminder(
            id: reminderIdForRecord(id),
            title: l10n.reminderBorrowedTitle,
            body: l10n.reminderBorrowedBody(work['title'] as String? ?? '', lender),
            when: reminderTimeFor(due),
          );
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _pickBorrowedOn() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _borrowedOn,
      firstDate: now.subtract(Duration(days: 3650)),
      lastDate: now,
    );
    if (picked != null) setState(() => _borrowedOn = picked);
  }

  Future<void> _pickRemindOn() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _remindOn ?? now.add(Duration(days: 14)),
      firstDate: now,
      lastDate: now.add(Duration(days: 3650)),
    );
    if (picked != null) setState(() => _remindOn = picked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 18,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SheetGrabber(),
            Text(l10n.logBorrowedTitle, style: Theme.of(context).textTheme.titleLarge),
            SizedBox(height: 14),
            SheetLabel(l10n.logBorrowedBookLabel),
            if (_selected != null)
              _SelectedBook(work: _selected!, onClear: () => setState(() => _selected = null))
            else
              _BookSearch(
                controller: _searchController,
                query: _query,
                onQuery: (v) => setState(() => _query = v),
                onPick: (w) => setState(() {
                  _selected = w;
                  _query = '';
                  _searchController.clear();
                }),
              ),
            SizedBox(height: 12),
            SheetLabel(l10n.logBorrowedFromLabel),
            TextField(
              controller: _lender,
              onChanged: (_) => setState(() {}),
              decoration: sheetInputDecoration(l10n.logBorrowedFromHint),
            ),
            SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SheetDateField(
                    label: l10n.logBorrowedOnLabel,
                    value: fmtLendingDate(_borrowedOn),
                    onTap: _pickBorrowedOn,
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: SheetDateField(
                    label: l10n.logBorrowedRemindLabel,
                    value: _remindOn == null ? l10n.logBorrowedNoDate : fmtLendingDate(_remindOn!),
                    onTap: _pickRemindOn,
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            SheetLabel(l10n.logBorrowedNoteLabel),
            TextField(
              controller: _note,
              maxLines: 2,
              decoration: sheetInputDecoration(''),
            ),
            SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _canSave ? _save : null,
                child: _saving
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.paper),
                      )
                    : Text(l10n.logBorrowedSave),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookSearch extends ConsumerWidget {
  const _BookSearch({
    required this.controller,
    required this.query,
    required this.onQuery,
    required this.onPick,
  });

  final TextEditingController controller;
  final String query;
  final ValueChanged<String> onQuery;
  final ValueChanged<Map<String, dynamic>> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final results = ref.watch(catalogSearchProvider(query));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          onChanged: onQuery,
          decoration: sheetInputDecoration(l10n.logBorrowedSearchHint).copyWith(
            prefixIcon: Icon(Icons.search, size: 18, color: AppColors.inkSoft),
          ),
        ),
        if (query.trim().isNotEmpty)
          results.when(
            loading: () => Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )),
            ),
            error: (err, _) => Padding(padding: EdgeInsets.all(8), child: Text('$err')),
            data: (works) => Column(
              children: [
                for (final work in works.take(6))
                  ListTile(
                    contentPadding: EdgeInsets.symmetric(horizontal: 4),
                    dense: true,
                    leading: TypesetCover(
                      title: work['title'] as String? ?? '',
                      author: _firstAuthor(work),
                      coverUrl: (work['edition'] as Map?)?['cover_url'] as String?,
                      width: 26,
                      height: 38,
                    ),
                    title: Text(
                      work['title'] as String? ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    subtitle: _firstAuthor(work) == null
                        ? null
                        : Text(
                            _firstAuthor(work)!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: AppColors.inkSoft),
                          ),
                    onTap: (work['edition'] as Map?)?['id'] == null ? null : () => onPick(work),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  static String? _firstAuthor(Map<String, dynamic> work) {
    final authors = (work['authors'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return authors.isEmpty ? null : authors.first['name'] as String?;
  }
}

class _SelectedBook extends StatelessWidget {
  const _SelectedBook({required this.work, required this.onClear});

  final Map<String, dynamic> work;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final authors = (work['authors'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return Container(
      padding: EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.ink),
      ),
      child: Row(
        children: [
          TypesetCover(
            title: work['title'] as String? ?? '',
            author: authors.isEmpty ? null : authors.first['name'] as String?,
            coverUrl: (work['edition'] as Map?)?['cover_url'] as String?,
            width: 26,
            height: 38,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              work['title'] as String? ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 18, color: AppColors.inkSoft),
            onPressed: onClear,
          ),
        ],
      ),
    );
  }
}

