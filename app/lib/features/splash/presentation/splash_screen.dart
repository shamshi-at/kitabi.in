import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/brand_mark.dart';

/// Shown while auth state (and, once signed in, the profile bootstrap call)
/// resolves. The router redirect leaves this location alone until then, so
/// there's no sign-in-screen flash for an already-authenticated user.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.paper,
      body: Center(
        child: BrandMark(size: 72),
      ),
    );
  }
}
