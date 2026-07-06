import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/sync/sync_providers.dart';
import '../../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

/// A slim, global banner (in the nav shell) shown ONLY when sync has actually
/// failed — a tappable "some changes haven't synced" after ops exhaust their
/// retries. Routine syncing is silent/background: the transient "Syncing…"
/// pill was removed (it read as noise for a background process).
class SyncStatusBar extends ConsumerWidget {
  const SyncStatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
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
    // A slim, centered pill with margin — reads as an intentional status chip,
    // not a full-bleed alert band.
    return Padding(
      padding: EdgeInsets.fromLTRB(0, 6, 0, 2),
      child: Center(
        child: Material(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 13, color: color),
                  SizedBox(width: 7),
                  Text(
                    text,
                    style: TextStyle(fontSize: 11.5, color: color, fontWeight: FontWeight.w600),
                  ),
                  if (onTap != null) ...[
                    SizedBox(width: 4),
                    Icon(Icons.chevron_right, size: 15, color: color),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
