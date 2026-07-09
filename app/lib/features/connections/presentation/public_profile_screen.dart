import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/haptics.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/async_states.dart';
import '../../../core/widgets/net_image.dart';
import '../../../core/widgets/status_pill.dart';
import '../../../core/widgets/typeset_cover.dart';
import '../../../data/api/api_client.dart';
import '../../../l10n/app_localizations.dart';
import '../../library/providers/library_providers.dart';
import '../connections_providers.dart';
import 'connection_loans_screen.dart';

/// Another reader's public face — avatar, name/@handle, contribution score
/// and shelf counts, a Connect action, and two tabs: their shelf (if made
/// public) and the lending ledger between you two. One screen instead of a
/// profile screen that pushes to a second ledger screen — Instagram-style
/// (username in the bar, name once in the body, icon tabs over a grid).
/// Profiles are public by default; a reader who opted out shows a quiet
/// "keeps their profile private" state (the API 404s, deliberately
/// indistinguishable from not-found).
class PublicProfileScreen extends ConsumerWidget {
  const PublicProfileScreen({super.key, required this.userId, this.name});

  final String userId;

  /// Display name carried from the tapped search/connection row, so the
  /// header renders instantly while the profile loads.
  final String? name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final profile = ref.watch(_publicProfileProvider(userId));
    final username = profile.valueOrNull?['username'] as String?;

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        // The full name renders once, in the body below — the bar carries
        // only the handle (or a generic fallback before it loads), so the
        // two never repeat the same string.
        title: Text(username != null ? '@$username' : (name ?? l10n.publicProfileTitle)),
        actions: [
          IconButton(
            icon: Icon(Icons.search, color: AppColors.oxblood),
            tooltip: l10n.searchTitle,
            onPressed: () => context.push(Routes.catalogSearch),
          ),
        ],
      ),
      body: profile.when(
        loading: () => ListSkeleton(),
        error: (err, _) => _isNotFound(err)
            ? Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_outline, size: 40, color: AppColors.inkSoft),
                      SizedBox(height: 12),
                      Text(
                        l10n.publicProfilePrivate,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.inkSoft, fontSize: 13.5),
                      ),
                    ],
                  ),
                ),
              )
            : ErrorRetry(onRetry: () => ref.invalidate(_publicProfileProvider(userId))),
        data: (p) => _ProfileBody(userId: userId, profile: p),
      ),
    );
  }

  static bool _isNotFound(Object err) =>
      err is DioException && err.response?.statusCode == 404;
}

final _publicProfileProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, userId) {
  return ref.watch(apiClientProvider).getPublicProfile(userId);
});

final _publicLibraryProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, userId) {
  return ref.watch(apiClientProvider).getPublicLibrary(userId);
});

class _ProfileBody extends ConsumerStatefulWidget {
  const _ProfileBody({required this.userId, required this.profile});

  final String userId;
  final Map<String, dynamic> profile;

  @override
  ConsumerState<_ProfileBody> createState() => _ProfileBodyState();
}

/// Which tab is showing below the header — Instagram's grid/tagged split,
/// here Shelf (their public library) vs. Ledger (the loans between you).
enum _ProfileTab { shelf, ledger }

class _ProfileBodyState extends ConsumerState<_ProfileBody> {
  var _tab = _ProfileTab.shelf;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final profile = widget.profile;
    final fullName = (profile['full_name'] as String?)?.trim();
    final username = profile['username'] as String?;
    final avatar = profile['avatar_url'] as String?;
    final display = (fullName?.isNotEmpty ?? false)
        ? fullName!
        : (username != null ? '@$username' : l10n.publicProfileTitle);
    final initial = display.replaceAll('@', '').isNotEmpty
        ? display.replaceAll('@', '')[0].toUpperCase()
        : '?';
    final libraryVisible = profile['library_visible'] == true;
    final connStatus =
        ref.watch(connectionsProvider).valueOrNull?.statusForUser(widget.userId);

    return ListView(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 36,
              backgroundColor: AppColors.goldSoft,
              foregroundImage: avatar != null ? netImageProvider(avatar) : null,
              child: Text(
                initial,
                style: TextStyle(
                  color: Color(0xFF8F681E),
                  fontWeight: FontWeight.w700,
                  fontSize: 22,
                ),
              ),
            ),
            SizedBox(width: 18),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _StatCell(
                    value: '${profile['score'] as int? ?? 0}',
                    label: l10n.publicProfileScoreLabel,
                  ),
                  _StatCell(
                    value: '${profile['books_tracked'] as int? ?? 0}',
                    label: l10n.publicProfileBooksLabel,
                  ),
                  _StatCell(
                    value: '${profile['books_finished'] as int? ?? 0}',
                    label: l10n.homeShelfRead,
                  ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: 14),
        Text(display, style: Theme.of(context).textTheme.titleLarge),
        SizedBox(height: 12),
        _ConnectRow(
          userId: widget.userId,
          status: connStatus,
          onViewLoans: () => setState(() => _tab = _ProfileTab.ledger),
        ),
        SizedBox(height: 18),
        _TabBar(selected: _tab, onChanged: (t) => setState(() => _tab = t)),
        SizedBox(height: 14),
        switch (_tab) {
          _ProfileTab.shelf => !libraryVisible
              ? Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    l10n.publicLibraryPrivate,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.inkSoft, fontSize: 12.5),
                  ),
                )
              : _PublicShelf(userId: widget.userId),
          _ProfileTab.ledger => _LedgerTab(userId: widget.userId, name: display),
        },
      ],
    );
  }
}

