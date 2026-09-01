import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/async_states.dart';
import '../../../l10n/app_localizations.dart';
import '../providers/catalog_providers.dart';

/// The three things a kitabi.in link can name, in the URL's own words — the
/// same words `GET /public/id/{kind}/{key}` takes.
enum CatalogLinkKind { book, author, publisher }

final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// True when a link's key is already an id, so nothing has to be asked.
bool isCatalogId(String key) => _uuid.hasMatch(key);

/// Turns the key in a shared link into the id the screen behind it needs.
///
/// A link the reader taps names a row the way the *site* does: today that is a
/// slug (`kitabi.in/book/chemmeen`), and for every link shared before the web
/// platform existed it is a UUID (`kitabi.in/b/<uuid>`). Both are claimed by
/// the association files, so both arrive here; every catalog endpoint and every
/// screen takes a UUID. A UUID key is passed straight through — no request, no
/// loading frame — and anything else is resolved by the server, which is the
/// only thing that knows which row a slug names.
class CatalogLinkResolver extends ConsumerWidget {
  const CatalogLinkResolver({
    super.key,
    required this.kind,
    required this.linkKey,
    required this.builder,
  });

  final CatalogLinkKind kind;
  final String linkKey;
  final Widget Function(String id) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isCatalogId(linkKey)) return builder(linkKey);

    final args = (kind: kind.name, key: linkKey);
    return ref.watch(resolvedCatalogIdProvider(args)).when(
          data: builder,
          loading: () => Scaffold(
            backgroundColor: AppColors.paper,
            body: const SafeArea(child: ListSkeleton()),
          ),
          error: (err, _) => Scaffold(
            backgroundColor: AppColors.paper,
            body: SafeArea(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ErrorRetry(
                      onRetry: () => ref.invalidate(resolvedCatalogIdProvider(args)),
                    ),
                    // A shared link is often the app's entry point, and the
                    // engine *replaces* into that route — with nothing beneath
                    // it, Retry alone would be a dead end (CLAUDE.md, 14 Aug).
                    if (!context.canPop())
                      TextButton(
                        onPressed: () => context.go(Routes.home),
                        child: Text(AppLocalizations.of(context)!.commonGoHome),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
  }
}
