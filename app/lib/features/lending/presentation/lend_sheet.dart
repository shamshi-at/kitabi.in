import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/notification_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/typeset_cover.dart';
import '../../../data/api/api_client.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../connections/connections_providers.dart';
import '../lending_format.dart';
import '../reminder.dart';
import 'borrower_field.dart';
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
    shape: RoundedRectangleBorder(
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
  String? _borrowerUserId;
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
    final l10n = AppLocalizations.of(context)!;
    final borrower = _borrower.text.trim();
    final repo = await ref.read(lendingRepositoryProvider.future);
    final id = await repo.lendOut(
      widget.libraryEntryId,
      borrowerName: borrower,
      borrowerUserId: _borrowerUserId,
      lentDate: _lentOn,
      dueDate: _dueOn,
      note: _note.text,
    );
    // When lending to a Kitabi user, send (or auto-accept) a connection request
    // so the link becomes mutually confirmed. Best-effort: an offline failure
    // doesn't block the lend — the record keeps the borrower's id and the
    // request can go out again later.
    final borrowerUserId = _borrowerUserId;
    if (borrowerUserId != null) {
      try {
        await ref.read(apiClientProvider).requestConnection(borrowerUserId);
        ref.invalidate(connectionsProvider);
      } catch (_) {
        // ignore — link stays pending on the record
      }
    }
    final due = _dueOn;
    if (due != null) {
      await ref.read(notificationServiceProvider).scheduleReminder(
            id: reminderIdForRecord(id),
            title: l10n.reminderLentTitle,
            body: l10n.reminderLentBody(widget.bookTitle, borrower),
            when: reminderTimeFor(due),
          );
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _pickLentOn() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _lentOn,
      firstDate: now.subtract(Duration(days: 3650)),
      lastDate: now,
    );
    if (picked != null) setState(() => _lentOn = picked);
  }

  Future<void> _pickDueOn() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueOn ?? now.add(Duration(days: 14)),
      firstDate: now,
      lastDate: now.add(Duration(days: 3650)),
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
            SheetGrabber(),
            Row(
              children: [
                TypesetCover(
                  title: widget.bookTitle,
                  author: widget.author,
                  coverUrl: widget.coverUrl,
                  width: 30,
                  height: 44,
                ),
                SizedBox(width: 10),
                Expanded(
                  // "Lend" reads as a verb, italic and tinted, so the book's
                  // own name — which can run long — carries the visual
                  // weight; capped at 2 lines so an unusually long title
                  // never pushes the rest of the sheet around.
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${l10n.lendSheetTitlePrefix} ',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontStyle: FontStyle.italic,
                                fontWeight: FontWeight.w500,
                                color: AppColors.oxblood,
                              ),
                        ),
                        TextSpan(
                          text: widget.bookTitle,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            SizedBox(height: 14),
            BorrowerField(
              controller: _borrower,
              label: l10n.lendSheetToLabel,
              hint: l10n.lendSheetToHint,
              autofocus: true,
              onUserIdChanged: (id) => _borrowerUserId = id,
              onChanged: () => setState(() {}),
            ),
            SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SheetDateField(
                    label: l10n.lendSheetLentOnLabel,
                    value: fmtLendingDate(_lentOn),
                    onTap: _pickLentOn,
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: SheetDateField(
                    label: l10n.lendSheetDueLabel,
                    value: _dueOn == null ? l10n.logBorrowedNoDate : fmtLendingDate(_dueOn!),
                    onTap: _pickDueOn,
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
                    : Text(l10n.lendSheetSave),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
