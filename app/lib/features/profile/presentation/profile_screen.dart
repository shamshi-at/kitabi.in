import 'dart:math';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/haptics.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/api/api_client.dart';
import '../../../l10n/app_localizations.dart';
import '../../import_books/csv_export.dart';
import '../../insights/providers/insights_providers.dart';
import '../../settings/theme_mode_provider.dart';
import '../providers/profile_providers.dart';

/// S12 — the dormant community switchboard: profile/library/review
/// visibility, all default off (feature-map.md `[WIRED]` rule 4).
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        elevation: 0,
        foregroundColor: AppColors.ink,
        title: Text(l10n.profileTitle, style: Theme.of(context).textTheme.titleLarge),
      ),
      body: SafeArea(
        top: false,
        child: me.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text('$err')),
          data: (profile) => _ProfileBody(profile: profile),
        ),
      ),
    );
  }
}

class _ProfileBody extends ConsumerStatefulWidget {
  const _ProfileBody({required this.profile});

  final Map<String, dynamic> profile;

  @override
  ConsumerState<_ProfileBody> createState() => _ProfileBodyState();
}

class _ProfileBodyState extends ConsumerState<_ProfileBody> {
  // Optimistic local mirror of the server-side visibility flags, so a tap flips
  // instantly instead of waiting on the /me round-trip (what made the old
  // switches feel dead). Reverts + warns if the save fails.
  late final Map<String, bool> _vis = {
    for (final k in const ['profile_visible', 'library_visible', 'reviews_visible_default'])
      k: widget.profile[k] as bool? ?? false,
  };

  Future<void> _toggle(String field, bool value) async {
    final previous = _vis[field]!;
    setState(() => _vis[field] = value);
    Haptics.selection();
    try {
      await ref.read(apiClientProvider).updateMe({field: value});
    } catch (_) {
      if (!mounted) return;
      setState(() => _vis[field] = previous);
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.profileVisibilitySaveError)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final profile = widget.profile;
    final fullName = profile['full_name'] as String? ?? profile['email'] as String? ?? '';
    final initial = fullName.isNotEmpty ? fullName[0].toUpperCase() : '?';
    final createdAt = DateTime.tryParse(profile['created_at'] as String? ?? '');

    return ListView(
      padding: EdgeInsets.all(20),
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: AppColors.oxblood,
              child: Text(initial, style: TextStyle(color: AppColors.paper)),
            ),
            SizedBox(width: 14),
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
        SizedBox(height: 20),
        Card(
          child: Padding(
            padding: EdgeInsets.all(12),
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
                Divider(height: 20),
                _VisibilityRow(
                  title: l10n.profileVisibilityProfileTitle,
                  subtitle: l10n.profileVisibilityProfileDesc,
                  isPublic: _vis['profile_visible']!,
                  onChanged: (v) => _toggle('profile_visible', v),
                ),
                _VisibilityRow(
                  title: l10n.profileVisibilityLibraryTitle,
                  subtitle: l10n.profileVisibilityLibraryDesc,
                  isPublic: _vis['library_visible']!,
                  onChanged: (v) => _toggle('library_visible', v),
                ),
                _VisibilityRow(
                  title: l10n.profileVisibilityReviewsTitle,
                  subtitle: l10n.profileVisibilityReviewsDesc,
                  isPublic: _vis['reviews_visible_default']!,
                  onChanged: (v) => _toggle('reviews_visible_default', v),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: 16),
        Card(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: _SwitchRow(
              title: l10n.profileDarkMode,
              subtitle: l10n.profileDarkModeDesc,
              value: ref.watch(themeModeControllerProvider),
              onChanged: (v) {
                Haptics.selection();
                ref.read(themeModeControllerProvider.notifier).set(v);
              },
            ),
          ),
        ),
        SizedBox(height: 24),
        _ActionButton(
          icon: Icons.history,
          label: l10n.activityEntry,
          onPressed: () => context.push(Routes.activity),
        ),
        SizedBox(height: 8),
        _ActionButton(
          icon: Icons.auto_awesome,
          label: l10n.recsProfileEntry,
          onPressed: () => context.push(Routes.recommendations),
        ),
        SizedBox(height: 8),
        _ActionButton(
          icon: Icons.upload_file_outlined,
          label: l10n.importEntry,
          onPressed: () => context.push(Routes.importBooks),
        ),
        SizedBox(height: 8),
        _ActionButton(
          icon: Icons.download_outlined,
          label: l10n.exportEntry,
          onPressed: () => _exportLibrary(context),
        ),
        SizedBox(height: 24),
        const _QuoteCard(),
        SizedBox(height: 24),
        Center(
          child: TextButton(
            onPressed: () => ref.read(authServiceProvider).signOut(),
            child: Text(l10n.profileSignOut, style: TextStyle(color: AppColors.inkSoft)),
          ),
        ),
        Center(
          child: TextButton(
            onPressed: () => _confirmDelete(context),
            child: Text(
              l10n.profileDeleteAccount,
              style: TextStyle(color: AppColors.oxbloodDeep, fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _exportLibrary(BuildContext context) async {
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

  Future<void> _confirmDelete(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.profileDeleteAccount),
        content: Text(l10n.profileDeleteAccountConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.profileDeleteAccount,
                style: TextStyle(color: AppColors.oxbloodDeep)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(apiClientProvider).deleteMe();
    await ref.read(authServiceProvider).signOut();
  }
}

/// A full-width outlined nav button — uniform across the profile's action list.
class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.label, required this.onPressed});

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
      ),
    );
  }
}

/// A visibility setting shown as a tappable Private ⇄ Public pill — a clearer,
/// bigger tap target than a bare switch, with the current state spelled out.
class _VisibilityRow extends StatelessWidget {
  const _VisibilityRow({
    required this.title,
    required this.subtitle,
    required this.isPublic,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool isPublic;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final color = isPublic ? AppColors.moss : AppColors.inkSoft;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
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
          SizedBox(width: 12),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => onChanged(!isPublic),
              child: AnimatedContainer(
                duration: Duration(milliseconds: 150),
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: isPublic ? AppColors.moss.withValues(alpha: 0.14) : AppColors.paperDeep,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(isPublic ? Icons.public : Icons.lock_outline, size: 14, color: color),
                    SizedBox(width: 5),
                    Text(
                      isPublic ? l10n.visibilityPublic : l10n.visibilityPrivate,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A plain on/off switch row — used for the Night reading (dark mode) toggle,
/// where a two-state switch reads more naturally than a Private/Public pill.
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
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
      padding: EdgeInsets.symmetric(vertical: 6),
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
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.night,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(
              quote,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.goldSoft,
                fontStyle: FontStyle.italic,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '— $author · TAP FOR A NEW ONE',
              style: TextStyle(color: AppColors.inkSoft, fontSize: 10, letterSpacing: 1),
            ),
          ],
        ),
      ),
    );
  }
}
