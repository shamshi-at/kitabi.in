import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/haptics.dart';
import '../../../core/notifications/push_service.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/net_image.dart';
import '../../../data/api/api_client.dart';
import '../../../l10n/app_localizations.dart';
import '../../circle/circle_providers.dart';
import '../notifications_providers.dart';

/// The inbox behind the bell on Home (owner request, 14 Oct 2026): everything
/// a connection told the reader, newest first. New ones are highlighted until
/// opened; opening one marks it read and goes where its notification would
/// have gone; "Clear all" empties it.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  // Marked read here before the server has answered — the highlight goes the
  // moment the reader taps, not a round trip later.
  final _readHere = <String>{};

  void _refreshBell() {
    ref.invalidate(unreadNotificationsProvider);
    ref.invalidate(inboxProvider);
  }

  Future<void> _open(InboxItem item) async {
    Haptics.selection();
    // Taken before the await; null only outside the app's router (tests).
    final router = GoRouter.maybeOf(context);
    if (!item.read && !_readHere.contains(item.id)) {
      setState(() => _readHere.add(item.id));
      try {
        await ref.read(apiClientProvider).markNotificationsRead([item.id]);
      } catch (_) {
        // Still open it; the next refresh puts the highlight back if needed.
      }
      ref.invalidate(unreadNotificationsProvider);
    }
    if (item.type == 'borrow_ask') {
      ref.invalidate(borrowAsksProvider);
    }
    final route = pushTapRoute(item.data);
    // A type with no screen of its own (Home) has nowhere better to be than
    // here — marking it read is the whole action.
    if (route != Routes.home && router != null) {
      navigateFromExternal(router, route);
    }
  }

  Future<void> _markAllRead() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(apiClientProvider).markAllNotificationsRead();
      _refreshBell();
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.notificationsUpdateFailed)),
      );
    }
  }

  Future<void> _clearAll() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.notificationsClearTitle),
        content: Text(l10n.notificationsClearBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.notificationsClearConfirm),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiClientProvider).clearNotifications();
      _refreshBell();
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.notificationsUpdateFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final inbox = ref.watch(inboxProvider);
    final items = inbox.valueOrNull?.items ?? const <InboxItem>[];
    final anyUnread = items.any((i) => !i.read && !_readHere.contains(i.id));
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        title: Text(l10n.notificationsTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all),
            tooltip: l10n.notificationsMarkAllRead,
            onPressed: anyUnread ? _markAllRead : null,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: l10n.notificationsClearAll,
            onPressed: items.isEmpty ? null : _clearAll,
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.oxblood,
        onRefresh: () async {
          _refreshBell();
          await ref.read(inboxProvider.future);
        },
        child: inbox.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => _Message(text: l10n.notificationsOffline),
          data: (data) => data.items.isEmpty
              ? _Message(text: l10n.notificationsEmpty)
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: data.items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final item = data.items[i];
                    final unread = !item.read && !_readHere.contains(item.id);
                    return _NotificationTile(
                      item: item,
                      unread: unread,
                      onTap: () => _open(item),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    // Scrollable so pull-to-refresh still works on an empty inbox.
    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 120, 32, 32),
      children: [
        Icon(Icons.notifications_none, size: 40, color: AppColors.stampGrey),
        const SizedBox(height: 12),
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13.5,
            height: 1.5,
            color: AppColors.inkSoft,
          ),
        ),
      ],
    );
  }
}

/// "3m ago", "5h ago", "Yesterday", then a date — quiet, like a letter's date.
String notificationWhen(AppLocalizations l10n, DateTime at, DateTime now) {
  final local = at.toLocal();
  final diff = now.difference(local);
  if (diff.inMinutes < 1) return l10n.notificationsJustNow;
  if (diff.inMinutes < 60) return l10n.notificationsMinutesAgo(diff.inMinutes);
  if (diff.inHours < 24) return l10n.notificationsHoursAgo(diff.inHours);
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  if (today.difference(day).inDays == 1) return l10n.notificationsYesterday;
  return DateFormat.MMMd().format(local);
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.item,
    required this.unread,
    required this.onTap,
  });

  final InboxItem item;
  final bool unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final name = item.actorName ?? '';
    final initial = name.replaceFirst('@', '').trim();
    final created = item.createdAt;
    return Material(
      // New ones sit on gold-tinted paper with an oxblood dot; read ones are
      // plain cards. The highlight is the only thing that changes on open.
      color: unread ? AppColors.goldSoft : AppColors.card,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: unread
                  ? AppColors.gold.withValues(alpha: 0.6)
                  : AppColors.line,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.paperDeep,
                foregroundImage: item.actorAvatarUrl != null
                    ? netImageProvider(item.actorAvatarUrl!)
                    : null,
                child: Text(
                  initial.isEmpty
                      ? '·'
                      : initial.characters.first.toUpperCase(),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.goldInk,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: unread ? FontWeight.w800 : FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.body,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: AppColors.ink,
                      ),
                    ),
                    if (created != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          notificationWhen(l10n, created, DateTime.now()),
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.inkSoft,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (unread)
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 6),
                  child: Semantics(
                    label: l10n.notificationsNew,
                    child: Container(
                      key: const ValueKey('unread-dot'),
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: AppColors.oxblood,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
