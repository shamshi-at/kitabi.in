import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/status_pill.dart';
import '../../../core/widgets/typeset_cover.dart';
import '../../../data/api/api_client.dart';
import '../../../data/db/catalog_cache.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../data/sync/sync_providers.dart';
import '../../../l10n/app_localizations.dart';

/// S2 — import from a Goodreads export or generic book CSV. The API parses +
/// matches rows to the catalog; matched rows become library entries locally
/// (offline-first), carrying status, rating, and review.
class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  final _csvController = TextEditingController();
  bool _busy = false;
  Map<String, dynamic>? _preview;

  @override
  void dispose() {
    _csvController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _matchedRows => ((_preview?['rows'] as List?) ?? [])
      .cast<Map<String, dynamic>>()
      .where((r) => r['match'] != null)
      .toList();

  Future<void> _pickFile() async {
    const group = XTypeGroup(
      label: 'CSV',
      extensions: ['csv'],
      mimeTypes: ['text/csv', 'text/comma-separated-values'],
    );
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return;
    _csvController.text = await file.readAsString();
    await _parse();
  }

  Future<void> _parse() async {
    final csv = _csvController.text.trim();
    if (csv.isEmpty) return;
    setState(() => _busy = true);
    try {
      final preview = await ref.read(apiClientProvider).importPreview(csv);
      if (mounted) setState(() => _preview = preview);
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$err')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    setState(() => _busy = true);
    final db = ref.read(appDatabaseProvider);
    final libraryRepo = await ref.read(libraryRepositoryProvider.future);
    final ratingsRepo = await ref.read(ratingsRepositoryProvider.future);
    final reviewsRepo = await ref.read(reviewsRepositoryProvider.future);
    var imported = 0;

    for (final row in _matchedRows) {
      final work = row['match'] as Map<String, dynamic>;
      final edition = work['edition'] as Map<String, dynamic>?;
      if (edition == null) continue;
      final editionId = edition['id'] as String;
      if (await libraryRepo.getByEditionId(editionId) != null) continue; // already owned

      await cacheBookForOffline(db, work, edition);
      await libraryRepo.add(editionId: editionId, status: row['status'] as String? ?? 'pending');
      final workId = work['id'] as String;
      if (row['rating'] != null) await ratingsRepo.setRating(workId, row['rating'] as int);
      final review = row['review'] as String?;
      if (review != null && review.trim().isNotEmpty) {
        await reviewsRepo.upsert(workId, body: review.trim(), visible: false);
      }
      imported++;
    }

    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.importDone(imported))));
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final preview = _preview;

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        elevation: 0,
        foregroundColor: AppColors.ink,
        title: Text(l10n.importTitle, style: Theme.of(context).textTheme.titleLarge),
      ),
      body: SafeArea(
        top: false,
        child: preview == null ? _picker(l10n) : _previewList(l10n, preview),
      ),
    );
  }

  Widget _picker(AppLocalizations l10n) {
    return ListView(
      padding: EdgeInsets.all(20),
      children: [
        Text(
          l10n.importSubtitle,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft),
        ),
        SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _busy ? null : _pickFile,
            icon: Icon(Icons.file_open_outlined, size: 18),
            label: Text(l10n.importPickFile),
          ),
        ),
        SizedBox(height: 14),
        Text(
          l10n.importPasteHint,
          style: TextStyle(fontSize: 11, color: AppColors.inkSoft),
        ),
        SizedBox(height: 12),
        TextField(
          textCapitalization: TextCapitalization.words,
          controller: _csvController,
          maxLines: 10,
          minLines: 6,
          style: TextStyle(fontSize: 12, fontFamily: 'monospace'),
          decoration: InputDecoration(
            hintText: 'Title,Author,ISBN,My Rating,Exclusive Shelf…',
            hintStyle: TextStyle(fontSize: 11, color: AppColors.inkSoft),
            filled: true,
            fillColor: AppColors.card,
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
        SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _busy ? null : _parse,
            icon: _busy
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.paper),
                  )
                : Icon(Icons.search, size: 18),
            label: Text(l10n.importPreviewButton),
          ),
        ),
      ],
    );
  }

  Widget _previewList(AppLocalizations l10n, Map<String, dynamic> preview) {
    final rows = (preview['rows'] as List).cast<Map<String, dynamic>>();
    final matched = preview['matched'] as int;
    final total = preview['total'] as int;

    if (total == 0) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(l10n.importEmpty,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft)),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.importMatched(matched, total),
                  style: TextStyle(fontWeight: FontWeight.w600)),
              Text(l10n.importUnmatchedNote,
                  style: TextStyle(fontSize: 11, color: AppColors.inkSoft)),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
            itemCount: rows.length,
            itemBuilder: (context, i) => _ImportRowTile(row: rows[i]),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_busy || matched == 0) ? null : _import,
              child: _busy
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.paper),
                    )
                  : Text(l10n.importAdd(matched)),
            ),
          ),
        ),
      ],
    );
  }
}

class _ImportRowTile extends StatelessWidget {
  const _ImportRowTile({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final match = row['match'] as Map<String, dynamic>?;
    final matched = match != null;
    final title = row['title'] as String? ?? '';
    final author = row['author'] as String?;
    final coverUrl = (match?['edition'] as Map?)?['cover_url'] as String?;
    final status = row['status'] as String?;

    return Opacity(
      opacity: matched ? 1 : 0.45,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            TypesetCover(title: title, author: author, coverUrl: coverUrl, width: 28, height: 40),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
                  if (author != null)
                    Text(author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppColors.inkSoft, fontSize: 11)),
                ],
              ),
            ),
            if (matched && status != null) ...[
              SizedBox(width: 8),
              StatusPill(status: status),
            ] else if (!matched)
              Icon(Icons.help_outline, size: 16, color: AppColors.inkSoft),
          ],
        ),
      ),
    );
  }
}
