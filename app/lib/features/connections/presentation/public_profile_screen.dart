import 'dart:async';

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
import '../../catalog/providers/catalog_providers.dart';
import '../../library/providers/library_providers.dart';
import '../connections_providers.dart';
import 'connection_loans_screen.dart';

/// Another reader's page — a "bookplate": a gold-framed card holding the
/// avatar, name, connection state (a corner stamp, or an action button), and
/// the Score/Books/Read/Links counts, over two tabs — the lending ledger
/// between you (shown first, it's why most visits happen) and their public
/// shelf. The @handle lives once, in the app bar; the plate carries the real
/// name. Destructive/rare actions (Disconnect, Block, Cancel request) hide in
/// the app bar's ⋮ menu so the plate stays about the person, not the buttons.
/// Profiles are public by default; a reader who opted out shows a quiet
/// "keeps their profile private" state (the API 404s, deliberately
/// indistinguishable from not-found) — the connection actions still work
/// even then, since acting on a request never required seeing their shelf.
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
    final fullName = (profile.valueOrNull?['full_name'] as String?)?.trim();
    // The @handle appears exactly once — here in the bar. The plate shows the
    // real name. Falls back to the name (then a generic title) when no handle.
    final barTitle = username != null
        ? '@$username'
        : (fullName?.isNotEmpty ?? false ? fullName! : (name ?? l10n.publicProfileTitle));

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: Text(barTitle),
        actions: [_ProfileMenu(userId: userId)],
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

/// Fire-and-forget connection mutation shared by the plate's action buttons
/// and the app-bar ⋮ menu — runs the call, refreshes the connections graph,
/// and surfaces success/failure. Callers that show a spinner track their own
/// busy flag around it.
Future<void> _runConnectionAction(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function(ApiClient api) action, {
  String? successMessage,
}) async {
  Haptics.selection();
  final messenger = ScaffoldMessenger.of(context);
  final l10n = AppLocalizations.of(context)!;
  try {
    await action(ref.read(apiClientProvider));
    ref.invalidate(connectionsProvider);
    if (successMessage != null) {
      messenger.showSnackBar(SnackBar(content: Text(successMessage)));
    }
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.lendingReminderFailed)));
  }
}

/// App-bar overflow menu — only the destructive/rare actions for the current
/// standing (Disconnect + Block once connected, Cancel request on one you
/// sent, Block on an incoming request). Renders nothing when there's no such
/// action, so a stranger's bar stays clean.
class _ProfileMenu extends ConsumerWidget {
  const _ProfileMenu({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final c = ref.watch(connectionsProvider).valueOrNull?.connectionFor(userId);
    if (c == null) return const SizedBox.shrink();

    // (label, isDanger, action)
    final items = <(String, bool, Future<void> Function(ApiClient))>[];
    if (c.status == 'accepted') {
      items.add((l10n.connectionsDisconnect, false, (api) => api.declineConnection(c.id)));
      items.add((l10n.connectionsBlock, true, (api) => api.blockConnection(c.id)));
    } else if (c.status == 'pending' && c.role == 'requester') {
      items.add((l10n.connectionsCancel, false, (api) => api.declineConnection(c.id)));
    } else if (c.status == 'pending' && c.role == 'addressee') {
      items.add((l10n.connectionsBlock, true, (api) => api.blockConnection(c.id)));
    }
    if (items.isEmpty) return const SizedBox.shrink();

    return PopupMenuButton<int>(
      icon: Icon(Icons.more_vert, color: AppColors.inkSoft),
      onSelected: (i) => _runConnectionAction(context, ref, items[i].$3),
      itemBuilder: (_) => [
        for (var i = 0; i < items.length; i++)
          PopupMenuItem(
            value: i,
            height: 44,
            child: Text(
              items[i].$1,
              style: TextStyle(color: items[i].$2 ? AppColors.oxblood : AppColors.ink),
            ),
          ),
      ],
    );
  }
}

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
    final libraryVisible = data?['library_visible'] == true;
    final connection = ref.watch(connectionsProvider).valueOrNull?.connectionFor(widget.userId);

    // Tab counts — loans with this person, and shelf size (once fetched).
    final allLoans = ref.watch(allLendingProvider).valueOrNull;
    final loanCount = allLoans == null
        ? null
        : loansForCounterparty(allLoans, userId: widget.userId, name: display).length;
    final shelfCount = (isPrivate || !libraryVisible)
        ? null
        : ref.watch(_publicLibraryProvider(widget.userId)).valueOrNull?.length;

