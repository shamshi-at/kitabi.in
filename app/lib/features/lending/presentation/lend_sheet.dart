import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/typeset_cover.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../l10n/app_localizations.dart';
import '../lending_format.dart';
import 'sheet_fields.dart';

/// S9 — the lend flow. A bottom sheet on the book you already own: to whom,
/// lent-on, an optional due date (which drives the reminder), and a note.
/// The "this person is on Kitabi" match rides on the cross-user work (Slice D);
/// for now the counterparty is free text.
Future<void> showLendSheet(
  BuildContext context, {
  required String libraryEntryId,
  required String bookTitle,
  String? author,
  String? coverUrl,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _LendSheet(
      libraryEntryId: libraryEntryId,
      bookTitle: bookTitle,
      author: author,
      coverUrl: coverUrl,
    ),
  );
}

class _LendSheet extends ConsumerStatefulWidget {
  const _LendSheet({
    required this.libraryEntryId,
    required this.bookTitle,
    this.author,
    this.coverUrl,
  });

  final String libraryEntryId;
  final String bookTitle;
  final String? author;
  final String? coverUrl;

  @override
  ConsumerState<_LendSheet> createState() => _LendSheetState();
}

class _LendSheetState extends ConsumerState<_LendSheet> {
  final _borrower = TextEditingController();
  final _note = TextEditingController();
  DateTime _lentOn = DateTime.now();
  DateTime? _dueOn;
  bool _saving = false;

  @override
  void dispose() {
    _borrower.dispose();
    _note.dispose();
    super.dispose();
  }

  bool get _canSave => _borrower.text.trim().isNotEmpty && !_saving;

  Future<void> _save() async {
    if (_borrower.text.trim().isEmpty) return;
    setState(() => _saving = true);
    final repo = await ref.read(lendingRepositoryProvider.future);
    await repo.lendOut(
      widget.libraryEntryId,
      borrowerName: _borrower.text.trim(),
      lentDate: _lentOn,
      dueDate: _dueOn,
      note: _note.text,
    );
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _pickLentOn() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _lentOn,
      firstDate: now.subtract(const Duration(days: 3650)),
      lastDate: now,
    );
    if (picked != null) setState(() => _lentOn = picked);
  }

  Future<void> _pickDueOn() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueOn ?? now.add(const Duration(days: 14)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 3650)),
    );
    if (picked != null) setState(() => _dueOn = picked);
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
            const SheetGrabber(),
            Row(
              children: [
                TypesetCover(
                  title: widget.bookTitle,
                  author: widget.author,
                  coverUrl: widget.coverUrl,
                  width: 30,
                  height: 44,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(l10n.lendSheetTitle, style: Theme.of(context).textTheme.titleLarge),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SheetLabel(l10n.lendSheetToLabel),
            TextField(
              controller: _borrower,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: sheetInputDecoration(l10n.lendSheetToHint),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SheetDateField(
                    label: l10n.lendSheetLentOnLabel,
                    value: fmtLendingDate(_lentOn),
                    onTap: _pickLentOn,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SheetDateField(
                    label: l10n.lendSheetDueLabel,
                    value: _dueOn == null ? l10n.logBorrowedNoDate : fmtLendingDate(_dueOn!),
                    onTap: _pickDueOn,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SheetLabel(l10n.logBorrowedNoteLabel),
            TextField(
              controller: _note,
              maxLines: 2,
              decoration: sheetInputDecoration(''),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _canSave ? _save : null,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.paper),
                      )
                    : Text(l10n.lendSheetSave),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
