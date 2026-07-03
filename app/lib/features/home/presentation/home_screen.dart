import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';

/// Placeholder home — replaced by the real dashboard in the v1 slice.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.appTitle,
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    color: AppColors.gold,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 4,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.homeGreeting,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: AppColors.teal,
                    letterSpacing: 3,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
