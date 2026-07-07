import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/haptics.dart';
import '../../../core/notifications/push_service.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/language_chips.dart';
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

  Future<void> _editUsername() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _UsernameSheet(current: widget.profile['username'] as String?),
    );
    if (saved == true) ref.invalidate(meProvider);
  }

  Future<void> _editLanguages() async {
    final current = (widget.profile['preferred_languages'] as List?)?.cast<String>() ?? const [];
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _LanguagesSheet(current: current.toSet()),
    );
    if (saved == true) ref.invalidate(meProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final profile = widget.profile;
    final fullName = profile['full_name'] as String? ?? profile['email'] as String? ?? '';
    final initial = fullName.isNotEmpty ? fullName[0].toUpperCase() : '?';
    final createdAt = DateTime.tryParse(profile['created_at'] as String? ?? '');
    final username = profile['username'] as String?;
    final langs = (profile['preferred_languages'] as List?)?.cast<String>() ?? const <String>[];

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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(fullName, style: Theme.of(context).textTheme.titleLarge),
                  GestureDetector(
                    onTap: _editUsername,
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (username != null)
                            Text(
                              '@$username',
                              style: TextStyle(
                                color: AppColors.oxblood,
                                fontWeight: FontWeight.w600,
                              ),
                            )
                          else
                            Text(
                              l10n.profileUsernameSet,
                              style: TextStyle(color: AppColors.oxblood, fontSize: 13),
                            ),
                          SizedBox(width: 4),
                          Icon(Icons.edit, size: 12, color: AppColors.inkSoft),
                        ],
                      ),
                    ),
                  ),
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
            ),
          ],
        ),
        SizedBox(height: 20),
        const _ReputationCard(),
        SizedBox(height: 16),
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
          child: InkWell(
            onTap: _editLanguages,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(Icons.translate, size: 18, color: AppColors.oxblood),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.profileLanguagesTitle,
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        SizedBox(height: 2),
                        Text(
                          langs.isEmpty ? l10n.profileLanguagesEmpty : langs.join(' · '),
                          style: TextStyle(color: AppColors.inkSoft, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 18, color: AppColors.inkSoft),
                ],
              ),
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
        SizedBox(height: 16),
        const _PushDiagnosticsTile(),
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

/// StackOverflow-style reputation — the total the reader has earned, with a
/// breakdown of where the points came from (contributions + activity).
class _ReputationCard extends ConsumerWidget {
  const _ReputationCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final score = ref.watch(scoreProvider);
    return Card(
      child: Padding(
        padding: EdgeInsets.all(14),
        child: score.when(
          loading: () => SizedBox(
            height: 60,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (err, _) => SizedBox(height: 40, child: Center(child: Text('$err'))),
          data: (s) {
            final total = (s['total'] as num?)?.toInt() ?? 0;
            final stats = <(String, int)>[
              (l10n.profileScoreBooksAdded, (s['books_added'] as num?)?.toInt() ?? 0),
              (l10n.profileScoreAuthorsAdded, (s['authors_added'] as num?)?.toInt() ?? 0),
              (l10n.profileScoreReviews, (s['reviews_written'] as num?)?.toInt() ?? 0),
              (l10n.profileScoreTracked, (s['books_tracked'] as num?)?.toInt() ?? 0),
              (l10n.profileScoreFinished, (s['books_finished'] as num?)?.toInt() ?? 0),
              (l10n.profileScoreLending, (s['lending_records'] as num?)?.toInt() ?? 0),
            ];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.profileScoreHeader,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: AppColors.inkSoft, letterSpacing: 1),
                ),
                SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '$total',
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                            color: AppColors.oxblood,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    SizedBox(width: 6),
                    Text(
                      l10n.profileScorePoints(total),
                      style: TextStyle(color: AppColors.inkSoft, fontSize: 13),
                    ),
                  ],
                ),
                Divider(height: 18),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (label, value) in stats) _StatPill(label: label, value: value),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final active = value > 0;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: active ? AppColors.goldSoft : AppColors.paperDeep,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$value',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: active ? AppColors.oxblood : AppColors.inkSoft,
              fontSize: 13,
            ),
          ),
          SizedBox(width: 5),
          Text(label, style: TextStyle(color: AppColors.inkSoft, fontSize: 12)),
        ],
      ),
    );
  }
}

/// Set/change the optional unique username, with a live availability check.
class _UsernameSheet extends ConsumerStatefulWidget {
  const _UsernameSheet({required this.current});

  final String? current;

  @override
  ConsumerState<_UsernameSheet> createState() => _UsernameSheetState();
}

enum _NameStatus { idle, checking, available, taken, invalid }

class _UsernameSheetState extends ConsumerState<_UsernameSheet> {
  late final TextEditingController _controller = TextEditingController(text: widget.current ?? '');
  Timer? _debounce;
  _NameStatus _status = _NameStatus.idle;
  bool _saving = false;

