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

/// Another reader's page — avatar, name/@handle, a styled score/shelf-count
/// card, every connection action (Connect, Accept/Deny, Cancel, Resend,
/// Disconnect, Block/Unblock — whatever applies to your standing with them),
/// and two tabs: the lending ledger between you (shown first — it's the
/// thing you're most often here to check) and their shelf, if they've made
/// it public, with its own search. One screen, not a profile that pushes to
/// a second ledger screen and leaves connection actions stranded on a list
/// row elsewhere. Profiles are public by default; a reader who opted out
/// shows a quiet "keeps their profile private" state (the API 404s,
/// deliberately indistinguishable from not-found) — but the connection
/// actions still work even then, since accepting a request doesn't require
/// seeing their shelf.
class PublicProfileScreen extends ConsumerWidget {
  const PublicProfileScreen({super.key, required this.userId, this.name});

  final String userId;

  /// Display name carried from the tapped search/connection row, so the
  /// header renders instantly while the profile loads (and is all we have
  /// if the profile turns out to be private).
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
      ),
      body: _ProfileBody(userId: userId, fallbackName: name, profile: profile),
    );
  }
}

final _publicProfileProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, userId) {
  return ref.watch(apiClientProvider).getPublicProfile(userId);
});

final _publicLibraryProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, userId) {
  return ref.watch(apiClientProvider).getPublicLibrary(userId);
});

bool _isNotFound(Object err) => err is DioException && err.response?.statusCode == 404;

class _ProfileBody extends ConsumerStatefulWidget {
  const _ProfileBody({required this.userId, required this.fallbackName, required this.profile});

  final String userId;
  final String? fallbackName;
  final AsyncValue<Map<String, dynamic>> profile;

  @override
  ConsumerState<_ProfileBody> createState() => _ProfileBodyState();
}

/// Which tab is showing below the header. Ledger first — the loans between
/// you are why most visits happen — with the shelf a tap away.
enum _ProfileTab { ledger, shelf }

class _ProfileBodyState extends ConsumerState<_ProfileBody> {
  var _tab = _ProfileTab.ledger;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final profile = widget.profile;
    final isPrivate = profile.hasError && _isNotFound(profile.error!);

    if (profile.isLoading && !profile.hasValue) return ListSkeleton();
    if (profile.hasError && !isPrivate) {
      return ErrorRetry(onRetry: () => ref.invalidate(_publicProfileProvider(widget.userId)));
    }

    final data = profile.valueOrNull;
    final fullName = (data?['full_name'] as String?)?.trim();
    final username = data?['username'] as String?;
    final avatar = data?['avatar_url'] as String?;
    final display = (fullName?.isNotEmpty ?? false)
        ? fullName!
        : (username != null ? '@$username' : (widget.fallbackName ?? l10n.publicProfileTitle));
    final initial = display.replaceAll('@', '').isNotEmpty
        ? display.replaceAll('@', '')[0].toUpperCase()
        : '?';
    final libraryVisible = data?['library_visible'] == true;
    final connection = ref.watch(connectionsProvider).valueOrNull?.connectionFor(widget.userId);

    return ListView(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: AppColors.goldSoft,
              foregroundImage: avatar != null ? netImageProvider(avatar) : null,
              child: Text(
                initial,
                style: TextStyle(
                  color: Color(0xFF8F681E),
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                ),
              ),
            ),
            SizedBox(width: 16),
            Expanded(child: Text(display, style: Theme.of(context).textTheme.titleLarge)),
          ],
        ),
        if (data != null) ...[
          SizedBox(height: 16),
          _StatsCard(profile: data),
        ],
        SizedBox(height: 16),
        _ConnectionActions(userId: widget.userId, connection: connection),
        SizedBox(height: 18),
        _TabBar(selected: _tab, onChanged: (t) => setState(() => _tab = t)),
        SizedBox(height: 14),
        switch (_tab) {
          _ProfileTab.ledger => _LedgerTab(userId: widget.userId, name: display),
          _ProfileTab.shelf => isPrivate
              ? Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    l10n.publicProfilePrivate,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.inkSoft, fontSize: 12.5),
                  ),
                )
              : !libraryVisible
                  ? Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Text(
                        l10n.publicLibraryPrivate,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.inkSoft, fontSize: 12.5),
                      ),
                    )
                  : _PublicShelf(userId: widget.userId),
        },
      ],
    );
  }
}

