import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/brand_mark.dart';
import '../../../data/api/api_client.dart';
import '../../../l10n/app_localizations.dart';

/// Shown (and not dismissible) when the API rejects this build as too old
/// (HTTP 426 — the version gate). A real store link lands with store listings.
class UpdateScreen extends ConsumerWidget {
  const UpdateScreen({super.key});

  /// Re-runs the version check: clears the 426 flag (the router then lets the
  /// app off this screen) and re-fires the profile bootstrap call. If the API
  /// still says 426, the Dio interceptor flips the flag straight back and the
  /// router returns here — a genuine re-check, not just a dismiss.
  void _tryAgain(WidgetRef ref) {
    ref.read(updateRequiredProvider.notifier).state = false;
    ref.invalidate(bootstrapProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final isIOS = defaultTargetPlatform == TargetPlatform.iOS;
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BrandMark(size: 72),
                SizedBox(height: 20),
                Text(
                  l10n.updateTitle,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: AppColors.oxblood,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                SizedBox(height: 10),
                Text(
                  isIOS ? l10n.updateBodyAppStore : l10n.updateBodyPlayStore,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft),
                ),
                SizedBox(height: 24),
                OutlinedButton(
                  onPressed: () => _tryAgain(ref),
                  child: Text(l10n.updateTryAgain),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
