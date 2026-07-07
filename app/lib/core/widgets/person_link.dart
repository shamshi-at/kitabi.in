import 'package:flutter/material.dart';

import '../router/app_router.dart';
import '../theme/app_theme.dart';

/// A counterparty name rendered as a door (same pattern as author/publisher
/// names — docs/screen-design.md): tinted oxblood and tappable, opening the
/// loans-with-this-person page. Works for linked Kitabi users ([userId]) and
/// self-logged free-text names alike.
class PersonLink extends StatelessWidget {
  const PersonLink(this.name, {super.key, this.userId, this.fontSize = 11});

  final String name;
  final String? userId;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => openPersonLoans(context, userId: userId, name: name),
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
