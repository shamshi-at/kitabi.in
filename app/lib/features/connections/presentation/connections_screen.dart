import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/haptics.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/async_states.dart';
import '../../../data/api/api_client.dart';
import '../../../l10n/app_localizations.dart';
import '../connections_providers.dart';

/// The connections inbox (S8b) — the consent layer for peer-to-peer lending.
/// Requests to approve (accept / deny / block), requests you've sent, declined
/// ones you can re-send (until the other person blocks you), confirmed
/// connections, and people you've blocked.
class ConnectionsScreen extends ConsumerWidget {
  const ConnectionsScreen({super.key});

  Future<void> _act(WidgetRef ref, Future<void> Function(ApiClient api) action) async {
    Haptics.selection();
    await action(ref.read(apiClientProvider));
    ref.invalidate(connectionsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final connections = ref.watch(connectionsProvider);

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        elevation: 0,
        foregroundColor: AppColors.ink,
        title: Text(l10n.connectionsTitle, style: Theme.of(context).textTheme.titleLarge),
      ),
      body: connections.when(
        loading: () => ListSkeleton(),
        error: (err, _) => ErrorRetry(onRetry: () => ref.invalidate(connectionsProvider)),
        data: (data) {
          final empty = data.incoming.isEmpty &&
              data.outgoing.isEmpty &&
              data.accepted.isEmpty &&
              data.rejected.isEmpty &&
              data.blocked.isEmpty;
          if (empty) {
            return EmptyState(
              icon: Icons.people_outline,
              title: l10n.connectionsTitle,
              body: l10n.connectionsEmpty,
            );
          }
          return RefreshIndicator(
            color: AppColors.oxblood,
            onRefresh: () async => ref.invalidate(connectionsProvider),
            child: ListView(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                if (data.incoming.isNotEmpty) ...[
                  _SectionLabel(l10n.connectionsIncomingSection),
                  for (final c in data.incoming)
                    _ConnectionCard(
                      user: c.other,
                      subtitle: l10n.connectionsWantsToConnect,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _CardButton(
                            label: l10n.connectionsAccept,
                            primary: true,
                            onTap: () => _act(ref, (api) => api.acceptConnection(c.id)),
                          ),
                          _Kebab(items: [
                            (l10n.connectionsDeny, () => _act(ref, (api) => api.declineConnection(c.id))),
                            (l10n.connectionsBlock, () => _act(ref, (api) => api.blockConnection(c.id))),
                          ]),
                        ],
                      ),
                    ),
                  SizedBox(height: 14),
                ],
                if (data.outgoing.isNotEmpty) ...[
                  _SectionLabel(l10n.connectionsOutgoingSection),
                  for (final c in data.outgoing)
                    _ConnectionCard(
                      user: c.other,
                      subtitle: l10n.connectionsAwaitingReply,
                      trailing: _CardButton(
                        label: l10n.connectionsCancel,
                        onTap: () => _act(ref, (api) => api.declineConnection(c.id)),
                      ),
                    ),
                  SizedBox(height: 14),
                ],
                if (data.rejected.isNotEmpty) ...[
                  _SectionLabel(l10n.connectionsRejectedSection),
                  for (final c in data.rejected)
                    _ConnectionCard(
                      user: c.other,
                      subtitle: l10n.connectionsDeclinedYou,
                      trailing: _CardButton(
                        label: l10n.connectionsResend,
                        primary: true,
                        onTap: () => _act(ref, (api) => api.requestConnection(c.other.id)),
                      ),
                    ),
                  SizedBox(height: 14),
                ],
                if (data.accepted.isNotEmpty) ...[
                  _SectionLabel(l10n.connectionsAcceptedSection),
                  for (final c in data.accepted)
                    _ConnectionCard(
                      user: c.other,
                      subtitle: c.other.username != null ? '@${c.other.username}' : null,
                      onTap: () => context.push(
                        Routes.connectionLoans,
                        extra: {'userId': c.other.id, 'name': c.other.display},
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _CardButton(
                            label: l10n.connectionsDisconnect,
                            onTap: () => _act(ref, (api) => api.declineConnection(c.id)),
                          ),
                          _Kebab(items: [
                            (l10n.connectionsBlock, () => _act(ref, (api) => api.blockConnection(c.id))),
                          ]),
                        ],
                      ),
                    ),
                  SizedBox(height: 14),
                ],
                if (data.blocked.isNotEmpty) ...[
                  _SectionLabel(l10n.connectionsBlockedSection),
                  for (final c in data.blocked)
                    _ConnectionCard(
                      user: c.other,
                      subtitle: c.other.username != null ? '@${c.other.username}' : null,
                      trailing: _CardButton(
                        label: l10n.connectionsUnblock,
                        onTap: () => _act(ref, (api) => api.unblockConnection(c.id)),
                      ),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: 8, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: AppColors.inkSoft,
        ),
      ),
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.user,
    required this.subtitle,
    required this.trailing,
    this.onTap,
  });

  final ConnectionUser user;
  final String? subtitle;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final name = user.display.replaceAll('@', '');
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.only(bottom: 8),
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.goldSoft,
              borderRadius: BorderRadius.circular(40),
            ),
            child: Text(
              initial,
              style: TextStyle(
                color: Color(0xFF8F681E),
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.display,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.inkSoft, fontSize: 12),
                  ),
              ],
            ),
          ),
          SizedBox(width: 8),
          trailing,
        ],
        ),
      ),
    );
  }
}

class _CardButton extends StatelessWidget {
  const _CardButton({required this.label, required this.onTap, this.primary = false});

  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        backgroundColor: primary ? AppColors.oxblood : Colors.transparent,
        foregroundColor: primary ? AppColors.paper : AppColors.inkSoft,
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: primary ? BorderSide.none : BorderSide(color: AppColors.line),
        ),
      ),
      child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

/// Overflow menu for a card's secondary actions (deny, block…).
class _Kebab extends StatelessWidget {
  const _Kebab({required this.items});

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
