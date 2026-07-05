import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/haptics.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../onboarding_providers.dart';

/// First-run welcome (S3 precursor) — three quiet cards that orient a new
/// reader, shown once. Skippable; "Get started" marks it seen and drops into
/// the home.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    Haptics.success();
    await markOnboardingSeen(ref);
    if (mounted) context.go(Routes.home);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final pages = <(IconData, String, String)>[
      (Icons.auto_stories_outlined, l10n.welcomeTitle1, l10n.welcomeBody1),
      (Icons.swap_horiz, l10n.welcomeTitle2, l10n.welcomeBody2),
      (Icons.lock_outline, l10n.welcomeTitle3, l10n.welcomeBody3),
    ];
    final isLast = _page == pages.length - 1;

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: EdgeInsets.only(right: 12, top: 4),
                child: TextButton(onPressed: _finish, child: Text(l10n.welcomeSkip)),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                onPageChanged: (i) => setState(() => _page = i),
                itemCount: pages.length,
                itemBuilder: (context, i) {
                  final (icon, title, body) = pages[i];
                  return Padding(
                    padding: EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 96,
                          height: 96,
                          decoration:
                              BoxDecoration(color: AppColors.goldSoft, shape: BoxShape.circle),
                          child: Icon(icon, size: 44, color: AppColors.oxblood),
                        ),
                        SizedBox(height: 28),
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: AppColors.oxblood,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        SizedBox(height: 12),
                        Text(
                          body,
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(color: AppColors.inkSoft, height: 1.5),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < pages.length; i++)
                  AnimatedContainer(
                    duration: Duration(milliseconds: 200),
                    margin: EdgeInsets.symmetric(horizontal: 3),
                    width: i == _page ? 20 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: i == _page ? AppColors.oxblood : AppColors.line,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isLast
                      ? _finish
                      : () => _controller.nextPage(
                            duration: Duration(milliseconds: 250),
                            curve: Curves.easeOut,
                          ),
                  child: Text(isLast ? l10n.welcomeGetStarted : l10n.welcomeNext),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
