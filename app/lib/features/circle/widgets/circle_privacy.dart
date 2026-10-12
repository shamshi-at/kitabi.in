import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/haptics.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/section_label.dart';
import '../../../data/api/api_client.dart';
import '../../../data/db/database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../profile/providers/profile_providers.dart';
import '../circle_providers.dart';

/// Profile → "Your circle" (mockup 3b): a group of its own, apart from the
/// public switches, so a reader never wonders whether sharing with their
/// circle just made something public. Optimistic like the visibility pills
/// beside it — a tap flips at once and reverts with a warning if the save fails.
class CirclePrivacyCard extends ConsumerStatefulWidget {
  const CirclePrivacyCard({super.key, required this.profile});

  final Map<String, dynamic> profile;

  @override
  ConsumerState<CirclePrivacyCard> createState() => _CirclePrivacyCardState();
}

class _CirclePrivacyCardState extends ConsumerState<CirclePrivacyCard> {
  static const _keys = [
    'circle_share_reading',
    'circle_share_ratings',
    'circle_share_owned',
  ];

  late Map<String, bool> _on = _seed();

  Map<String, bool> _seed() => {
    for (final k in _keys) k: widget.profile[k] == true,
  };

  @override
  void didUpdateWidget(covariant CirclePrivacyCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.profile, widget.profile)) _on = _seed();
  }

  Future<void> _toggle(String field, bool value) async {
    final previous = Map<String, bool>.of(_on);
    setState(() => _on[field] = value);
    Haptics.selection();
    try {
      await ref.read(apiClientProvider).updateMe({field: value});
      // A fresh /me re-derives what this reader shares, which every circle
      // surface watches — the card on the book page reflects it on return.
      ref.invalidate(meProvider);
    } catch (_) {
      if (!mounted) return;
      setState(() => _on = previous);
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.profileVisibilitySaveError)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final reading = _on['circle_share_reading']!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionLabel(l10n.circlePrivacyHeader, padding: EdgeInsets.zero),
            const Divider(height: 20),
            _Row(
              title: l10n.circleShareReading,
              subtitle: l10n.circleShareReadingHint,
              value: reading,
              onChanged: (v) => _toggle('circle_share_reading', v),
            ),
            _Row(
              title: l10n.circleShareRatings,
              subtitle: l10n.circleShareRatingsHint,
              // Ratings ride on reading: shown off and inert while reading is.
              value: reading && _on['circle_share_ratings']!,
              onChanged: reading
                  ? (v) => _toggle('circle_share_ratings', v)
                  : null,
            ),
            _Row(
              title: l10n.circleShareOwned,
              subtitle: l10n.circleShareOwnedHint,
              value: _on['circle_share_owned']!,
              onChanged: (v) => _toggle('circle_share_owned', v),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.circlePrivacyNote,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.inkSoft),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onChanged == null ? 0.5 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.bodyMedium),
                  Text(
                    subtitle,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: AppColors.inkSoft),
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: AppColors.moss,
            ),
          ],
        ),
      ),
    );
  }
}

/// "Keep this one to myself" on a book's Yours tab (mockup 3c). Shown only to
/// a reader who shares something — for anyone else there is nothing to hide
/// from. A property of the copy: it writes Drift and the sync queue like every
/// other entry change, so it works offline.
class CircleHiddenRow extends ConsumerWidget {
  const CircleHiddenRow({super.key, required this.entry});

  final LibraryEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sharing = ref.watch(circleSharingProvider);
    if (sharing == null || !sharing.any) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 4, 6, 4),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Icon(
            Icons.visibility_off_outlined,
            size: 16,
            color: AppColors.inkSoft,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.circleKeepToMyself,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  Text(
                    entry.circleHidden
                        ? l10n.circleKeptHint
                        : l10n.circleKeepToMyselfHint,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.35,
                      color: entry.circleHidden
                          ? AppColors.moss
                          : AppColors.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Switch(
            value: entry.circleHidden,
            activeThumbColor: AppColors.moss,
            onChanged: (v) async {
              Haptics.selection();
              final repo = await ref.read(libraryRepositoryProvider.future);
              await repo.setCircleHidden(entry.id, v);
            },
          ),
        ],
      ),
    );
  }
}
