import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/haptics.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/sheet_grabber.dart';
import '../../../data/api/api_client.dart';
import '../../../l10n/app_localizations.dart';
import '../../profile/providers/profile_providers.dart';
import '../circle_providers.dart';

/// The ask (mockup 3a): what to share with your circle. Reached from Home's
/// invitation, never a pop-up at launch. Every box **starts unticked** — a
/// rating given privately must not become attributed without a fresh yes —
/// and each names the sentence a friend would actually see, so consent is to
/// something concrete.
Future<void> showCircleShareSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    // Over the bottom nav, not under it — Home's invitation opens this from
    // inside the tab shell, whose navigator stops above the bar.
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: AppColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => const _CircleShareSheet(),
  );
}

class _CircleShareSheet extends ConsumerStatefulWidget {
  const _CircleShareSheet();

  @override
  ConsumerState<_CircleShareSheet> createState() => _CircleShareSheetState();
}

class _CircleShareSheetState extends ConsumerState<_CircleShareSheet> {
  var _reading = false;
  var _ratings = false;
  var _owned = false;
  var _saving = false;

  bool get _anything => _reading || _owned;

  Future<void> _save() async {
    setState(() => _saving = true);
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(apiClientProvider).updateMe({
        'circle_share_reading': _reading,
        // Ratings ride on reading; never store a yes the server would ignore.
        'circle_share_ratings': _reading && _ratings,
        'circle_share_owned': _owned,
      });
      Haptics.success();
      ref.invalidate(meProvider);
      ref.invalidate(circlePickProvider);
      navigator.pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.profileVisibilitySaveError)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SheetGrabber(),
            Text(
              l10n.circleShareTitle,
              style: GoogleFonts.fraunces(
                fontSize: 21,
                height: 1.25,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.circleShareIntro,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: AppColors.inkSoft,
              ),
            ),
            const SizedBox(height: 8),
            _Choice(
              title: l10n.circleShareReading,
              hint: l10n.circleShareReadingHint,
              value: _reading,
              onChanged: (v) => setState(() => _reading = v),
            ),
            Divider(height: 1, color: AppColors.line),
            _Choice(
              title: l10n.circleShareRatings,
              hint: l10n.circleShareRatingsHint,
              value: _reading && _ratings,
              onChanged: _reading ? (v) => setState(() => _ratings = v) : null,
            ),
            Divider(height: 1, color: AppColors.line),
            _Choice(
              title: l10n.circleShareOwned,
              hint: l10n.circleShareOwnedHint,
              value: _owned,
              onChanged: (v) => setState(() => _owned = v),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.paperDeep,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                l10n.circleShareNever,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.45,
                  color: AppColors.inkSoft,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.circleShareReciprocity,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.45,
                color: AppColors.inkSoft,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _anything && !_saving ? _save : null,
                child: Text(l10n.circleShareSave),
              ),
            ),
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.circleShareNotNow),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.title,
    required this.hint,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String hint;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return InkWell(
      onTap: enabled ? () => onChanged!(!value) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: value,
              onChanged: enabled ? (v) => onChanged!(v ?? false) : null,
              activeColor: AppColors.moss,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Opacity(
                opacity: enabled ? 1 : 0.5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hint,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.4,
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
