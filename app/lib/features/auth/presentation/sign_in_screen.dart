import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/brand_mark.dart';
import '../../../l10n/app_localizations.dart';

/// S1 — matches docs/kitabi_screens.html: mark, wordmark, tagline, the gold
/// fleuron, a rotating literary quote with its attribution, Google + Apple
/// (iOS only), a private-by-default footnote.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

enum _Provider { google, apple }

class _SignInScreenState extends ConsumerState<SignInScreen> {
  /// Which button was tapped — that one shows the spinner, both disable.
  _Provider? _loading;
  // Picked once in initState (not per-rebuild) so the quote doesn't jump
  // around while the user is looking at the screen.
  final int _quoteIndex = Random().nextInt(3);

  Future<void> _signIn(_Provider provider, Future<void> Function() action) async {
    setState(() => _loading = provider);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.signInError)),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = null);
    }
  }

  Widget _spinner(Color color) => SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: color),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final authService = ref.read(authServiceProvider);
    final quotes = [
      (l10n.signInQuote1, l10n.signInQuote1Author),
      (l10n.signInQuote2, l10n.signInQuote2Author),
      (l10n.signInQuote3, l10n.signInQuote3Author),
    ];
    final (quote, author) = quotes[_quoteIndex];
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
                  l10n.splashTagline.toUpperCase(),
                  style: TextStyle(
                    color: AppColors.gold,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 3.5,
                  ),
                ),
                SizedBox(height: 22),
                // The mockup's gold fleuron — a small typographic rest between
                // the brand block and the quote.
                Text(
                  '❦',
                  style: TextStyle(color: AppColors.gold, fontSize: 12, letterSpacing: 6),
                ),
                SizedBox(height: 18),
                Text(
                  '“$quote”',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.fraunces(
                    fontSize: 15,
                    fontStyle: FontStyle.italic,
                    color: AppColors.inkSoft,
                    height: 1.45,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  '— $author',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1,
                    color: AppColors.inkSoft,
                  ),
                ),
                SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _loading != null
                        ? null
                        : () => _signIn(_Provider.google, authService.signInWithGoogle),
                    child: _loading == _Provider.google
                        ? _spinner(AppColors.ink)
                        : Text(l10n.signInGoogle),
                  ),
                ),
                if (isIOS) ...[
                  SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      // Constant colors on purpose: brightness-aware tokens on
                      // this always-dark button made it cream-on-cream at night.
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFF2B2118),
                        foregroundColor: Color(0xFFF6F0E3),
                      ),
                      onPressed: _loading != null
                          ? null
                          : () => _signIn(_Provider.apple, authService.signInWithApple),
                      child: _loading == _Provider.apple
                          ? _spinner(Color(0xFFF6F0E3))
                          : Text(l10n.signInApple),
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
