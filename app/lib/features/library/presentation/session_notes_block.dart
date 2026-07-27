import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/section_label.dart';
import '../../../data/db/database.dart';
import '../../../l10n/app_localizations.dart';
import 'note_page.dart';

/// N3 — the notes this sitting already holds, plus "+ Add a closing thought…".
///
/// Shared by the quick-stop sheet and the timer's wax-seal face, so the most
/// deliberate stop path can't lose the closing-thought moment the sheet has
/// (CLAUDE.md's standing lesson: stop surfaces drift apart the moment they're
/// built separately). Notes were saved as they were written, so nothing here
/// is at stake — the block always offers the closing thought, even for a
/// sitting with no notes yet.
class SessionNotesBlock extends StatelessWidget {
  const SessionNotesBlock({
    super.key,
    required this.notes,
    required this.libraryEntryId,
    required this.sessionId,
    required this.bookTitle,
    this.currentPage,
  });

  final List<ReadingNote> notes;
  final String libraryEntryId;

  /// The sitting the closing thought belongs to.
  final String sessionId;
  final String? bookTitle;

  /// Resolved at tap time, because the page field it usually mirrors keeps
  /// changing under the sheet.
  final ValueGetter<int?>? currentPage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (notes.isNotEmpty)
          SectionLabel(
            l10n.notesSectionThisSitting(notes.length),
            padding: const EdgeInsets.only(bottom: 6),
          ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.slip,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: AppColors.slipLine),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (final note in notes)
                _SessionNoteRow(note: note, entryId: libraryEntryId),
              InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<bool>(
                    builder: (_) => NotePage(
                      libraryEntryId: libraryEntryId,
                      bookTitle: bookTitle,
                      sessionId: sessionId,
                      currentPage: currentPage?.call(),
                    ),
                  ),
                ),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                  decoration: BoxDecoration(
                    border: notes.isEmpty
                        ? null
                        : Border(top: BorderSide(color: AppColors.slipLine)),
                  ),
                  child: Text(
                    '+ ${l10n.notesClosingThought}',
                    style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One already-saved note — tappable, because the reader may want to finish a
/// thought they jotted mid-sentence.
class _SessionNoteRow extends StatelessWidget {
  const _SessionNoteRow({required this.note, required this.entryId});

  final ReadingNote note;
  final String entryId;

  @override
  Widget build(BuildContext context) {
    final pages = note.pageStart == null
        ? null
        : (note.pageEnd == null
            ? 'p. ${note.pageStart}'
            : 'p. ${note.pageStart}-${note.pageEnd}');
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<bool>(
          builder: (_) => NotePage(
            libraryEntryId: entryId,
            existing: note,
            startReadOnly: true,
          ),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                note.body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.5, height: 1.45),
              ),
            ),
            if (pages != null) ...[
              const SizedBox(width: 8),
              Text(pages, style: TextStyle(fontSize: 9.5, color: AppColors.inkSoft)),
            ],
          ],
        ),
      ),
    );
  }
}
