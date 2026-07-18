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

class _AddBooksToShelfSheet extends ConsumerStatefulWidget {
  const _AddBooksToShelfSheet({required this.tagId, required this.shelfName});

  final String tagId;
  final String shelfName;

  @override
  ConsumerState<_AddBooksToShelfSheet> createState() => _AddBooksToShelfSheetState();
}

class _AddBooksToShelfSheetState extends ConsumerState<_AddBooksToShelfSheet> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final books = ref.watch(libraryHitsProvider).valueOrNull ?? const <LibraryHit>[];
    final assignments =
        ref.watch(allShelfAssignmentsProvider).valueOrNull ?? const <LibraryEntryTag>[];
    final shelfNames = {
      for (final t in ref.watch(personalShelvesProvider).valueOrNull ?? const <PersonalTag>[])
        t.id: t.name,
    };
    // For this shelf only: entryId → the assignment that shelves it (unshelve).
    final onShelf = {
      for (final a in assignments)
        if (a.tagId == widget.tagId) a.libraryEntryId: a.id,
    };
    final q = _query.trim().toLowerCase();
    final sorted = [...books]
      ..sort((a, b) => a.book.title.toLowerCase().compareTo(b.book.title.toLowerCase()));
    final filtered = sorted
        .where((h) =>
            q.isEmpty ||
            h.book.title.toLowerCase().contains(q) ||
            h.book.authorNames.toLowerCase().contains(q))
        .toList();

    // The shelves each entry sits on, named — so the picker shows "this book is
    // already on Malayalam classics" while you shelve it somewhere new.
    List<({String id, String name})> shelvesOf(String entryId) {
      final out = <({String id, String name})>[];
      for (final a in assignments) {
        if (a.libraryEntryId == entryId && shelfNames[a.tagId] != null) {
          out.add((id: a.tagId, name: shelfNames[a.tagId]!));
        }
      }
      out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return out;
    }

    return SafeArea(
      child: Padding(
        // Lift the sheet above the keyboard while searching.
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _sheetHeader(context, l10n.libraryAddToShelfTitle(widget.shelfName), l10n.libraryAddBooksHint),
              const SizedBox(height: 10),
              if (books.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: Text(
                    l10n.libraryAddBooksEmpty,
                    style: TextStyle(color: AppColors.inkSoft, fontSize: 13),
                  ),
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppColors.paper,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.search, size: 18, color: AppColors.inkSoft),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            decoration: InputDecoration(
                              hintText: l10n.libraryAddBooksSearchHint,
                              border: InputBorder.none,
                              isDense: true,
                            ),
                            onChanged: (v) => setState(() => _query = v),
                          ),
                        ),
                        if (_query.isNotEmpty)
                          GestureDetector(
                            onTap: () {
                              _controller.clear();
                              setState(() => _query = '');
                            },
                            child: Icon(Icons.close, size: 16, color: AppColors.inkSoft),
                          ),
                      ],
                    ),
                  ),
                ),
                if (filtered.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    child: Text(
                      l10n.libraryAddBooksNoMatches,
                      style: TextStyle(color: AppColors.inkSoft, fontSize: 13),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(bottom: 8),
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final hit = filtered[i];
                        final assignmentId = onShelf[hit.entry.id];
                        final selected = assignmentId != null;
                        final shelves = shelvesOf(hit.entry.id);
                        return ListTile(
                          onTap: () async {
                            Haptics.selection();
                            final repo = await ref.read(tagsRepositoryProvider.future);
                            if (assignmentId != null) {
                              await repo.unassign(assignmentId);
                            } else {
                              await repo.assign(hit.entry.id, widget.tagId);
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
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                hit.book.authorNames,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: AppColors.inkSoft, fontSize: 11.5),
                              ),
                              if (shelves.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Wrap(
                                    spacing: 4,
                                    runSpacing: 4,
                                    children: [
                                      for (final s in shelves)
                                        _MiniShelfChip(label: s.name, current: s.id == widget.tagId),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          trailing: Icon(
                            selected ? Icons.check_circle : Icons.add_circle_outline,
                            color: selected ? AppColors.moss : AppColors.oxblood,
                          ),
                        );
                      },
                    ),
                  ),
              ],
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
      ),
    );
  }
}

/// A tiny shelf label under a book in the add-books picker — gold for another
/// shelf the book sits on, oxblood for *this* shelf (already here).
class _MiniShelfChip extends StatelessWidget {
  const _MiniShelfChip({required this.label, required this.current});

  final String label;
  final bool current;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: current ? AppColors.oxblood : AppColors.goldSoft,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          color: current ? AppColors.paper : const Color(0xFF6B4E16),
        ),
      ),
    );
  }
}