/// The score/books/read counts, styled as their own card — a small icon
/// over a bold number over a caption, split by hairline dividers, instead
/// of three bare pills competing with the avatar for attention.
class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.profile});

  final Map<String, dynamic> profile;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: _StatCell(
              icon: Icons.military_tech_outlined,
              value: '${profile['score'] as int? ?? 0}',
              label: l10n.publicProfileScoreLabel,
              color: AppColors.gold,
            ),
          ),
          _StatDivider(),
          Expanded(
            child: _StatCell(
              icon: Icons.auto_stories_outlined,
              value: '${profile['books_tracked'] as int? ?? 0}',
              label: l10n.publicProfileBooksLabel,
              color: AppColors.oxblood,
            ),
          ),
          _StatDivider(),
          Expanded(
            child: _StatCell(
              icon: Icons.check_circle_outline,
              value: '${profile['books_finished'] as int? ?? 0}',
              label: l10n.homeShelfRead,
              color: AppColors.moss,
            ),
          ),
          _StatDivider(),
          Expanded(
            child: _StatCell(
              icon: Icons.people_alt_outlined,
              value: '${profile['connections_count'] as int? ?? 0}',
              label: l10n.publicProfileConnectionsLabel,
              color: AppColors.slate,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(width: 1, height: 34, color: AppColors.line);
}

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 16, color: color),
        SizedBox(height: 4),
        Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(fontSize: 10.5, color: AppColors.inkSoft, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

/// Icon-only segmented tabs (ledger / shelf), underlined when active.
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
        tab(_ProfileTab.ledger, Icons.swap_horiz_rounded, l10n.lendingLedgerTitle),
        tab(_ProfileTab.shelf, Icons.shelves, l10n.publicLibrarySection),
      ],
    );
  }
}

/// Every connection action, in one place: Connect for a stranger; Accept/
/// Deny/Block for an incoming request; a pending pill + Cancel for one you
/// sent; a status pill + Disconnect/Block once accepted; Resend for one they
/// declined; Unblock for one you blocked. Replaces the buttons that used to
/// live on the Connections list row.
class _ConnectionActions extends ConsumerStatefulWidget {
  const _ConnectionActions({required this.userId, required this.connection});

  final String userId;
  final Connection? connection;

  @override
  ConsumerState<_ConnectionActions> createState() => _ConnectionActionsState();
}

class _ConnectionActionsState extends ConsumerState<_ConnectionActions> {
  bool _busy = false;

  Future<void> _act(Future<void> Function(ApiClient api) action, {String? successMessage}) async {
    Haptics.selection();
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action(ref.read(apiClientProvider));
      ref.invalidate(connectionsProvider);
      if (successMessage != null && mounted) {
        messenger.showSnackBar(SnackBar(content: Text(successMessage)));
      }
    } catch (_) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        messenger.showSnackBar(SnackBar(content: Text(l10n.lendingReminderFailed)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _spinner() => SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.paper),
      );

