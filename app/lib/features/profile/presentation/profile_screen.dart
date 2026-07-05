import 'dart:math';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/api/api_client.dart';
import '../../../l10n/app_localizations.dart';
import '../../import_books/csv_export.dart';
import '../../insights/providers/insights_providers.dart';
import '../providers/profile_providers.dart';

/// S12 — the dormant community switchboard: profile/library/review
/// visibility, all default off (feature-map.md `[WIRED]` rule 4).
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: me.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text('$err')),
          data: (profile) => _ProfileBody(profile: profile),
        ),
      ),
    );
  }
}

class _ProfileBody extends ConsumerWidget {
  const _ProfileBody({required this.profile});

  final Map<String, dynamic> profile;

  Future<void> _toggle(WidgetRef ref, String field, bool value) async {
    await ref.read(apiClientProvider).updateMe({field: value});
    ref.invalidate(meProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final fullName = profile['full_name'] as String? ?? profile['email'] as String? ?? '';
    final initial = fullName.isNotEmpty ? fullName[0].toUpperCase() : '?';
    final createdAt = DateTime.tryParse(profile['created_at'] as String? ?? '');

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: AppColors.oxblood,
              child: Text(initial, style: const TextStyle(color: AppColors.paper)),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(fullName, style: Theme.of(context).textTheme.titleLarge),
                if (createdAt != null)
                  Text(
                    l10n.profileReadingSince(createdAt.year),
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.inkSoft),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.profileVisibilityHeader,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.inkSoft,
                        letterSpacing: 1,
                      ),
                ),
                const Divider(height: 20),
                _VisibilityRow(
                  title: l10n.profileVisibilityProfileTitle,
                  subtitle: l10n.profileVisibilityProfileDesc,
                  value: profile['profile_visible'] as bool? ?? false,
                  onChanged: (v) => _toggle(ref, 'profile_visible', v),
                ),
                _VisibilityRow(
                  title: l10n.profileVisibilityLibraryTitle,
                  subtitle: l10n.profileVisibilityLibraryDesc,
                  value: profile['library_visible'] as bool? ?? false,
                  onChanged: (v) => _toggle(ref, 'library_visible', v),
                ),
                _VisibilityRow(
                  title: l10n.profileVisibilityReviewsTitle,
                  subtitle: l10n.profileVisibilityReviewsDesc,
                  value: profile['reviews_visible_default'] as bool? ?? false,
                  onChanged: (v) => _toggle(ref, 'reviews_visible_default', v),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              OutlinedButton.icon(
                onPressed: () => context.push(Routes.importBooks),
                icon: const Icon(Icons.upload_file_outlined, size: 18),
                label: Text(l10n.importEntry),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _exportLibrary(context, ref),
                icon: const Icon(Icons.download_outlined, size: 18),
                label: Text(l10n.exportEntry),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const _QuoteCard(),
        const SizedBox(height: 24),
        Center(
          child: TextButton(
            onPressed: () => ref.read(authServiceProvider).signOut(),
            child: Text(l10n.profileSignOut, style: const TextStyle(color: AppColors.inkSoft)),
          ),
        ),
        Center(
          child: TextButton(
            onPressed: () => _confirmDelete(context, ref),
            child: Text(
              l10n.profileDeleteAccount,
              style: const TextStyle(color: AppColors.oxbloodDeep, fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _exportLibrary(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final hits = await ref.read(libraryWithBooksProvider.future);
    if (hits.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.exportEmpty)));
      }
      return;
    }
    final file = XFile.fromData(
      utf8.encode(buildLibraryCsv(hits)),
      name: 'kitabi-library.csv',
      mimeType: 'text/csv',
    );
    await Share.shareXFiles([file], text: l10n.exportShareText);
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.profileDeleteAccount),
        content: Text(l10n.profileDeleteAccountConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.profileDeleteAccount,
                style: const TextStyle(color: AppColors.oxbloodDeep)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(apiClientProvider).deleteMe();
    await ref.read(authServiceProvider).signOut();
  }
}

class _VisibilityRow extends StatelessWidget {
  const _VisibilityRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.bodyMedium),
                Text(subtitle,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.inkSoft)),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged, activeThumbColor: AppColors.moss),
        ],
      ),
    );
  }
}

class _QuoteCard extends StatefulWidget {
  const _QuoteCard();

  @override
  State<_QuoteCard> createState() => _QuoteCardState();
}

class _QuoteCardState extends State<_QuoteCard> {
  int _index = 0;

  static const _quotes = [
    ('"I have always imagined that Paradise will be a kind of library."', 'BORGES'),
    ('"A reader lives a thousand lives before he dies."', 'GEORGE R.R. MARTIN'),
    ('"A book must be the axe for the frozen sea within us."', 'KAFKA'),
  ];

  @override
  Widget build(BuildContext context) {
    final (quote, author) = _quotes[_index];
    return GestureDetector(
      onTap: () => setState(() => _index = Random().nextInt(_quotes.length)),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.night,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(
              quote,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.goldSoft,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '— $author · TAP FOR A NEW ONE',
              style: const TextStyle(color: AppColors.inkSoft, fontSize: 10, letterSpacing: 1),
            ),
          ],
        ),
      ),
    );
  }
}
