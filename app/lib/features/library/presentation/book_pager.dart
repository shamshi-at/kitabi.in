import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:go_router/go_router.dart';

import '../../../core/haptics.dart';
import '../../../core/router/app_router.dart';
import '../book_browse_context.dart';
import 'book_detail_screen.dart';

/// How far past the first or last book the reader has to pull before the
/// page closes. Far enough that the ordinary end-of-list bounce doesn't do it
/// by accident, near enough that a deliberate "keep going" swipe does.
const double bookPagerCloseThreshold = 64;

/// Builds the book route: the plain [BookDetailScreen] when the page was
/// reached on its own, the swipeable [BookPager] when it was opened from a
/// list that says what its neighbours are. One function, used by the router
/// and by the tests, so the two can't disagree about what `extra` means.
Widget buildBookRoute(BuildContext context, GoRouterState state) {
  final workId = state.pathParameters['workId']!;
  final editionId = state.pathParameters['editionId']!;
  final extra = state.extra;
  if (extra is BookBrowseContext && extra.indexOf(editionId) >= 0) {
    return BookPager(browse: extra, editionId: editionId);
  }
  return BookDetailScreen(workId: workId, editionId: editionId);
}

/// The book page, swipeable through the shelf it was opened from.
///
/// A horizontal [PageView] over the shelf's books, starting on the one that
/// was tapped: swipe left for the next, right for the previous. Pulling past
/// either end — beyond the last book, or before the first — closes the page
/// and returns the reader to the shelf, the way a photo viewer does (owner
/// request, 6 Sep 2026).
///
/// Only the visible page is built, so a two-hundred-book library costs what
/// one book page costs; the neighbour is built as it slides in. The route's
/// URL stays on the book that opened the pager — the pages themselves render
/// from their own ids, and every exit (`_BackButton`, the pull past the end)
/// pops the one route this whole thing is.
class BookPager extends StatefulWidget {
  const BookPager({super.key, required this.browse, required this.editionId});

  final BookBrowseContext browse;

  /// The book that was tapped — where the pager opens.
  final String editionId;

  @override
  State<BookPager> createState() => _BookPagerState();
}

class _BookPagerState extends State<BookPager> {
  late final PageController _controller =
      PageController(initialPage: widget.browse.indexOf(widget.editionId));

  /// How far the finger has pulled past an end during the current drag. Two
  /// physics, two ways of reporting the same thing: clamping physics (Android)
  /// hold the position at the edge and report the excess as
  /// [OverscrollNotification]s, which accumulate here; bouncing physics (iOS)
  /// let the position itself travel past the extent, so the pull is read off
  /// the metrics directly. Either way only a *drag* counts — the snap-back
  /// animation after the finger lifts must never close anything.
  double _edgePull = 0;

  /// Latched once the pull has closed the page, so the frames the pop
  /// transition plays can't close it twice.
  bool _closing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _leave() {
    // Same rule as the page's own back button and every other exit in the app
    // (CLAUDE.md, 14 Aug 2026): pop when there's something beneath, else Home.
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.home);
    }
  }

  bool _onScroll(ScrollNotification n) {
    if (_closing) return false;
    if (n is ScrollEndNotification ||
        (n is UserScrollNotification && n.direction == ScrollDirection.idle)) {
      _edgePull = 0;
      return false;
    }
    final double pull;
    if (n is OverscrollNotification) {
      if (n.dragDetails == null) return false;
      _edgePull += n.overscroll;
      pull = _edgePull.abs();
    } else if (n is ScrollUpdateNotification) {
      if (n.dragDetails == null) return false;
      final m = n.metrics;
      pull = (m.minScrollExtent - m.pixels).clamp(0, double.infinity) +
          (m.pixels - m.maxScrollExtent).clamp(0, double.infinity);
    } else {
      return false;
    }
    if (pull >= bookPagerCloseThreshold) {
      _closing = true;
      Haptics.selection();
      _leave();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final books = widget.browse.books;
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: PageView.builder(
        controller: _controller,
        itemCount: books.length,
        itemBuilder: (context, i) => BookDetailScreen(
          key: ValueKey(books[i].editionId),
          workId: books[i].workId,
          editionId: books[i].editionId,
        ),
      ),
    );
  }
}
