import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// One page of the cover viewer — an image URL plus its caption
/// ("Front cover" / "Back cover").
typedef CoverPage = ({String url, String label});

/// Full-screen, swipeable viewer for a book's cover photos — viewing is the
/// default gesture on the book page; *editing* stays on the small camera
/// badge. Night backdrop (photos read best on dark), pinch-zoom per page,
/// page dots when both sides exist.
Future<void> showCoverViewer(
  BuildContext context, {
  required List<CoverPage> pages,
  int initialIndex = 0,
}) {
  if (pages.isEmpty) return Future.value();
  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.transparent,
      pageBuilder: (_, _, _) =>
          _CoverViewer(pages: pages, initialIndex: initialIndex.clamp(0, pages.length - 1)),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

class _CoverViewer extends StatefulWidget {
  const _CoverViewer({required this.pages, required this.initialIndex});

  final List<CoverPage> pages;
  final int initialIndex;

  @override
  State<_CoverViewer> createState() => _CoverViewerState();
}

class _CoverViewerState extends State<_CoverViewer> {
  late final PageController _controller = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const paper = Color(0xFFF6F0E3); // always-light ink on the always-dark night scrim

    return Scaffold(
      backgroundColor: AppColors.night.withValues(alpha: 0.96),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.close, color: paper),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  ),
                  Expanded(
                    child: Text(
                      widget.pages[_index].label.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: paper.withValues(alpha: 0.85),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ),
                  // Balances the close button so the caption stays centered.
                  SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: widget.pages.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) => InteractiveViewer(
                  maxScale: 5,
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Image.network(
                        widget.pages[i].url,
                        fit: BoxFit.contain,
                        loadingBuilder: (context, child, progress) => progress == null
                            ? child
                            : Center(
                                child: CircularProgressIndicator(
                                  color: AppColors.gold,
                                  strokeWidth: 2,
                                ),
                              ),
                        errorBuilder: (context, _, _) => Icon(
                          Icons.broken_image_outlined,
                          color: paper.withValues(alpha: 0.4),
                          size: 48,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (widget.pages.length > 1)
              Padding(
                padding: EdgeInsets.only(top: 10, bottom: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < widget.pages.length; i++)
                      AnimatedContainer(
                        duration: Duration(milliseconds: 200),
                        margin: EdgeInsets.symmetric(horizontal: 3),
                        width: i == _index ? 16 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: i == _index ? AppColors.gold : paper.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                  ],
                ),
              )
            else
              SizedBox(height: 14),
          ],
        ),
      ),
    );
  }
}
