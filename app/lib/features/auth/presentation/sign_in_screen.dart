import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/brand_mark.dart';
import '../../../l10n/app_localizations.dart';

/// S1 — matches docs/kitabi_screens.html: mark, wordmark, tagline, a rotating
/// literary quote, Google + Apple (iOS only), a private-by-default footnote.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  bool _loading = false;
  // Picked once in initState (not per-rebuild) so the quote doesn't jump
  // around while the user is looking at the screen.
  final int _quoteIndex = Random().nextInt(3);

  Future<void> _signIn(Future<void> Function() action) async {
    setState(() => _loading = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.signInError)),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final authService = ref.read(authServiceProvider);
    final quotes = [l10n.signInQuote1, l10n.signInQuote2, l10n.signInQuote3];
    final isIOS = defaultTargetPlatform == TargetPlatform.iOS;

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BrandMark(size: 88),
                SizedBox(height: 18),
                Text(l10n.appTitle, style: Theme.of(context).textTheme.headlineLarge),
                SizedBox(height: 6),
                Text(
                  l10n.homeGreeting.toUpperCase(),
                  style: TextStyle(
                    color: AppColors.gold,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 3.5,
                  ),
                ),
                SizedBox(height: 28),
                Text(
                  '“${quotes[_quoteIndex]}”',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontStyle: FontStyle.italic,
                        color: AppColors.inkSoft,
                      ),
                ),
                SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _loading ? null : () => _signIn(authService.signInWithGoogle),
                    child: Text(l10n.signInGoogle),
                  ),
                ),
                if (isIOS) ...[
                  SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.ink),
                      onPressed: _loading ? null : () => _signIn(authService.signInWithApple),
                      child: Text(l10n.signInApple),
                    ),
                  ),
                ],
                SizedBox(height: 20),
                Text(
                  l10n.signInPrivacyNote,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.inkSoft),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
