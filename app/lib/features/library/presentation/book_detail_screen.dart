import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/async_states.dart';
import '../../../core/widgets/typeset_cover.dart';
import '../../../data/db/catalog_cache.dart';
import '../../../data/db/database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../data/sync/sync_providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/notifications/notification_service.dart';
import '../../catalog/providers/catalog_providers.dart';
import '../../lending/presentation/lend_sheet.dart';
import '../../lending/reminder.dart';
import '../../share/presentation/share_book_sheet.dart';
import '../cover_upload.dart';
import '../reading_status.dart';
import '../providers/library_providers.dart';

/// S6 — book detail. Reached with a Work id (shared data: title, authors,
/// genres, aggregate rating) and an Edition id (this specific printing:
/// cover, pages, ISBN, publisher) — feature-map.md rule 17.
class BookDetailScreen extends ConsumerWidget {
  const BookDetailScreen({super.key, required this.workId, required this.editionId});

  final String workId;
  final String editionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final work = ref.watch(workProvider(workId));
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: work.when(
          loading: () => const ListSkeleton(),
          error: (err, _) => ErrorRetry(onRetry: () => ref.invalidate(workProvider(workId))),
          data: (body) => _BookDetailBody(work: body, editionId: editionId),
        ),
      ),
    );
  }
}

class _BookDetailBody extends ConsumerWidget {
  const _BookDetailBody({required this.work, required this.editionId});

  final Map<String, dynamic> work;
  final String editionId;