    return ListView(
      padding: EdgeInsets.fromLTRB(20, 14, 20, 24),
      children: [
        _Bookplate(
          userId: widget.userId,
          display: display,
          avatar: avatar,
          data: data,
          connection: connection,
        ),
        SizedBox(height: 16),
        _TabBar(
          selected: _tab,
          ledgerCount: loanCount,
          shelfCount: shelfCount,
          onChanged: (t) => setState(() => _tab = t),
        ),
        SizedBox(height: 14),
        switch (_tab) {
          _ProfileTab.ledger => _LedgerTab(userId: widget.userId, name: display),
          _ProfileTab.shelf => isPrivate
              ? _MutedNote(l10n.publicProfilePrivate)
              : !libraryVisible
                  ? _MutedNote(l10n.publicLibraryPrivate)
                  : _PublicShelf(userId: widget.userId),
        },
      ],
    );
  }
}

class _MutedNote extends StatelessWidget {
  const _MutedNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 20),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.inkSoft, fontSize: 12.5),
      ),
    );
  }
}

/// The bookplate — a gold-inset-framed card: avatar (gold ring) + "Ex Libris"
/// eyebrow + name, the connection action slot (Connect / Accept+Deny / Resend
/// / Unblock, or nothing once the state is carried by a corner stamp), and the
/// stat row. A moss/gold corner stamp marks a connected or pending standing.
class _Bookplate extends StatelessWidget {
  const _Bookplate({
    required this.userId,
    required this.display,
    required this.avatar,
    required this.data,
    required this.connection,
  });

  final String userId;
  final String display;
  final String? avatar;
  final Map<String, dynamic>? data;
  final Connection? connection;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final initial = display.replaceAll('@', '').isNotEmpty
        ? display.replaceAll('@', '')[0].toUpperCase()
        : '?';

    // Corner stamp: connected (moss) or awaiting-reply (gold). Other states
    // put their control in the action slot instead, so there's no stamp.
    final ({String text, Color color})? stamp = switch (connection) {
      Connection(status: 'accepted') => (text: l10n.connectionsAcceptedSection, color: AppColors.moss),
      Connection(status: 'pending', role: 'requester') =>
        (text: l10n.connectionsAwaitingReply, color: AppColors.gold),
      _ => null,
    };

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Stack(
        children: [
          // Gold hairline inset frame (echoes the Kitabi logo tile).
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                margin: EdgeInsets.all(5),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.goldSoft),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  // Reserve the top-right corner for the stamp so a long name
                  // never slides under it.
                  padding: EdgeInsets.only(right: stamp != null ? 92 : 0, bottom: 12),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: AppColors.card,
                        child: CircleAvatar(
                          radius: 23,
                          backgroundColor: AppColors.goldSoft,
                          foregroundImage: avatar != null ? netImageProvider(avatar!) : null,
                          child: Text(
                            initial,
                            style: TextStyle(
                              color: Color(0xFF8F681E),
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.publicProfileExLibris.toUpperCase(),
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 2.4,
                                color: AppColors.gold,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              display,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                _ConnectionActionSlot(userId: userId, connection: connection),
                if (data != null) _StatsRow(profile: data!),
              ],
            ),
          ),
          if (stamp != null)
            Positioned(
              top: 12,
              right: 12,
              child: Transform.rotate(
                angle: 0.09,
                child: _Stamp(text: stamp.text, color: stamp.color),
              ),
            ),
        ],
      ),
    );
  }
}

/// The little inked stamp on the plate's corner — moss for connected, gold for
/// a request awaiting reply.
class _Stamp extends StatelessWidget {
  const _Stamp({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check, size: 11, color: color),
          SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// The one action slot inside the plate — a full-width Connect for a stranger,
/// Accept/Deny for an incoming request, Resend for a declined one, Unblock for
/// a blocked one. Accepted and awaiting-reply states show nothing here (their
/// standing is the corner stamp; their actions live in the ⋮ menu).
class _ConnectionActionSlot extends ConsumerStatefulWidget {
  const _ConnectionActionSlot({required this.userId, required this.connection});

  final String userId;
  final Connection? connection;

  @override
  ConsumerState<_ConnectionActionSlot> createState() => _ConnectionActionSlotState();
}

class _ConnectionActionSlotState extends ConsumerState<_ConnectionActionSlot> {
  bool _busy = false;

  Future<void> _run(Future<void> Function(ApiClient api) action, {String? successMessage}) async {
    setState(() => _busy = true);
    await _runConnectionAction(context, ref, action, successMessage: successMessage);
    if (mounted) setState(() => _busy = false);
  }

  Widget _spinner() => SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.paper),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final c = widget.connection;

    Widget? slot;
    if (c == null) {
      slot = SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _busy
              ? null
              : () => _run(
                    (api) => api.requestConnection(widget.userId),
                    successMessage: l10n.publicProfileRequestSent,
                  ),
          icon: _busy ? _spinner() : Icon(Icons.person_add_alt, size: 16),
          label: Text(l10n.publicProfileConnect),
        ),
      );
    } else if (c.status == 'pending' && c.role == 'addressee') {
      slot = Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: _busy ? null : () => _run((api) => api.acceptConnection(c.id)),
              child: Text(l10n.connectionsAccept),
            ),
          ),
          SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              onPressed: _busy ? null : () => _run((api) => api.declineConnection(c.id)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.inkSoft,
                side: BorderSide(color: AppColors.line),
              ),
              child: Text(l10n.connectionsDeny),
            ),
          ),
        ],
      );
    } else if (c.status == 'denied') {
      slot = SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _busy ? null : () => _run((api) => api.requestConnection(widget.userId)),
          icon: _busy ? _spinner() : Icon(Icons.refresh, size: 16),
          label: Text(l10n.connectionsResend),
        ),
      );
    } else if (c.status == 'blocked') {
      slot = SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: _busy ? null : () => _run((api) => api.unblockConnection(c.id)),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.inkSoft,
            side: BorderSide(color: AppColors.line),
          ),
          child: Text(l10n.connectionsUnblock),
        ),
      );
    }

    if (slot == null) return const SizedBox.shrink();
    return Padding(padding: EdgeInsets.only(bottom: 14), child: slot);
  }
}

