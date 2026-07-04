import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';

/// Placeholder home — replaced by the real dashboard (S3) in a later phase.
/// The profile icon is a temporary way in until the real bottom nav lands.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline, color: AppColors.oxblood),
            onPressed: () => context.push(Routes.profile),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.appTitle,
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    color: AppColors.oxblood,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 4,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.homeGreeting,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: AppColors.gold,
                    letterSpacing: 3,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