  Map<String, dynamic>? get _edition {
    final editions = (work['editions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return editions.where((e) => e['id'] == editionId).firstOrNull ?? editions.firstOrNull;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final edition = _edition;
    final entry = ref.watch(libraryEntryProvider(editionId));
    final authors = (work['authors'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final genres = (work['genres'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final publisher = edition?['publisher'] as Map<String, dynamic>?;

    return ListView(
      children: [
        Container(
          color: AppColors.paperDeep,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: AppColors.ink),
                onPressed: () => context.pop(),
                padding: EdgeInsets.zero,
              ),
              const SizedBox(width: 4),
              _CoverUploader(
                editionId: editionId,
                title: work['title'] as String,
                author: authors.isNotEmpty ? authors.first['name'] as String? : null,
                coverUrl: edition?['cover_url'] as String?,
                workId: work['id'] as String,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(work['title'] as String, style: Theme.of(context).textTheme.titleLarge),
                    if (authors.isNotEmpty)
                      GestureDetector(
                        onTap: () =>
                            context.push(Routes.authorBrowsePath(authors.first['id'] as String)),
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (authors.first['image_url'] != null) ...[
                                CircleAvatar(
                                  radius: 9,
                                  backgroundColor: AppColors.goldSoft,
                                  foregroundImage:
                                      NetworkImage(authors.first['image_url'] as String),
                                ),
                                const SizedBox(width: 6),
                              ],
                              Flexible(
                                child: Text(
                                  authors.first['name'] as String,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.oxblood,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (work['first_publish_year'] != null)
                      Text(
                        '${work['first_publish_year']}',
                        style: const TextStyle(color: AppColors.inkSoft, fontSize: 12),
                      ),
                    if (publisher != null)
                      GestureDetector(
                        onTap: () => context
                            .push(Routes.publisherBrowsePath(publisher['id'] as String)),
                        child: Text(
                          publisher['name'] as String,
                          style: const TextStyle(color: AppColors.oxblood, fontSize: 12),
                        ),
                      ),
                    if (edition?['page_count'] != null)
                      Text(
                        '${edition!['page_count']} pp',
                        style: const TextStyle(color: AppColors.inkSoft, fontSize: 12),
                      ),
                    if (edition?['language'] != null)
                      Text(
                        edition!['language'] as String,
                        style: const TextStyle(color: AppColors.inkSoft, fontSize: 12),
                      ),
                    const SizedBox(height: 4),
                    _RatingRow(workId: work['id'] as String),
                  ],
                ),
              ),
              _ShareButton(work: work, edition: edition),
              _LibraryEntryMenu(editionId: editionId),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(13, 10, 13, 24),
          child: entry.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(child: Text('$err')),
            data: (libraryEntry) => libraryEntry == null
                ? _AddToLibraryButton(work: work, edition: edition ?? {'id': editionId})
                : _OwnedBookSections(entry: libraryEntry, workId: work['id'] as String),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final genre in genres)
                      Chip(
                        label: Text(genre['name'] as String, style: const TextStyle(fontSize: 10)),
                        backgroundColor: AppColors.card,
                        side: const BorderSide(color: AppColors.line),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                  ],
                ),
              ),
              if (edition?['isbn'] != null)
                Text(
                  AppLocalizations.of(context)!.bookIsbnLabel(edition!['isbn'] as String),
                  style: const TextStyle(color: AppColors.inkSoft, fontSize: 10),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// The book-detail cover — tappable to upload your own photo (S7b "⇧ upload a
/// photo"), with a small camera badge. Uploads to Supabase Storage, points the
/// edition's cover_url at it, and refreshes.
class _CoverUploader extends ConsumerStatefulWidget {
  const _CoverUploader({
    required this.editionId,
    required this.title,
    required this.author,
    required this.coverUrl,
    required this.workId,
  });

  final String editionId;
  final String title;
  final String? author;
  final String? coverUrl;
  final String workId;

  @override
  ConsumerState<_CoverUploader> createState() => _CoverUploaderState();
}

class _CoverUploaderState extends ConsumerState<_CoverUploader> {
  bool _busy = false;

  Future<void> _upload() async {
    if (_busy) return;
    setState(() => _busy = true);
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final url = await pickAndUploadCover(ref, editionId: widget.editionId);
      if (url != null) {
        ref.invalidate(workProvider(widget.workId));
        ref.invalidate(cachedBookProvider(widget.editionId));
        messenger.showSnackBar(SnackBar(content: Text(l10n.coverUploaded)));
      }
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.coverUploadFailed)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _upload,
      child: Stack(
        children: [
          TypesetCover(
            title: widget.title,
            author: widget.author,
            coverUrl: widget.coverUrl,
            width: 58,
            height: 84,
          ),
          Positioned(
            right: 2,
            bottom: 2,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(color: AppColors.oxblood, shape: BoxShape.circle),
              child: _busy
                  ? const SizedBox(
                      width: 11,
                      height: 11,
                      child: CircularProgressIndicator(strokeWidth: 1.6, color: AppColors.paper),
                    )
                  : const Icon(Icons.photo_camera, size: 11, color: AppColors.paper),
            ),
          ),
        ],
      ),
    );
  }
}

class _RatingRow extends ConsumerWidget {
  const _RatingRow({required this.workId});

  final String workId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final rating = ref.watch(ratingProvider(workId));
    final value = rating.valueOrNull?.value ?? 0;

    return Row(
      children: [
        for (var i = 1; i <= 5; i++)
          GestureDetector(
            onTap: () async {
              Haptics.selection();
              final repo = await ref.read(ratingsRepositoryProvider.future);
              await repo.setRating(workId, i);
              ref.invalidate(ratingProvider(workId));
            },
            child: Icon(
              i <= value ? Icons.star : Icons.star_border,
              size: 16,
              color: AppColors.gold,
            ),
          ),
        const SizedBox(width: 6),
        Text(l10n.bookYourRating, style: const TextStyle(color: AppColors.inkSoft, fontSize: 10)),
      ],
    );
  }
}

class _ShareButton extends ConsumerWidget {
  const _ShareButton({required this.work, required this.edition});

  final Map<String, dynamic> work;
  final Map<String, dynamic>? edition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workId = work['id'] as String;
    return IconButton(
      icon: const Icon(Icons.ios_share, color: AppColors.oxblood),
      onPressed: () {
        final authors = (work['authors'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        final rating = ref.read(ratingProvider(workId)).valueOrNull;
        final review = ref.read(reviewProvider(workId)).valueOrNull;
        // Catalog average until the user has rated it (feature-map S6c).
        final catalog = (work['aggregate_rating'] as num?)?.toDouble() ??
            (work['translation_group_rating'] as num?)?.toDouble();
        showShareBookSheet(
          context,
          title: work['title'] as String,
          author: authors.isNotEmpty ? authors.first['name'] as String : '',
          coverUrl: edition?['cover_url'] as String?,
          blurb: work['description'] as String?,
          catalogRating: catalog,
          personalRating: rating?.value,
          personalReview: review?.body,
        );
      },
    );
  }
}

class _LibraryEntryMenu extends ConsumerWidget {
  const _LibraryEntryMenu({required this.editionId});

  final String editionId;

  Future<void> _confirmRemove(BuildContext context, WidgetRef ref, String entryId) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.bookRemoveFromLibrary),
        content: Text(l10n.bookRemoveConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.bookCancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              l10n.bookRemoveFromLibrary,
              style: const TextStyle(color: AppColors.oxbloodDeep),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final repo = await ref.read(libraryRepositoryProvider.future);
    await repo.remove(entryId);
    ref.invalidate(libraryEntryProvider(editionId));
    if (context.mounted) context.pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = ref.watch(libraryEntryProvider(editionId));
    final current = entry.valueOrNull;
    if (current == null) return const SizedBox.shrink();

    return Column(
      children: [
        IconButton(
          icon: Icon(
            current.isFavorite ? Icons.star : Icons.star_border,
            color: AppColors.gold,
          ),
          onPressed: () async {
            Haptics.selection();
            final repo = await ref.read(libraryRepositoryProvider.future);
            await repo.setFavorite(current.id, !current.isFavorite);
            ref.invalidate(libraryEntryProvider(editionId));
          },
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline, color: AppColors.inkSoft),
          onPressed: () => _confirmRemove(context, ref, current.id),
        ),
      ],
    );
  }
}

class _AddToLibraryButton extends ConsumerWidget {
  const _AddToLibraryButton({required this.work, required this.edition});

  final Map<String, dynamic> work;
  final Map<String, dynamic> edition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editionId = edition['id'] as String;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () async {
          // Cache before creating the entry so the grid/home cover tiles that
          // rebuild on the insert already find the catalog data (rule 2).
          await cacheBookForOffline(ref.read(appDatabaseProvider), work, edition);
          final repo = await ref.read(libraryRepositoryProvider.future);
          await repo.add(editionId: editionId);
          ref.invalidate(libraryEntryProvider(editionId));
        },
        child: Text(AppLocalizations.of(context)!.bookAddToLibrary),
      ),
    );
  }
}