  static final _re = RegExp(r'^[a-z][a-z0-9_]{2,19}$');

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String raw) {
    final value = raw.trim().toLowerCase();
    _debounce?.cancel();
    if (value == (widget.current ?? '')) {
      setState(() => _status = _NameStatus.idle);
      return;
    }
    if (!_re.hasMatch(value)) {
      setState(() => _status = _NameStatus.invalid);
      return;
    }
    setState(() => _status = _NameStatus.checking);
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final available = await ref.read(apiClientProvider).usernameAvailable(value);
        if (mounted && _controller.text.trim().toLowerCase() == value) {
          setState(() => _status = available ? _NameStatus.available : _NameStatus.taken);
        }
      } catch (_) {
        if (mounted) setState(() => _status = _NameStatus.idle);
      }
    });
  }

  Future<void> _save() async {
    final value = _controller.text.trim().toLowerCase();
    setState(() => _saving = true);
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(apiClientProvider).updateMe({'username': value});
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.usernameSaved)));
        Navigator.of(context).pop(true);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _status = _NameStatus.taken;
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final canSave = _status == _NameStatus.available && !_saving;
    final (hint, hintColor) = switch (_status) {
      _NameStatus.available => (l10n.usernameAvailable, AppColors.moss),
      _NameStatus.taken => (l10n.usernameTaken, AppColors.oxblood),
      _NameStatus.invalid => (l10n.usernameInvalid, AppColors.inkSoft),
      _ => (l10n.usernameInvalid, AppColors.inkSoft),
    };

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.usernameSheetTitle, style: Theme.of(context).textTheme.titleLarge),
          SizedBox(height: 4),
          Text(l10n.profileUsernameHint, style: TextStyle(color: AppColors.inkSoft, fontSize: 13)),
          SizedBox(height: 14),
          TextField(
            controller: _controller,
            autofocus: true,
            autocorrect: false,
            textInputAction: TextInputAction.done,
            onChanged: _onChanged,
            onSubmitted: (_) => canSave ? _save() : null,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.ink),
            decoration: InputDecoration(
              prefixText: '@',
              hintText: l10n.usernameFieldHint,
              filled: true,
              fillColor: AppColors.card,
              suffixIcon: _status == _NameStatus.checking
                  ? Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : _status == _NameStatus.available
                      ? Icon(Icons.check_circle, color: AppColors.moss)
                      : _status == _NameStatus.taken
                          ? Icon(Icons.error_outline, color: AppColors.oxblood)
                          : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          if (_status != _NameStatus.idle && _status != _NameStatus.checking)
            Padding(
              padding: EdgeInsets.only(top: 6, left: 4),
              child: Text(hint, style: TextStyle(color: hintColor, fontSize: 12)),
            ),
          SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: canSave ? _save : null,
              child: _saving
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.paper),
                    )
                  : Text(l10n.usernameSave),
            ),
          ),
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

/// Edit the reader's languages — a multi-select over [kLanguages]. At least one
/// must stay selected (an empty set would re-trigger the onboarding gate).
class _LanguagesSheet extends ConsumerStatefulWidget {
  const _LanguagesSheet({required this.current});

  final Set<String> current;

  @override
  ConsumerState<_LanguagesSheet> createState() => _LanguagesSheetState();
}

class _LanguagesSheetState extends ConsumerState<_LanguagesSheet> {
  late final Set<String> _sel = {...widget.current};
  bool _saving = false;

  Future<void> _save() async {
    if (_sel.isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref.read(apiClientProvider).updateMe({'preferred_languages': _sel.toList()});
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.profileLanguagesSheetTitle, style: Theme.of(context).textTheme.titleLarge),
          SizedBox(height: 16),
          LanguageChips(
            selected: _sel,
            onToggle: (lang) => setState(
              () => _sel.contains(lang) ? _sel.remove(lang) : _sel.add(lang),
            ),
          ),
          SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_sel.isEmpty || _saving) ? null : _save,
              child: _saving
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.paper),
                    )
                  : Text(l10n.profileLanguagesSave),
            ),
          ),
        ],
      ),
    );
  }
}

/// A live push-pipeline health readout, so an otherwise-invisible iOS push
/// failure (permission, APNs token, FCM token, API registration) is legible on a
/// real TestFlight device. "Retry" re-runs acquisition; "Copy token" exports the
/// FCM token for a manual test send.
class _PushDiagnosticsTile extends ConsumerWidget {
  const _PushDiagnosticsTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final push = ref.watch(pushServiceProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: ValueListenableBuilder<PushDiagnostics>(
          valueListenable: push.diagnostics,
          builder: (context, d, _) {
            Widget row(String label, String value, {bool ok = true}) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 110,
                        child: Text(label,
                            style: TextStyle(color: AppColors.inkSoft, fontSize: 12.5)),
                      ),
                      Expanded(
                        child: Text(
                          value,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: ok ? null : AppColors.oxblood,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
            final fcm = d.fcmToken;
            final permOk = d.permission == 'authorized' || d.permission == 'provisional';
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.notifications_active_outlined,
                        size: 18, color: AppColors.oxblood),
                    const SizedBox(width: 8),
                    const Text('Push notifications',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
                const Divider(height: 18),
                row('Firebase', d.firebaseAvailable ? 'ready' : 'unavailable',
                    ok: d.firebaseAvailable),
                row('Permission', d.permission, ok: permOk),
                if (Platform.isIOS)
                  row(
                    'APNs token',
                    d.apnsToken == null ? 'checking…' : (d.apnsToken! ? 'present' : 'MISSING'),
                    ok: d.apnsToken ?? true,
                  ),
                row(
                  'FCM token',
                  fcm != null
                      ? '${fcm.substring(0, fcm.length < 12 ? fcm.length : 12)}…'
                      : (d.checking ? 'checking…' : 'none'),
                  ok: fcm != null || d.checking,
                ),
                row('Registered', d.registered ? 'yes' : 'no', ok: d.registered || d.checking),
                if (d.lastError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(d.lastError!,
                        style: TextStyle(color: AppColors.oxblood, fontSize: 11.5)),
                  ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () => push.refresh(),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Retry'),
                    ),
                    if (fcm != null)
                      TextButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: fcm));
                          Haptics.selection();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('FCM token copied')),
                          );
                        },
                        icon: const Icon(Icons.copy, size: 16),
                        label: const Text('Copy token'),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
