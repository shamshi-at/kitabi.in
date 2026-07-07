import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/language_chips.dart';
import '../../../data/api/api_client.dart';
import '../../../l10n/app_localizations.dart';
import '../../profile/providers/profile_providers.dart';

/// One-time onboarding step (after sign-in) capturing the reader's languages.
/// The router gates on this: while `preferred_languages` is empty the app lands
/// here, so it re-asks until at least one is chosen. Also reachable never after
/// that — editing lives in the profile.
class LanguagePickerScreen extends ConsumerStatefulWidget {
  const LanguagePickerScreen({super.key});

  @override
  ConsumerState<LanguagePickerScreen> createState() => _LanguagePickerScreenState();
}

class _LanguagePickerScreenState extends ConsumerState<LanguagePickerScreen> {
  final Set<String> _selected = {};
  bool _saving = false;

  Future<void> _save() async {
    if (_selected.isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref.read(apiClientProvider).updateMe({'preferred_languages': _selected.toList()});
      // Wait until /me actually reflects the saved languages BEFORE navigating —
      // otherwise the router's redirect can run while meProvider is still
      // reloading (empty languages) and bounce us straight back here, leaving the
      // screen stuck even though the save succeeded server-side.
      ref.invalidate(meProvider);
      await ref.read(meProvider.future);
      if (mounted) context.go(Routes.home);
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.langPickerTitle,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 10),
              Text(
                l10n.langPickerSubtitle,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppColors.inkSoft, height: 1.4),
              ),
              const SizedBox(height: 28),
              Expanded(
                child: SingleChildScrollView(
                  child: LanguageChips(
                    selected: _selected,
                    onToggle: (lang) => setState(
                      () => _selected.contains(lang) ? _selected.remove(lang) : _selected.add(lang),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (_selected.isEmpty || _saving) ? null : _save,
                  child: _saving
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.paper),
                        )
                      : Text(l10n.langPickerContinue),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