  Widget _pill(String text, Color color, {IconData? icon}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: color), SizedBox(width: 5)],
          Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final c = widget.connection;

    if (c == null) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _busy
              ? null
              : () => _act(
                    (api) => api.requestConnection(widget.userId),
                    successMessage: l10n.publicProfileRequestSent,
                  ),
          icon: _busy ? _spinner() : Icon(Icons.person_add_alt, size: 16),
          label: Text(l10n.publicProfileConnect),
        ),
      );
    }

    if (c.status == 'pending' && c.role == 'addressee') {
      return Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: _busy ? null : () => _act((api) => api.acceptConnection(c.id)),
              child: Text(l10n.connectionsAccept),
            ),
          ),
          SizedBox(width: 8),
          _OutlinedAction(
            label: l10n.connectionsDeny,
            onTap: _busy ? null : () => _act((api) => api.declineConnection(c.id)),
          ),
          SizedBox(width: 4),
          _ActionKebab(items: [
            (l10n.connectionsBlock, () => _act((api) => api.blockConnection(c.id))),
          ]),
        ],
      );
    }

    if (c.status == 'pending' && c.role == 'requester') {
      return Row(
        children: [
          _pill(l10n.connectionsAwaitingReply, AppColors.gold),
          SizedBox(width: 8),
          _OutlinedAction(
            label: l10n.connectionsCancel,
            onTap: _busy ? null : () => _act((api) => api.declineConnection(c.id)),
          ),
        ],
      );
    }

    if (c.status == 'accepted') {
      return Row(
        children: [
          _pill(l10n.connectionsAcceptedSection, AppColors.moss, icon: Icons.check_circle),
          Spacer(),
          _OutlinedAction(
            label: l10n.connectionsDisconnect,
            onTap: _busy ? null : () => _act((api) => api.declineConnection(c.id)),
          ),
          SizedBox(width: 4),
          _ActionKebab(items: [
            (l10n.connectionsBlock, () => _act((api) => api.blockConnection(c.id))),
          ]),
        ],
      );
    }

    if (c.status == 'denied') {
      return Row(
        children: [
          Expanded(child: _pill(l10n.connectionsDeclinedYou, AppColors.inkSoft)),
          SizedBox(width: 8),
          ElevatedButton(
            onPressed: _busy
                ? null
                : () => _act((api) => api.requestConnection(widget.userId)),
            child: Text(l10n.connectionsResend),
          ),
        ],
      );
    }

    if (c.status == 'blocked') {
      return Row(
        children: [
          Expanded(child: _pill(l10n.connectionsBlockedSection, AppColors.inkSoft)),
          SizedBox(width: 8),
          ElevatedButton(
            onPressed: _busy ? null : () => _act((api) => api.unblockConnection(c.id)),
            child: Text(l10n.connectionsUnblock),
          ),
        ],
      );
    }

    return SizedBox.shrink();
  }
}

class _OutlinedAction extends StatelessWidget {
  const _OutlinedAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.inkSoft,
        side: BorderSide(color: AppColors.line),
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

class _ActionKebab extends StatelessWidget {
  const _ActionKebab({required this.items});

  final List<(String, VoidCallback)> items;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      icon: Icon(Icons.more_vert, size: 18, color: AppColors.inkSoft),
      padding: EdgeInsets.zero,
      splashRadius: 18,
      onSelected: (i) => items[i].$2(),
      itemBuilder: (_) => [
        for (var i = 0; i < items.length; i++)
          PopupMenuItem(value: i, height: 40, child: Text(items[i].$1)),
      ],
    );
  }
}

/// The public shelf — a search box over a covers-first grid, each cover a
/// door to the catalog book page. The search filters locally: the whole
/// shelf is already fetched in one call, so there's nothing to debounce.
class _PublicShelf extends ConsumerStatefulWidget {
  const _PublicShelf({required this.userId});

  final String userId;

  @override
  ConsumerState<_PublicShelf> createState() => _PublicShelfState();
}

class _PublicShelfState extends ConsumerState<_PublicShelf> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final shelf = ref.watch(_publicLibraryProvider(widget.userId));
    return shelf.when(
      loading: () => Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: CircularProgressIndicator(color: AppColors.gold)),
      ),
      error: (_, _) => ErrorRetry(
        onRetry: () => ref.invalidate(_publicLibraryProvider(widget.userId)),
      ),
      data: (items) {
        final q = _query.trim().toLowerCase();
        final filtered = q.isEmpty
            ? items
            : items
                .where((b) =>
                    ((b['title'] as String?) ?? '').toLowerCase().contains(q) ||
                    ((b['author_names'] as String?) ?? '').toLowerCase().contains(q))
                .toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: l10n.publicShelfSearchHint,
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 18, color: AppColors.inkSoft),
                filled: true,
                fillColor: AppColors.paper,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
            SizedBox(height: 12),
            if (filtered.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text(
                    l10n.publicShelfSearchEmpty,
                    style: TextStyle(color: AppColors.inkSoft, fontSize: 12.5),
                  ),
                ),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.52,
                ),
                itemCount: filtered.length,
                itemBuilder: (context, i) {
                  final b = filtered[i];
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
          ],
        );
      },
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
