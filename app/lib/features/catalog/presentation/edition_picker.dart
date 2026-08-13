import 'package:flutter/material.dart';

import '../../../core/widgets/select_sheet.dart';
import '../../../l10n/app_localizations.dart';
import '../work_editions.dart';

/// "Which printing is yours?" — asked only when the answer isn't obvious.
///
/// A Work carries every printing anyone has catalogued, and a silent pick of
/// the representative one is how a reader ended up with a 55-page first
/// edition on the shelf while holding a 240-page reprint (owner report,
/// 13 Aug 2026). One edition needs no question; several do, and the page
/// count is the thing that answers it.
///
/// Returns the chosen edition, or null if the reader dismissed the sheet.
Future<Map<String, dynamic>?> chooseEdition(
  BuildContext context,
  List<Map<String, dynamic>> editions,
) async {
  if (editions.isEmpty) return null;
  if (editions.length == 1) return editions.first;

  final l10n = AppLocalizations.of(context)!;
  Map<String, dynamic>? picked;
  await openSelectSheet(
    context,
    title: l10n.editionPickTitle,
    current: null,
    options: [
      for (final edition in editions)
        SelectOption(
          edition['id'] as String,
          editionLabel(edition).isEmpty ? l10n.editionPickFallback : editionLabel(edition),
        ),
    ],
    onChanged: (id) {
      for (final edition in editions) {
        if (edition['id'] == id) picked = edition;
      }
    },
  );
  return picked;
}
