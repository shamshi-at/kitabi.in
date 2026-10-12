import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/haptics.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/typeset_cover.dart';
import '../../../data/db/catalog_cache.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../data/sync/sync_providers.dart';
import '../../../l10n/app_localizations.dart';
import '../circle_models.dart';
import '../circle_providers.dart';
import 'circle_share_sheet.dart';
import 'circle_widgets.dart';

/// Home's one "From your circle" card (mockups 2a–2c) — the same discipline as
/// the AI pick: one card, never a feed. It's the pick for today, an invitation
/// for a reader who doesn't share yet (only when some of their connections
/// do), or nothing at all — Home never grows a hole for it.
class CircleHomeCard extends ConsumerWidget {
  const CircleHomeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final response = ref.watch(circlePickProvider).valueOrNull;
    if (response == null) return const SizedBox.shrink();
    final pick = response.pick;
    if (pick != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: _PickCard(pick: pick),
      );
    }
    final invite = response.invite ?? 0;
    if (invite <= 0) return const SizedBox.shrink();
    final dismissals = ref.watch(circleInviteDismissalsProvider).valueOrNull;
    if (dismissals == null || !dismissals.allowsShowing(DateTime.now())) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: _InviteCard(count: invite, dismissals: dismissals),
    );
  }
}

BoxDecoration _letterPaper() => BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      AppColors.card,
      AppColors.dark ? AppColors.card : const Color(0xFFFBF4E2),
    ],
  ),
  borderRadius: BorderRadius.circular(12),
  border: Border.all(color: AppColors.line),
);

class _Eyebrow extends StatelessWidget {
  const _Eyebrow({required this.text, this.onClose});

  final String text;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.3,
            color: AppColors.goldInk,
          ),
        ),
        const Spacer(),
        if (onClose != null)
          InkResponse(
            onTap: onClose,
            radius: 18,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.close, size: 16, color: AppColors.stampGrey),
            ),
          ),
      ],
    );
  }
}

/// The friend's initial as a wax seal — a letter, not an ad.
class _Seal extends StatelessWidget {
  const _Seal({required this.person});

  final CirclePerson person;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: AppColors.card, spreadRadius: 2),
          BoxShadow(
            color: AppColors.gold.withValues(alpha: 0.6),
            spreadRadius: 3,
          ),
        ],
      ),
      child: CircleFace.of(person, size: 34, ring: false),
    );
  }
}

class _PickCard extends ConsumerWidget {
  const _PickCard({required this.pick});

  final CirclePick pick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final person = pick.person;
    final editionId = pick.editionId;
    final title = pick.title;
    final authors = (pick.work['authors'] as List?) ?? const [];
    final author = authors.isNotEmpty && authors.first is Map
        ? (authors.first as Map)['name'] as String?
        : null;

    final String sentence = switch (pick.kind) {
      'borrow' => l10n.circlePickBorrow(person!.shortName, title),
      'read_along' => l10n.circlePickReadAlong(person!.shortName, title),
      'loved' => l10n.circlePickLoved(person!.shortName, title),
      'cluster' => l10n.circlePickCluster(pick.people.length, title),
      'kindred' => l10n.circlePickKindred(
        person!.shortName,
        title,
        person.rating ?? 5,
      ),
      _ => title,
    };

    Future<void> openBook() async {
      if (editionId != null) {
        await context.push(Routes.bookDetailPath(pick.workId, editionId));
      }
    }

    Future<void> wantToRead() async {
      final edition = pick.edition;
      if (editionId == null || edition == null) return;
      Haptics.selection();
      final messenger = ScaffoldMessenger.of(context);
      final container = ProviderScope.containerOf(context);
      await cacheBookForOffline(
        ref.read(appDatabaseProvider),
        pick.work,
        edition,
      );
      final repo = await ref.read(libraryRepositoryProvider.future);
      await repo.add(editionId: editionId, status: 'wishlist');
      messenger.showSnackBar(SnackBar(content: Text(l10n.bookWishlistAdded)));
      // It's on the shelf now — the next card can be about something else.
      await dismissCirclePick(container, pick.workId);
    }