/// The Score/Books/Read/Links counts as a ruled row inside the plate — big
/// serif figures over small-caps labels, hairline dividers between.
class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.profile});

  final Map<String, dynamic> profile;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.line)),
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
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 10),
      child: Column(
        children: [
          Icon(icon, size: 15, color: color),
          SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          SizedBox(height: 1),
          Text(
            label,
            style: TextStyle(fontSize: 9.5, color: AppColors.inkSoft, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// Segmented Ledger / Shelf tabs with live counts — the same control the
/// lending ledger uses, so the app keeps one segmented pattern.
class _TabBar extends StatelessWidget {
  const _TabBar({
    required this.selected,
    required this.ledgerCount,
    required this.shelfCount,
    required this.onChanged,
  });

  final _ProfileTab selected;
  final int? ledgerCount;
  final int? shelfCount;
  final ValueChanged<_ProfileTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.paperDeep,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          _SegTab(
            label: l10n.publicProfileTabLedger,
            count: ledgerCount,
            active: selected == _ProfileTab.ledger,
            onTap: () => onChanged(_ProfileTab.ledger),
          ),
          _SegTab(
            label: l10n.publicProfileTabShelf,
            count: shelfCount,
            active: selected == _ProfileTab.shelf,
            onTap: () => onChanged(_ProfileTab.shelf),
          ),
        ],
      ),
    );
  }
}

class _SegTab extends StatelessWidget {
  const _SegTab({
    required this.label,
    required this.count,
    required this.active,
    required this.onTap,
  });

  final String label;
  final int? count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? AppColors.card : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: active
                ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 3, offset: Offset(0, 1))]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: active ? AppColors.oxblood : AppColors.inkSoft,
                ),
              ),
              if (count != null)
                Text(
                  ' · $count',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: (active ? AppColors.oxblood : AppColors.inkSoft).withValues(alpha: 0.65),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The public shelf — an advanced (transliteration-aware) search over a
/// covers-first grid, each cover a door to the catalog book page. Local
/// substring runs on every keystroke; a 300ms-debounced books-only catalog
/// search (the same cross-script search global search uses) unions in by
/// work id, so "kayar" also finds a "കയർ" title on their shelf.
class _PublicShelf extends ConsumerStatefulWidget {
  const _PublicShelf({required this.userId});

  final String userId;

  @override
  ConsumerState<_PublicShelf> createState() => _PublicShelfState();
}

class _PublicShelfState extends ConsumerState<_PublicShelf> {
  String _query = '';
  String _remoteQuery = '';
  Timer? _debounce;

  void _onChanged(String value) {
    setState(() => _query = value);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _remoteQuery = value);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

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
        final remoteQuery = _remoteQuery.trim();
        final crossScriptWorkIds = remoteQuery.length < 2
            ? const <String>{}
            : (ref.watch(catalogSearchProvider(remoteQuery)).valueOrNull ?? const [])
                .map((w) => w['id'] as String)
                .toSet();
        final filtered = q.isEmpty
            ? items
            : items
                .where((b) =>
                    ((b['title'] as String?) ?? '').toLowerCase().contains(q) ||
                    ((b['author_names'] as String?) ?? '').toLowerCase().contains(q) ||
                    crossScriptWorkIds.contains(b['work_id']))
                .toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              onChanged: _onChanged,
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
          return _MutedNote(l10n.connectionLoansEmpty);
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
