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
import '../connections_providers.dart';

/// Another reader's public face: avatar, name/@handle, contribution score and
/// shelf counts, a Connect action, and — when they've made their library
/// public — their shelf as a cover grid, each book a door into the shared
/// catalog. Profiles are public by default; a reader who opted out shows a
/// quiet "keeps their profile private" state (the API 404s, deliberately
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

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(title: Text(name ?? l10n.publicProfileTitle)),
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

class _ProfileBody extends ConsumerWidget {
  const _ProfileBody({required this.userId, required this.profile});

  final String userId;
  final Map<String, dynamic> profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
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
        ref.watch(connectionsProvider).valueOrNull?.statusForUser(userId);

    return ListView(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 30,
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
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(display, style: Theme.of(context).textTheme.titleLarge),
                  if (username != null && (fullName?.isNotEmpty ?? false))
                    Text(
                      '@$username',
                      style: TextStyle(color: AppColors.inkSoft, fontSize: 12.5),
                    ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: 14),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _StatChip(
              icon: Icons.military_tech_outlined,
              label: l10n.publicProfileScore(profile['score'] as int? ?? 0),
              color: AppColors.gold,
            ),
            _StatChip(
              icon: Icons.auto_stories_outlined,
              label: l10n.publicProfileBooks(profile['books_tracked'] as int? ?? 0),
              color: AppColors.slate,
            ),
            _StatChip(
              icon: Icons.check_circle_outline,
              label:
                  '${l10n.homeShelfRead} · ${profile['books_finished'] as int? ?? 0}',
              color: AppColors.moss,
            ),
          ],
        ),
        SizedBox(height: 14),
        _ConnectRow(userId: userId, status: connStatus, display: display),
        SizedBox(height: 20),
        Text(
          l10n.publicLibrarySection.toUpperCase(),
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: AppColors.inkSoft,
          ),
        ),
        SizedBox(height: 8),
        if (!libraryVisible)
          Text(
            l10n.publicLibraryPrivate,
            style: TextStyle(color: AppColors.inkSoft, fontSize: 12.5),
          )
        else
          _PublicShelf(userId: userId),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}

/// Connect / connection-state row: a Connect button for strangers, a quiet
/// state pill once a request is pending or accepted; accepted also opens the
/// loans-between-you page.
class _ConnectRow extends ConsumerStatefulWidget {
  const _ConnectRow({required this.userId, required this.status, required this.display});

  final String userId;
  final String? status;
  final String display;

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
      'accepted' => SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () =>
                openPersonLoans(context, userId: widget.userId, name: widget.display),
            icon: Icon(Icons.swap_horiz, size: 16),
            label: Text(l10n.lendingLedgerTitle),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.oxblood,
              side: BorderSide(color: AppColors.line),
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