    final lender = person != null && person.owns ? person : null;
    final Widget primary = switch (pick.kind) {
      'borrow' => _CardButton(
        label: l10n.circleAskNameToLend(person!.shortName),
        gold: true,
        onTap: () => askToBorrow(context, ref, person: person, title: title),
      ),
      'read_along' ||
      'kindred' => _CardButton(label: l10n.circleOpenBook, onTap: openBook),
      _ => _CardButton(label: '＋ ${l10n.circleWantToRead}', onTap: wantToRead),
    };

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: openBook,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: _letterPaper(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Eyebrow(
              text: l10n.circleFromYourCircle,
              onClose: () => dismissCirclePick(
                ProviderScope.containerOf(context),
                pick.workId,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (person != null)
                            _Seal(person: person)
                          else
                            CircleFaces(
                              people: [
                                for (final p in pick.people)
                                  CircleFace.of(p, size: 26),
                              ],
                              size: 26,
                              max: 3,
                            ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              sentence,
                              style: GoogleFonts.fraunces(
                                fontSize: 14.5,
                                height: 1.3,
                                color: AppColors.ink,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (pick.kind == 'loved' && person?.rating != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          '${'★' * person!.rating!}  ${l10n.circlePickTheirRating}',
                          style: TextStyle(fontSize: 12, color: AppColors.gold),
                        ),
                      ],
                      if (pick.kind == 'cluster') ...[
                        const SizedBox(height: 6),
                        Text(
                          pick.people.map((p) => p.shortName).join(', '),
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppColors.inkSoft,
                          ),
                        ),
                      ],
                      if (person?.review != null && pick.kind == 'loved') ...[
                        const SizedBox(height: 6),
                        Text(
                          '“${person!.review}”',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.fraunces(
                            fontSize: 12.5,
                            fontStyle: FontStyle.italic,
                            height: 1.4,
                            color: AppColors.ink,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // Tilted slightly, like a book handed across a table.
                Transform.rotate(
                  angle: 0.05,
                  child: TypesetCover(
                    title: title,
                    author: author,
                    coverUrl: pick.edition?['cover_url'] as String?,
                    width: 50,
                    height: 75,
                  ),
                ),
              ],
            ),
            if (pick.kind == 'loved' && pick.alsoReadCount > 0) ...[
              const SizedBox(height: 6),
              Text(
                l10n.circlePickAlsoRead(pick.alsoReadCount),
                style: TextStyle(fontSize: 11, color: AppColors.inkSoft),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: primary),
                if (lender != null && pick.kind != 'borrow') ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: _CardButton(
                      label: l10n.circleAskNameToLend(lender.shortName),
                      gold: true,
                      onTap: () => askToBorrow(
                        context,
                        ref,
                        person: lender,
                        title: title,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CardButton extends StatelessWidget {
  const _CardButton({
    required this.label,
    required this.onTap,
    this.gold = false,
  });

  final String label;
  final Future<void> Function()? onTap;
  final bool gold;

  @override
  Widget build(BuildContext context) {
    final fill = gold ? AppColors.goldSoft : AppColors.oxblood;
    final ink = gold ? AppColors.goldInk : AppColors.paper;
    return Material(
      color: fill,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap == null ? null : () => onTap!(),
        child: Container(
          height: 36,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
        ),
      ),
    );
  }
}

/// Mockup 2c — some connections share and the reader doesn't. The count is
/// of people who already chose to share, so it is theirs to reveal.
class _InviteCard extends ConsumerWidget {
  const _InviteCard({required this.count, required this.dismissals});

  final int count;
  final InviteDismissals dismissals;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: _letterPaper(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Eyebrow(
            text: l10n.circleEyebrow,
            onClose: () async {
              await ref
                  .read(appDatabaseProvider)
                  .keyValuesDao
                  .setValue(
                    circleInviteDismissedKey,
                    dismissals.bumped(DateTime.now()),
                  );
              ref.invalidate(circleInviteDismissalsProvider);
            },
          ),
          const SizedBox(height: 8),
          Text(
            l10n.circleInviteHeadline(count),
            style: GoogleFonts.fraunces(
              fontSize: 15,
              height: 1.3,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.circleInviteBody,
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              color: AppColors.inkSoft,
            ),
          ),
          const SizedBox(height: 10),
          _CardButton(
            label: l10n.circleInviteButton,
            onTap: () => showCircleShareSheet(context),
          ),
        ],
      ),
    );
  }
}
