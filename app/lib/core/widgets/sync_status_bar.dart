import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/sync/sync_providers.dart';
import '../../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

/// A slim, global banner (in the nav shell) that makes offline-first sync
/// visible: a quiet "Syncing…" while queued ops drain, and a tappable
/// "some changes haven't synced" when ops have exhausted their retries.
/// Invisible when everything is synced.
class SyncStatusBar extends ConsumerWidget {
  const SyncStatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final pending = ref.watch(unsyncedCountProvider).valueOrNull ?? 0;
    final errored = ref.watch(syncErrorCountProvider).valueOrNull ?? 0;

    if (errored > 0) {
      return _Bar(
        color: AppColors.oxblood,
        icon: Icons.sync_problem,
        text: l10n.syncError,
        onTap: () async {
          await ref.read(appDatabaseProvider).syncQueueDao.resetAttempts();
          ref.read(syncTriggerProvider)();
        },
      );
    }
    if (pending > 0) {
      return _Bar(color: AppColors.gold, icon: Icons.sync, text: l10n.syncPending);
    }
    return SizedBox.shrink();
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.color, required this.icon, required this.text, this.onTap});

  final Color color;
  final IconData icon;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.12),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          child: Row(
            children: [
              Icon(icon, size: 14, color: color),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(fontSize: 11.5, color: color, fontWeight: FontWeight.w600),
                ),
              ),
              if (onTap != null) Icon(Icons.chevron_right, size: 16, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