class _OwnedBookSections extends ConsumerWidget {
  const _OwnedBookSections({required this.entry, required this.workId});

  final LibraryEntry entry;
  final String workId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 2),
          child: Text(
            AppLocalizations.of(context)!.bookYourCopy.toUpperCase(),
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: AppColors.inkSoft,
            ),
          ),
        ),
        _StatusPicker(entry: entry),
        const SizedBox(height: 8),
        _ProgressCard(entry: entry),
        const SizedBox(height: 8),
        _ReviewCard(entry: entry, workId: workId),
        const SizedBox(height: 8),
        _NotesCard(entry: entry),
        const SizedBox(height: 8),
        _LendingCard(entry: entry),
        const SizedBox(height: 8),
        _TagsSection(entry: entry),
      ],
    );
  }
}

class _StatusPicker extends ConsumerWidget {
  const _StatusPicker({required this.entry});

  final LibraryEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final status in readingStatuses)
          GestureDetector(
            onTap: () async {
              Haptics.selection();
              final repo = await ref.read(libraryRepositoryProvider.future);
              await repo.updateStatus(entry.id, status);
              if (status == 'read' && entry.finishDate == null) {
                await repo.updateProgress(entry.id, finishDate: DateTime.now());
              }
              ref.invalidate(libraryEntryProvider(entry.editionId));
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: entry.status == status ? AppColors.oxblood : AppColors.card,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: entry.status == status ? AppColors.oxblood : AppColors.line,
                ),
              ),
              child: Text(
                readingStatusLabel(status),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: entry.status == status ? AppColors.paper : AppColors.ink,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.color, this.borderColor, this.leftBorder});

  final Widget child;
  final Color? color;
  final Color? borderColor;
  final Color? leftBorder;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color ?? AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          top: BorderSide(color: borderColor ?? AppColors.line),
          bottom: BorderSide(color: borderColor ?? AppColors.line),
          right: BorderSide(color: borderColor ?? AppColors.line),
          left: BorderSide(color: leftBorder ?? borderColor ?? AppColors.line, width: leftBorder != null ? 3 : 1),
        ),
      ),
      child: child,
    );
  }
}

class _ProgressCard extends ConsumerWidget {
  const _ProgressCard({required this.entry});

