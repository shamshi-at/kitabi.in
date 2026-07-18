import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/haptics.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/typeset_cover.dart';
import '../../../data/db/database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../l10n/app_localizations.dart';
import '../providers/library_providers.dart';

/// Shelves are personal tags (CLAUDE.md rule 18). These two sheets are the
/// "easy flow" for moving books on and off them (owner request, 18 Jul 2026):
///
/// - [showShelfPickerSheet] — from a book: which shelves is this book on?
///   Every shelf listed, a tap toggles membership, and a new shelf can be made
///   without leaving the sheet. This replaces the old type-the-exact-name
///   dialog, which never showed the shelves you'd already made.
/// - [showAddBooksToShelfSheet] — from a shelf: which books belong here? Every
///   library book listed, a tap shelves or unshelves it — so an empty shelf you
///   just made isn't a dead end.

/// Grabber + title + subtitle header shared by both sheets.
Widget _sheetHeader(BuildContext context, String title, String subtitle) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Center(
        child: Container(
          width: 32,
          height: 4,
          margin: const EdgeInsets.only(top: 10, bottom: 12),
          decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(99)),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkSoft),
            ),
          ],
        ),
      ),
    ],
  );
}

/// Name-a-new-shelf dialog; returns the created tag's id (case-insensitively
/// reusing an existing shelf of the same name), or null if cancelled.
Future<String?> _promptNewShelf(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context)!;
  final controller = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.card,
      title: Text(l10n.libraryNewShelfTitle, style: const TextStyle(fontSize: 16)),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: l10n.libraryNewShelfHint),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.bookCancel)),
        TextButton(onPressed: () => Navigator.pop(ctx, controller.text), child: Text(l10n.bookSave)),
      ],
    ),
  );
  final cleaned = name?.trim();
  if (cleaned == null || cleaned.isEmpty) return null;
  final repo = await ref.read(tagsRepositoryProvider.future);
  final existing = (await ref.read(allTagsProvider.future))
      .where((t) => t.name.toLowerCase() == cleaned.toLowerCase());
  return existing.isNotEmpty ? existing.first.id : await repo.createTag(cleaned);
}

/// From a book — the shelves it's on, toggleable, with a door to a new one.
Future<void> showShelfPickerSheet(BuildContext context, {required String entryId}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ShelfPickerSheet(entryId: entryId),
  );
}

class _ShelfPickerSheet extends ConsumerWidget {
  const _ShelfPickerSheet({required this.entryId});

  final String entryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final shelves = ref.watch(personalShelvesProvider).valueOrNull ?? const <PersonalTag>[];
    final assignments = ref.watch(libraryTagsProvider(entryId)).valueOrNull ?? const <LibraryEntryTag>[];
    // tagId → the assignment row that puts this book on it (for unshelving).
    final memberAssignment = {for (final a in assignments) a.tagId: a.id};
    final sorted = [...shelves]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetHeader(context, l10n.shelfPickerTitle, l10n.shelfPickerHint),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 8),
                children: [
                  if (sorted.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                      child: Text(
                        l10n.shelfPickerEmpty,
                        style: TextStyle(color: AppColors.inkSoft, fontSize: 13),
                      ),
                    ),
                  for (final shelf in sorted)
                    _ShelfRow(
                      name: shelf.name,
                      selected: memberAssignment.containsKey(shelf.id),
                      onTap: () async {
                        Haptics.selection();
                        final repo = await ref.read(tagsRepositoryProvider.future);
                        final assignmentId = memberAssignment[shelf.id];
                        if (assignmentId != null) {
                          await repo.unassign(assignmentId);
                        } else {
                          await repo.assign(entryId, shelf.id);
                        }
                      },
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.add, color: AppColors.oxblood),
              title: Text(
                l10n.libraryNewShelf,
                style: TextStyle(color: AppColors.oxblood, fontWeight: FontWeight.w700),
              ),
              onTap: () async {
                final tagId = await _promptNewShelf(context, ref);
                if (tagId == null) return;
                final repo = await ref.read(tagsRepositoryProvider.future);
                await repo.assign(entryId, tagId);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ShelfRow extends StatelessWidget {
  const _ShelfRow({required this.name, required this.selected, required this.onTap});

  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Icon(
        selected ? Icons.check_circle : Icons.circle_outlined,
        color: selected ? AppColors.oxblood : AppColors.line,
      ),
      title: Text(
        name,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: AppColors.ink,
        ),
      ),
    );
  }
}

/// From a shelf — every library book, toggleable onto it. The way to fill a
/// shelf you just made without opening each book in turn.
Future<void> showAddBooksToShelfSheet(
  BuildContext context, {
  required String tagId,
  required String shelfName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _AddBooksToShelfSheet(tagId: tagId, shelfName: shelfName),
  );
}

class _AddBooksToShelfSheet extends ConsumerWidget {
  const _AddBooksToShelfSheet({required this.tagId, required this.shelfName});

  final String tagId;
  final String shelfName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final books = ref.watch(libraryHitsProvider).valueOrNull ?? const <LibraryHit>[];
    final assignments =
        ref.watch(allShelfAssignmentsProvider).valueOrNull ?? const <LibraryEntryTag>[];
    // For this shelf only: entryId → the assignment that shelves it (unshelve).
    final onShelf = {
      for (final a in assignments)
        if (a.tagId == tagId) a.libraryEntryId: a.id,
    };
    final sorted = [...books]
      ..sort((a, b) => a.book.title.toLowerCase().compareTo(b.book.title.toLowerCase()));

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetHeader(context, l10n.libraryAddToShelfTitle(shelfName), l10n.libraryAddBooksHint),
            const SizedBox(height: 8),
            if (sorted.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Text(
                  l10n.libraryAddBooksEmpty,
                  style: TextStyle(color: AppColors.inkSoft, fontSize: 13),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: sorted.length,
                  itemBuilder: (context, i) {
                    final hit = sorted[i];
                    final assignmentId = onShelf[hit.entry.id];
                    final selected = assignmentId != null;
                    return ListTile(
                      onTap: () async {
                        Haptics.selection();
                        final repo = await ref.read(tagsRepositoryProvider.future);
                        if (assignmentId != null) {
                          await repo.unassign(assignmentId);
                        } else {
                          await repo.assign(hit.entry.id, tagId);
                        }
                      },
                      leading: TypesetCover(
                        title: hit.book.title,
                        author: hit.book.authorNames,
                        coverUrl: hit.book.coverUrl,
                        width: 30,
                        height: 44,
                      ),
                      title: Text(
                        hit.book.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      subtitle: Text(
                        hit.book.authorNames,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppColors.inkSoft, fontSize: 11.5),
                      ),
                      trailing: Icon(
                        selected ? Icons.check_circle : Icons.add_circle_outline,
                        color: selected ? AppColors.moss : AppColors.oxblood,
                      ),
                    );
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.oxblood,
                    foregroundColor: AppColors.paper,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  child: Text(l10n.formEditorDone),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
