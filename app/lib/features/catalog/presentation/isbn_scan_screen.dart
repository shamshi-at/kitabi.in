import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/typeset_cover.dart';
import '../../../data/api/api_client.dart';
import '../../../l10n/app_localizations.dart';

/// S7 — point the camera at a barcode; on a decode, resolve it through
/// `GET /catalog/isbn/{isbn}` (local match, else OpenLibrary, cached either
/// way) and show a confirm card before handing back to the caller.
class IsbnScanScreen extends ConsumerStatefulWidget {
  const IsbnScanScreen({super.key});

  @override
  ConsumerState<IsbnScanScreen> createState() => _IsbnScanScreenState();
}

class _IsbnScanScreenState extends ConsumerState<IsbnScanScreen> {
  final _controller = MobileScannerController(formats: [BarcodeFormat.ean13]);
  String? _detectedIsbn;
  Map<String, dynamic>? _work;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_loading || _detectedIsbn != null) return;
    final isbn = capture.barcodes.firstOrNull?.rawValue;
    if (isbn == null) return;

    setState(() {
      _detectedIsbn = isbn;
      _loading = true;
      _error = null;
    });
    await _controller.stop();

    try {
      final work = await ref.read(apiClientProvider).lookupIsbn(isbn);
      if (mounted) setState(() => _work = work);
    } catch (_) {
      if (mounted) setState(() => _error = AppLocalizations.of(context)!.scanNotFound);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _reset() {
    setState(() {
      _detectedIsbn = null;
      _work = null;
      _error = null;
    });
    _controller.start();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Theme(
      data: buildNightOverlayTheme(),
      child: Scaffold(
        backgroundColor: AppColors.night,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Color(0xFFEFE6C8)),
                      onPressed: () => context.pop(),
                    ),
                  ],
                ),
              ),
              Text(
                l10n.scanTitle,
                style: const TextStyle(
                  color: Color(0xFFEFE6C8),
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.scanSubtitle,
                style: const TextStyle(color: Color(0xFFA08D6E), fontSize: 12),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.gold, width: 1.5),
                      ),
                      child: MobileScanner(
                        controller: _controller,
                        onDetect: _onDetect,
                        errorBuilder: (context, error, child) => Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              '${error.errorDetails?.message ?? error.errorCode}',
                              style: const TextStyle(color: Color(0xFFEFE6C8)),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_detectedIsbn != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Text(
                    l10n.scanDetected(_detectedIsbn!),
                    style: const TextStyle(color: Color(0xFFCBB897), fontSize: 12),
                  ),
                ),
              const SizedBox(height: 10),
              if (_loading) const CircularProgressIndicator(color: AppColors.gold),
              if (_error != null) _ScanFooter(error: _error!, onReset: _reset, l10n: l10n),
              if (_work != null) _ConfirmCard(work: _work!, l10n: l10n),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFCBB897)),
                          foregroundColor: const Color(0xFFCBB897),
                        ),
                        onPressed: () {
                          context.pop();
                          context.push(Routes.catalogSearch);
                        },
                        child: Text(l10n.scanSearchInstead),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFCBB897)),
                          foregroundColor: const Color(0xFFCBB897),
                        ),
                        onPressed: () {
                          context.pop();
                          context.push(Routes.catalogAdd);
                        },
                        child: Text(l10n.scanAddManually),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanFooter extends StatelessWidget {
  const _ScanFooter({required this.error, required this.onReset, required this.l10n});

  final String error;
  final VoidCallback onReset;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: [
          Text(error, style: const TextStyle(color: Color(0xFFEFE6C8))),
          TextButton(
            onPressed: onReset,
            child: const Text('Scan again', style: TextStyle(color: AppColors.gold)),
          ),
        ],
      ),
    );
  }
}

class _ConfirmCard extends StatelessWidget {
  const _ConfirmCard({required this.work, required this.l10n});

  final Map<String, dynamic> work;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final editions = (work['editions'] as List?) ?? [];
    final edition = editions.isNotEmpty ? editions.first as Map<String, dynamic> : null;
    final authors = (work['authors'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final authorNames = authors.map((a) => a['name'] as String).join(', ');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF2A2115),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            TypesetCover(
              title: work['title'] as String,
              author: authors.isNotEmpty ? authors.first['name'] as String? : null,
              coverUrl: edition?['cover_url'] as String?,
              width: 26,
              height: 38,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    work['title'] as String,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFEFE6C8),
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  if (authorNames.isNotEmpty)
                    Text(
                      authorNames,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFFA08D6E), fontSize: 11),
                    ),
                ],
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: const Color(0xFF241811),
              ),
              onPressed: () => context.pop(),
              child: Text(l10n.scanConfirmAdd),
            ),
          ],
        ),
      ),
    );
  }
}
