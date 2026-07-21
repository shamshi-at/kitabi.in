import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format_duration.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/db/database.dart';
import '../../../data/sync/sync_providers.dart';
import '../../../l10n/app_localizations.dart';
import '../providers/library_providers.dart';
import 'note_page.dart';

/// N4 — the book's reading journal.
///
/// Notes group under the sitting that produced them, so the session header
/// *is* the timestamp and nothing needs a date of its own. A note that came
/// from no sitting keeps its own group rather than being forced into a fake
/// one. Every note is a door: tapping opens the same editor it was written in.
///
/// Private is stated once, at the top, and never contradicted — unlike a
/// review there is no visibility toggle, because there is no other setting.
class NotesJournalScreen extends ConsumerWidget {
  const NotesJournalScreen({super.key, required this.entry});

  final LibraryEntry entry;

  static String _monthDay(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final local = d.toLocal();
    return '${local.day} ${months[local.month - 1]}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final notes = ref.watch(bookNotesProvider(entry.id)).valueOrNull ?? const <ReadingNote>[];
    final sessions =
        ref.watch(entrySessionsProvider(entry.id)).valueOrNull ?? const <ReadingSession>[];
    final sessionById = {for (final s in sessions) s.id: s};

    // Group by sitting, preserving the newest-first order the stream gives us.
    final grouped = <String?, List<ReadingNote>>{};
    for (final note in notes) {
      grouped.putIfAbsent(note.sessionId, () => []).add(note);
    }
    // Sittings first (newest note wins the ordering), unattached notes last —
    // they belong to the book, not to a stretch of reading.
    final keys = grouped.keys.toList()
      ..sort((a, b) {
        if (a == null) return 1;
        if (b == null) return -1;
        return 0;
      });

    final legacy = entry.notes;
    final hasLegacy = legacy != null && legacy.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        elevation: 0,
        title: Text(l10n.notesTitle, style: Theme.of(context).textTheme.titleLarge),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Row(
              children: [
                Icon(Icons.lock, size: 11, color: AppColors.inkSoft),
                const SizedBox(width: 4),
                Text(
                  l10n.notesAlwaysPrivate,
                  style: TextStyle(fontSize: 10.5, color: AppColors.inkSoft),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text(
              l10n.notesSummary(notes.length, grouped.keys.whereType<String>().length),
              style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft),
            ),
            const SizedBox(height: 14),
            if (notes.isEmpty && !hasLegacy)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Text(
                  l10n.notesEmpty,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: AppColors.inkSoft, height: 1.5),
                ),
              ),
            for (final key in keys) ...[
              _GroupHeader(
                label: key == null
                    ? l10n.notesNoSitting
                    : _sessionLabel(l10n, sessionById[key]),
              ),
              for (final note in grouped[key]!)
                _NoteTile(note: note, entryId: entry.id),
              const SizedBox(height: 10),
            ],
            // The blob that predates the journal — still the reader's, shown
            // as one undated note rather than quietly retired.
            if (hasLegacy) ...[
              _GroupHeader(label: l10n.notesNoSitting),
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: const Color(0xFFF6EEDC),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: const Color(0xFFE8DCC0)),
                ),
                child: Text(
                  legacy,
                  style: const TextStyle(fontSize: 13, height: 1.5),
                ),
              ),
            ],
            const SizedBox(height: 6),
            if (notes.isNotEmpty)
              Text(
                l10n.notesTapToEdit,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: AppColors.inkSoft),
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<bool>(
                  builder: (_) => NotePage(libraryEntryId: entry.id),
                ),
              ),
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.notesAdd),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.oxblood,
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _sessionLabel(AppLocalizations l10n, ReadingSession? s) {
    if (s == null) return l10n.notesNoSitting;
    return l10n.notesSessionHeader(
      _monthDay(s.endedAt),
      formatDuration(Duration(seconds: s.durationSeconds)),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 4),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: AppColors.inkSoft,
        ),
      ),
    );
  }
}

class _NoteTile extends StatelessWidget {
  const _NoteTile({required this.note, required this.entryId});

  final ReadingNote note;
  final String entryId;

  @override
  Widget build(BuildContext context) {
    final pages = note.pageStart == null
        ? null
        : (note.pageEnd == null
            ? 'p. ${note.pageStart}'
            : 'p. ${note.pageStart}–${note.pageEnd}');

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: const Color(0xFFF6EEDC),
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          // N5 — every note is a door back into the editor it was written in.
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
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: const Color(0xFFE8DCC0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(note.body, style: const TextStyle(fontSize: 13, height: 1.5)),
                if (pages != null) ...[
                  const SizedBox(height: 5),
                  Text(pages, style: TextStyle(fontSize: 10, color: AppColors.inkSoft)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Sittings for one book — the journal joins notes to them for its headers.
final entrySessionsProvider =
    StreamProvider.autoDispose.family<List<ReadingSession>, String>((ref, entryId) {
  return ref.watch(appDatabaseProvider).readingSessionsDao.watchForEntry(entryId);
});