  final LibraryEntry entry;

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: entry.currentPage?.toString() ?? '');
    final page = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.bookEditProgress),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: l10n.bookCurrentPage),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.bookCancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(controller.text)),
            child: Text(l10n.bookSave),
          ),
        ],
      ),
    );
    if (page == null) return;
    final repo = await ref.read(libraryRepositoryProvider.future);
    final needsStartDate = entry.startDate == null;
    await repo.updateProgress(
      entry.id,
      currentPage: page,
      startDate: needsStartDate ? DateTime.now() : null,
    );
    ref.invalidate(libraryEntryProvider(entry.editionId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return _Card(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.bookProgressLabel,
                  style: const TextStyle(fontSize: 9, color: AppColors.inkSoft, letterSpacing: 1),
                ),
                Text(
                  entry.currentPage != null
                      ? l10n.bookProgressValue(entry.currentPage!, entry.currentPage!)
                      : '—',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.bookStartedLabel,
                  style: const TextStyle(fontSize: 9, color: AppColors.inkSoft, letterSpacing: 1),
                ),
                Text(
                  entry.startDate != null
                      ? '${entry.startDate!.day}/${entry.startDate!.month}/${entry.startDate!.year}'
                      : l10n.bookNotStarted,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit, size: 16, color: AppColors.oxblood),
            onPressed: () => _edit(context, ref),
          ),
        ],
      ),
    );
  }
}

class _ReviewCard extends ConsumerWidget {
  const _ReviewCard({required this.entry, required this.workId});

  final LibraryEntry entry;
  final String workId;