/// A single Instagram-style stat: bold count over a small caption.
class _StatCell extends StatelessWidget {
  const _StatCell({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: AppColors.inkSoft, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

/// Icon-only segmented tabs (grid / ledger), underlined when active — the
/// same idea as Instagram's grid-vs-tagged tab strip, just two tabs deep.
class _TabBar extends StatelessWidget {
  const _TabBar({required this.selected, required this.onChanged});

  final _ProfileTab selected;
  final ValueChanged<_ProfileTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    Widget tab(_ProfileTab t, IconData icon, String tooltip) {
      final active = t == selected;
      return Expanded(
        child: InkWell(
          onTap: () => onChanged(t),
          child: Container(
            padding: EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: active ? AppColors.oxblood : AppColors.line,
                  width: active ? 2 : 1,
                ),
              ),
            ),
            child: Tooltip(
              message: tooltip,
              child: Icon(icon, size: 20, color: active ? AppColors.oxblood : AppColors.inkSoft),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        tab(_ProfileTab.shelf, Icons.grid_view_rounded, l10n.publicLibrarySection),
        tab(_ProfileTab.ledger, Icons.swap_horiz_rounded, l10n.lendingLedgerTitle),
      ],
    );
  }
}

/// Connect / connection-state row: a Connect button for strangers, a quiet
/// state pill once a request is pending, or a "Connected" pill once
/// accepted — the ledger between you is a tab away, not a second screen.
class _ConnectRow extends ConsumerStatefulWidget {
  const _ConnectRow({required this.userId, required this.status, required this.onViewLoans});

  final String userId;
  final String? status;
  final VoidCallback onViewLoans;

  @override
  ConsumerState<_ConnectRow> createState() => _ConnectRowState();
}

class _ConnectRowState extends ConsumerState<_ConnectRow> {
  bool _busy = false;

  Future<void> _connect() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).requestConnection(widget.userId);
      ref.invalidate(connectionsProvider);
      Haptics.success();
      messenger.showSnackBar(SnackBar(content: Text(l10n.publicProfileRequestSent)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.lendingReminderFailed)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return switch (widget.status) {
      'accepted' => Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.moss.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, size: 13, color: AppColors.moss),
                SizedBox(width: 5),
                Text(
                  l10n.connectionsAcceptedSection,
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.moss),
                ),
              ],
            ),
          ),
        ),
      'pending_out' => Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              l10n.connectionsAwaitingReply,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.gold),
            ),
          ),
        ),
      _ => SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _busy ? null : _connect,
            icon: _busy
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child:
                        CircularProgressIndicator(strokeWidth: 2, color: AppColors.paper),
                  )
                : Icon(Icons.person_add_alt, size: 16),
            label: Text(l10n.publicProfileConnect),
          ),
        ),
    };
  }
}

/// The public shelf — covers-first grid, each a door to the catalog book page.
class _PublicShelf extends ConsumerWidget {
  const _PublicShelf({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shelf = ref.watch(_publicLibraryProvider(userId));
    return shelf.when(
      loading: () => Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: CircularProgressIndicator(color: AppColors.gold)),
      ),
      error: (_, _) => ErrorRetry(
        onRetry: () => ref.invalidate(_publicLibraryProvider(userId)),
      ),
      data: (items) => GridView.builder(
        shrinkWrap: true,
        physics: NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.52,
        ),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final b = items[i];
          return GestureDetector(
            onTap: () => context.push(
              Routes.bookDetailPath(b['work_id'] as String, b['edition_id'] as String),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: TypesetCover(
                    title: b['title'] as String? ?? '',
                    author: b['author_names'] as String?,
                    coverUrl: b['cover_url'] as String?,
                    width: double.infinity,
                    height: double.infinity,
                  ),
                ),
                SizedBox(height: 3),
                StatusPill(status: b['status'] as String? ?? 'pending'),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The lending ledger between you and them, inline — the same data
/// [ConnectionLoansScreen] shows for private contacts, but as a tab instead
/// of a second screen now that there's an account (and a profile) to attach
/// it to.
class _LedgerTab extends ConsumerWidget {
  const _LedgerTab({required this.userId, required this.name});

  final String userId;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final ledger = ref.watch(allLendingProvider);
    return ledger.when(
      loading: () => Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: CircularProgressIndicator(color: AppColors.gold)),
      ),
      error: (_, _) => ErrorRetry(onRetry: () => ref.invalidate(allLendingProvider)),
      data: (all) {
        final loans = loansForCounterparty(all, userId: userId, name: name);
        final lent = loans.where((r) => r.record.direction != 'borrowed').toList();
        final borrowed = loans.where((r) => r.record.direction == 'borrowed').toList();
        if (loans.isEmpty) {
          return Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Text(
              l10n.connectionLoansEmpty,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.inkSoft, fontSize: 12.5),
            ),
          );
        }
        return Column(
          children: [
            if (lent.isNotEmpty) ...[
              _LedgerSectionLabel(l10n.connectionLoansLent),
              for (final item in lent) LoanRow(item: item),
              SizedBox(height: 14),
            ],
            if (borrowed.isNotEmpty) ...[
              _LedgerSectionLabel(l10n.connectionLoansBorrowed),
              for (final item in borrowed) LoanRow(item: item),
            ],
          ],
        );
      },
    );
  }
}

class _LedgerSectionLabel extends StatelessWidget {
  const _LedgerSectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: AppColors.inkSoft,
          ),
        ),
      ),
    );
  }
}
