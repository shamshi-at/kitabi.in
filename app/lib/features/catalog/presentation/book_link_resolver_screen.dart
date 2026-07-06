import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/async_states.dart';
import '../../library/presentation/book_detail_screen.dart';
import '../providers/catalog_providers.dart';

/// Resolves the short shareable/deep-link path `/b/:workId` (the same URL the
/// landing page uses) to the full book detail screen. A share link only carries
/// the Work id, so we fetch the Work and open its representative (first)
/// edition — matching how search/browse tiles open a book.
class BookLinkResolverScreen extends ConsumerWidget {
  const BookLinkResolverScreen({super.key, required this.workId});

  final String workId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final work = ref.watch(workProvider(workId));
    return work.when(
      // BookDetailScreen is itself a full Scaffold — only the loading/error
      // placeholders need their own.
      data: (body) {
        final editions = (body['editions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        final editionId = editions.isNotEmpty ? editions.first['id'] as String : workId;
        return BookDetailScreen(workId: workId, editionId: editionId);
      },
      loading: () => Scaffold(
        backgroundColor: AppColors.paper,
        body: SafeArea(child: ListSkeleton()),
      ),
      error: (err, _) => Scaffold(
        backgroundColor: AppColors.paper,
        body: SafeArea(
          child: ErrorRetry(onRetry: () => ref.invalidate(workProvider(workId))),
        ),
      ),
    );
  }
}