  Future<void> _edit(BuildContext context, WidgetRef ref, Review? current) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: current?.body ?? '');
    var visible = current?.visible ?? false;
    final result = await showDialog<(String, bool)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(l10n.bookEditReview),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: controller, maxLines: 4, autofocus: true),
              Row(
                children: [
                  Expanded(child: Text(l10n.bookReviewVisibilityPublic)),
                  Switch(
                    value: visible,
                    onChanged: (v) => setState(() => visible = v),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.bookCancel)),
            TextButton(
              onPressed: () => Navigator.pop(ctx, (controller.text, visible)),
              child: Text(l10n.bookSave),
            ),
          ],
        ),
      ),
    );
    if (result == null || result.$1.trim().isEmpty) return;
    final repo = await ref.read(reviewsRepositoryProvider.future);
    await repo.upsert(workId, body: result.$1.trim(), visible: result.$2);
    ref.invalidate(reviewProvider(workId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final review = ref.watch(reviewProvider(workId));
    final current = review.valueOrNull;

    return GestureDetector(
      onTap: () => _edit(context, ref, current),
      child: _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.bookReviewLabel,
                    style: const TextStyle(fontSize: 9, color: AppColors.inkSoft, letterSpacing: 1),
                  ),
                ),
                if (current != null)
                  Text(
                    current.visible
                        ? l10n.bookReviewVisibilityPublic
                        : l10n.bookReviewVisibilityPrivate,
                    style: const TextStyle(fontSize: 9, color: AppColors.inkSoft),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              current?.body ?? l10n.bookReviewEmpty,
              style: TextStyle(
                fontStyle: FontStyle.italic,
                fontSize: 12.5,
                color: current != null ? AppColors.ink : AppColors.inkSoft,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotesCard extends ConsumerWidget {
  const _NotesCard({required this.entry});

  final LibraryEntry entry;

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: entry.notes ?? '');
    final notes = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.bookEditNotes),
        content: TextField(controller: controller, maxLines: 4, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.bookCancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(l10n.bookSave),
          ),
        ],
      ),
    );
    if (notes == null) return;
    final repo = await ref.read(libraryRepositoryProvider.future);
    await repo.updateNotes(entry.id, notes);
    ref.invalidate(libraryEntryProvider(entry.editionId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return GestureDetector(
      onTap: () => _edit(context, ref),
      child: _Card(
        color: const Color(0xFFF6EEDC),
        borderColor: const Color(0xFFE8DCC0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.lock, size: 10, color: AppColors.inkSoft),
                const SizedBox(width: 4),
                Text(
                  l10n.bookNotesLabel,
                  style: const TextStyle(fontSize: 9, color: AppColors.inkSoft, letterSpacing: 0.5),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              (entry.notes?.isNotEmpty ?? false) ? entry.notes! : l10n.bookNotesEmpty,
              style: TextStyle(
                fontSize: 12.5,
                color: (entry.notes?.isNotEmpty ?? false) ? AppColors.ink : AppColors.inkSoft,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TagsSection extends ConsumerWidget {
  const _TagsSection({required this.entry});

  final LibraryEntry entry;

  Future<void> _addTag(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.bookNewTagTitle),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(hintText: l10n.bookNewTagHint),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.bookCancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(l10n.bookSave),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;

    final repo = await ref.read(tagsRepositoryProvider.future);
    final allTags = await ref.read(allTagsProvider.future);
    final existing = allTags.where((t) => t.name.toLowerCase() == name.trim().toLowerCase());
    final tagId = existing.isNotEmpty ? existing.first.id : await repo.createTag(name.trim());
    await repo.assign(entry.id, tagId);
    ref.invalidate(libraryTagsProvider(entry.id));
    ref.invalidate(allTagsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final assignments = ref.watch(libraryTagsProvider(entry.id));
    final allTags = ref.watch(allTagsProvider);
    final tagNames = {for (final t in allTags.valueOrNull ?? <PersonalTag>[]) t.id: t.name};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.bookTagsLabel,
          style: const TextStyle(fontSize: 9, color: AppColors.inkSoft, letterSpacing: 1),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final assignment in assignments.valueOrNull ?? <LibraryEntryTag>[])
              if (tagNames[assignment.tagId] != null)
                Chip(
                  label: Text(tagNames[assignment.tagId]!, style: const TextStyle(fontSize: 11)),
                  onDeleted: () async {
                    final repo = await ref.read(tagsRepositoryProvider.future);
                    await repo.unassign(assignment.id);
                    ref.invalidate(libraryTagsProvider(entry.id));
                  },
                  backgroundColor: AppColors.goldSoft,
                  side: BorderSide.none,
                  visualDensity: VisualDensity.compact,
                ),
            ActionChip(
              label: Text(l10n.bookAddTag, style: const TextStyle(fontSize: 11)),
              onPressed: () => _addTag(context, ref),
              backgroundColor: AppColors.card,
              side: const BorderSide(color: AppColors.line),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ],
    );
  }
}

class _LendingCard extends ConsumerWidget {
  const _LendingCard({required this.entry});

  final LibraryEntry entry;

  Future<void> _lend(BuildContext context, WidgetRef ref) async {
    // The lend flow (S9) is a bottom sheet; pull the cached book so it can show
    // the cover + title the same way the ledger does.
    final book = await ref.read(cachedBookProvider(entry.editionId).future);
    if (!context.mounted) return;
    await showLendSheet(
      context,
      libraryEntryId: entry.id,
      bookTitle: book?.title ?? '',
      author: book?.authorNames,
      coverUrl: book?.coverUrl,
    );
    ref.invalidate(lendingRecordsProvider(entry.id));
  }

  Future<void> _markReturned(WidgetRef ref, String lendingId) async {
    Haptics.success();
    final repo = await ref.read(lendingRepositoryProvider.future);
    await repo.markReturned(lendingId, DateTime.now());
    await ref.read(notificationServiceProvider).cancel(reminderIdForRecord(lendingId));
    ref.invalidate(lendingRecordsProvider(entry.id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final records = ref.watch(lendingRecordsProvider(entry.id));
    final list = records.valueOrNull ?? [];
    final current = list.where((r) => r.returnedDate == null).firstOrNull;
    final pastCount = list.where((r) => r.returnedDate != null).length;

    return _Card(
      leftBorder: AppColors.gold,
      child: Row(
        children: [
          const Icon(Icons.swap_horiz, size: 16, color: AppColors.gold),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  current != null
                      ? l10n.bookLendingWithSomeone(current.borrowerName)
                      : l10n.bookLendingNotLentOut,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                ),
                if (pastCount > 0)
                  Text(
                    l10n.bookLendingPastCount(pastCount),
                    style: const TextStyle(color: AppColors.inkSoft, fontSize: 10),
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed:
                current != null ? () => _markReturned(ref, current.id) : () => _lend(context, ref),
            child: Text(
              current != null ? l10n.bookMarkReturnedAction : l10n.bookLendAction,
              style: const TextStyle(color: AppColors.oxblood, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
