import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../notifications_providers.dart';

/// The bell on Home's header — the way into the inbox, with the number of new
/// notifications on it until they're read.
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final unread = ref.watch(unreadNotificationsProvider).valueOrNull ?? 0;
    final button = IconButton(
      icon: Icon(
        unread > 0 ? Icons.notifications : Icons.notifications_none,
        color: AppColors.oxblood,
      ),
      tooltip: unread > 0
          ? l10n.notificationsUnreadTooltip(unread)
          : l10n.notificationsTitle,
      onPressed: () => context.push(Routes.notifications),
    );
    if (unread <= 0) return button;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        button,
        Positioned(
          top: 6,
          right: 5,
          child: IgnorePointer(
            child: Container(
              constraints: const BoxConstraints(minWidth: 17),
              height: 17,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.oxblood,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: AppColors.paper, width: 1.5),
              ),
              child: Text(
                unread > 9 ? '9+' : '$unread',
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.paper,
                  height: 1,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
