import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../router/app_router.dart';
import '../theme/app_theme.dart';

/// A counterparty name rendered as a door (same pattern as author/publisher
/// names — docs/screen-design.md): tinted oxblood and tappable. A linked
/// Kitabi user ([userId] set) opens their public profile — which has the
/// ledger between you as its own tab, so the loans view is still one tap
/// away, not lost. A self-logged free-text name (no [userId], no account to
/// show a profile for) opens the loans-with-this-person page directly, same
/// as before.
class PersonLink extends StatelessWidget {
  const PersonLink(this.name, {super.key, this.userId, this.fontSize = 11});

  final String name;
  final String? userId;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => userId != null
          ? context.push(Routes.publicProfilePath(userId!), extra: name)
          : openPersonLoans(context, name: name),
      child: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: AppColors.oxblood,
          fontWeight: FontWeight.w600,
          fontSize: fontSize,
        ),
      ),
    );
  }
}
