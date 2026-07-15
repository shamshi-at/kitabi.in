import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

/// The small gold "On Kitabi" pill marking a catalog author who is also a
/// linked, registered reader (`authors.linked_user_id`) — reused wherever an
/// author name can appear (search, the add-book author picker, the author
/// browse page) so the signal reads the same everywhere. Same gold-pill
/// language the lending ledger already uses for a linked borrower/lender.
class KitabiLinkedBadge extends StatelessWidget {
  const KitabiLinkedBadge({super.key, this.compact = false});

  /// Smaller padding/text for tight rows (e.g. the author picker's typeahead).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 7, vertical: compact ? 1 : 2),
      decoration: BoxDecoration(
        color: AppColors.goldSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.link, size: compact ? 9 : 10, color: const Color(0xFF8F681E)),
          const SizedBox(width: 2),
          Text(
            l10n.linkedAuthorBadge,
            style: TextStyle(
              fontSize: compact ? 8 : 9,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF8F681E),
            ),
          ),
        ],
      ),
    );
  }
}
