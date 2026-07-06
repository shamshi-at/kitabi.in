import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/haptics.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/async_states.dart';
import '../../../data/api/api_client.dart';
import '../../../l10n/app_localizations.dart';
import '../connections_providers.dart';

/// The connections inbox (S8b) — the consent layer for peer-to-peer lending.
/// Incoming requests to approve/deny, requests you've sent, and confirmed
/// connections you can disconnect.
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
          final empty =
              data.incoming.isEmpty && data.outgoing.isEmpty && data.accepted.isEmpty;
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
                      actions: [
                        _CardButton(
                          label: l10n.connectionsAccept,
                          primary: true,
                          onTap: () => _act(ref, (api) => api.acceptConnection(c.id)),
                        ),
                        _CardButton(
                          label: l10n.connectionsDeny,
                          onTap: () => _act(ref, (api) => api.declineConnection(c.id)),
                        ),
                      ],
                    ),
                  SizedBox(height: 14),
                ],
                if (data.outgoing.isNotEmpty) ...[
                  _SectionLabel(l10n.connectionsOutgoingSection),
                  for (final c in data.outgoing)
                    _ConnectionCard(
                      user: c.other,
                      subtitle: l10n.connectionsAwaitingReply,
                      actions: [
                        _CardButton(
                          label: l10n.connectionsCancel,
                          onTap: () => _act(ref, (api) => api.declineConnection(c.id)),
                        ),
                      ],
                    ),
                  SizedBox(height: 14),
                ],
                if (data.accepted.isNotEmpty) ...[
                  _SectionLabel(l10n.connectionsAcceptedSection),
                  for (final c in data.accepted)
                    _ConnectionCard(
                      user: c.other,
                      subtitle: c.other.username != null ? '@${c.other.username}' : null,
                      actions: [
                        _CardButton(
                          label: l10n.connectionsDisconnect,
                          onTap: () => _act(ref, (api) => api.declineConnection(c.id)),
                        ),
                      ],
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
  const _ConnectionCard({required this.user, required this.subtitle, required this.actions});

  final ConnectionUser user;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final name = user.display.replaceAll('@', '');
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
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
          ...actions,
        ],
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
    return Padding(
      padding: EdgeInsets.only(left: 6),
      child: TextButton(
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
      ),
    );
  }
}
