import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/haptics.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/net_image.dart';
import '../../../core/widgets/sheet_grabber.dart';
import '../../../data/api/api_client.dart';
import '../../../l10n/app_localizations.dart';
import '../../profile/providers/profile_providers.dart';
import '../circle_models.dart';
import '../circle_providers.dart';

/// "Your circle" surfaces (docs/circle-reading-mockups.html). Everything here
/// renders only what the server already decided may be seen; there is no
/// filtering in the app, so nothing private can leak from a widget.

// A person's tint is derived from them, the way a generated cover's colour is
// derived from its book — stable across screens, so a face is recognisable.
const _avatarTints = [
  Color(0xFF7E2A33),
  Color(0xFF43617E),
  Color(0xFF48663F),
  Color(0xFF8F681E),
  Color(0xFF6B4E7A),
  Color(0xFF5C3A24),
];

Color _tintFor(String id) =>
    _avatarTints[id.hashCode.abs() % _avatarTints.length];

String _initial(String name) {
  final trimmed = name.replaceFirst('@', '').trim();
  return trimmed.isEmpty ? '·' : trimmed.characters.first.toUpperCase();
}

/// One face: photo when there is one, else an initial on the person's tint.
/// The paper ring is what lets a row of them overlap legibly.
class CircleFace extends StatelessWidget {
  const CircleFace({
    super.key,
    required this.id,
    required this.name,
    this.avatarUrl,
    this.size = 18,
    this.ring = true,
  });

  CircleFace.of(CirclePerson p, {super.key, this.size = 18, this.ring = true})
    : id = p.userId,
      name = p.name,
      avatarUrl = p.avatarUrl;

  final String id;
  final String name;
  final String? avatarUrl;
  final double size;
  final bool ring;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: ring
            ? Border.all(color: AppColors.card, width: size > 20 ? 2 : 1.5)
            : null,
      ),
      child: CircleAvatar(
        backgroundColor: _tintFor(id),
        foregroundImage: avatarUrl != null
            ? netImageProvider(avatarUrl!)
            : null,
        child: Text(
          _initial(name),
          style: TextStyle(
            color: const Color(0xFFFFF7E6),
            fontSize: size * 0.42,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// Overlapping faces, with a "+N" disc when there are more than fit.
class CircleFaces extends StatelessWidget {
  const CircleFaces({
    super.key,
    required this.people,
    this.size = 18,
    this.max = 4,
    this.extra = 0,
  });

  final List<CircleFace> people;
  final double size;
  final int max;

  /// People beyond [people] the server counted but didn't send.
  final int extra;

  @override
  Widget build(BuildContext context) {
    final shown = people.take(max).toList();
    final more = extra + (people.length - shown.length);
    final step = size * 0.68;
    final count = shown.length + (more > 0 ? 1 : 0);
    if (count == 0) return const SizedBox.shrink();
    return SizedBox(
      width: size + step * (count - 1),
      height: size,
      child: Stack(
        children: [
          for (final (i, face) in shown.indexed)
            Positioned(left: step * i, child: face),
          if (more > 0)
            Positioned(
              left: step * shown.length,
              child: Container(
                width: size,
                height: size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.paperDeep,
                  border: Border.all(color: AppColors.card, width: 1.5),
                ),
                child: Text(
                  '+$more',
                  style: TextStyle(
                    fontSize: size * 0.36,
                    fontWeight: FontWeight.w700,
                    color: AppColors.inkSoft,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The one line under a search row (mockup 1a). Priority: read it (with
/// names) › reading now › has a copy. A row with nothing to say gets nothing.
class CircleSearchLine extends StatelessWidget {
  const CircleSearchLine({super.key, required this.signal});

  final CircleSignal signal;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final List<CirclePerson> faces;
    final String text;
    Color accent = AppColors.ink;
    if (signal.readCount > 0) {
      faces = signal.readers;
      final names = signal.readers.map((p) => p.shortName).toList();
      final more = signal.readCount - 2;
      text = switch (signal.readCount) {
        1 => l10n.circleSearchReadOne(names.first),
        2 when names.length >= 2 => l10n.circleSearchReadTwo(
          names[0],
          names[1],
        ),
        _ when names.length >= 2 => l10n.circleSearchReadMany(
          names[0],
          names[1],
          more,
        ),
        _ => l10n.circleSearchReadOne(names.first),
      };
    } else if (signal.readingCount > 0) {
      faces = signal.reading;
      accent = AppColors.oxblood;
      text = signal.readingCount == 1
          ? l10n.circleSearchReading(signal.reading.first.shortName)
          : l10n.circleSearchReadingMany(
              signal.reading.first.shortName,
              signal.readingCount - 1,
            );
    } else if (signal.ownsCount > 0) {
      faces = signal.owners;
      accent = AppColors.goldInk;
      final owner = signal.owners.first;
      text = !signal.canAsk
          ? l10n.circleHasACopy(owner.shortName)
          : owner.asked
          ? l10n.circleSearchAsked(owner.shortName)
          : l10n.circleSearchOwns(owner.shortName);
    } else {
      return const SizedBox.shrink();
    }
    final stars = signal.readCount > 0 && signal.avgRating != null
        ? ' · ★ ${signal.avgRating!.toStringAsFixed(1)}'
        : '';
    return Padding(
      padding: const EdgeInsets.only(top: 3, bottom: 2),
      child: Row(
        children: [
          CircleFaces(
            people: [for (final p in faces) CircleFace.of(p, size: 16)],
            size: 16,
            max: 3,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '$text$stars',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Stars as text — the circle's own figures, kept apart from the catalogue's.
String _stars(int value) => '★' * value + '☆' * (5 - value);

/// The book page's circle (mockups 1b and 1c). [myStatus] is the reader's own
/// status on this book, or null when it isn't on their shelf: null shows the
/// full card under the cover, anything else the compact strip above the tabs.
/// While the reader is mid-way through ('reading') the circle's stars and
/// review lines stay folded behind a tap — a friend's five stars halfway
/// through is pressure, a two-star is a spoiler of mood.
class BookCircleSection extends ConsumerWidget {
  const BookCircleSection({
    super.key,
    required this.workId,
    required this.title,
    this.myStatus,
    this.padding = EdgeInsets.zero,
  });

  final String workId;
  final String title;
  final String? myStatus;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final answer = ref.watch(circleWorkProvider(workId)).valueOrNull;
    final circle = answer == null || answer.canAsk
        ? answer
        : answer.withoutCopies();
    // Silence is the empty state: no connections, nobody sharing, the reader
    // not sharing (the invitation lives on Home), offline — all the same here.
    if (circle == null || circle.invite != null || circle.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: padding,
      child: myStatus == null
          ? _CircleCard(circle: circle, title: title)
          : _CircleStrip(circle: circle, title: title, myStatus: myStatus!),
    );
  }
}

class _CircleCard extends StatelessWidget {
  const _CircleCard({required this.circle, required this.title});

  final CircleWork circle;
  final String title;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final readers = circle.readers;
    final reading = circle.readingNow;
    final owners = circle.owners;
    final String headline;
    if (circle.readCount > 0) {
      headline = l10n.circleHeadlineRead(circle.readCount);
    } else if (reading.isNotEmpty) {
      headline = l10n.circleHeadlineReading(reading.first.shortName);
    } else if (owners.isNotEmpty) {
      headline = l10n.circleHeadlineOwns(owners.first.shortName);
    } else {
      headline = l10n.circleTranslationsOnly;
    }
    final subParts = [
      if (circle.readCount > 0 && circle.avgRating != null)
        l10n.circleTheyGaveIt(circle.avgRating!.toStringAsFixed(1)),
      if (circle.readCount > 0 && reading.isNotEmpty)
        l10n.circleAlsoReading(reading.first.shortName),
    ];
    final quoted = readers.where((p) => p.review != null).firstOrNull;
    // No lending door on a book the reader already has (owner request,
    // 14 Oct 2026) — "has a copy" means nothing to someone holding one.
    final lender = circle.canAsk ? owners.firstOrNull : null;
    final faces = [
      ...readers,
      ...reading,
      ...owners.where((p) => p.status == null),
    ];

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () =>
          showCircleSheet(context, circle: circle, title: title, folded: false),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Gold, because "ask Faisal" *is* lending — the same accent.
            Container(height: 3, color: AppColors.gold),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        l10n.circleEyebrow.toUpperCase(),
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.3,
                          color: AppColors.goldInk,
                        ),
                      ),
                      const Spacer(),
                      if (circle.people.length > 1)
                        Text(
                          l10n.circleSeeAll(circle.people.length),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.oxblood,
                          ),
                        ),
                    ],
                  ),
                  if (faces.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    CircleFaces(
                      people: [
                        for (final p in faces) CircleFace.of(p, size: 26),
                      ],
                      size: 26,
                      max: 5,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    headline,
                    style: GoogleFonts.fraunces(
                      fontSize: 16,
                      height: 1.25,
                      color: AppColors.ink,
                    ),
                  ),
                  if (subParts.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subParts.join(' · '),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.inkSoft,
                        ),
                      ),
                    ),
                  if (quoted != null) ...[
                    Divider(height: 18, color: AppColors.line),
                    _Quote(person: quoted),
                  ],
                  if (lender != null) ...[
                    const SizedBox(height: 10),
                    _LendRow(person: lender, title: title),
                  ],
                  for (final t in circle.translations) ...[
                    const SizedBox(height: 8),
                    _TranslationLine(translation: t),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Quote extends StatelessWidget {
  const _Quote({required this.person});

  final CirclePerson person;

  @override
  Widget build(BuildContext context) {
    final finished = person.finishedOn;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleFace.of(person, size: 22, ring: false),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '“${person.review}”',
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.fraunces(
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  height: 1.4,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 3),
              Text.rich(
                TextSpan(
                  style: TextStyle(fontSize: 10.5, color: AppColors.inkSoft),
                  children: [
                    TextSpan(text: person.shortName),
                    if (person.rating != null) ...[
                      const TextSpan(text: ' · '),
                      TextSpan(
                        text: _stars(person.rating!),
                        style: TextStyle(color: AppColors.gold),
                      ),
                    ],
                    if (finished != null)
                      TextSpan(
                        text: ' · ${DateFormat.yMMM().format(finished)}',
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// "Faisal has a copy · Ask to borrow ›" — the lending wedge, on the card.
class _LendRow extends ConsumerWidget {
  const _LendRow({required this.person, required this.title});

  final CirclePerson person;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return Material(
      color: AppColors.goldSoft,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: person.asked
            ? null
            : () => askToBorrow(context, ref, person: person, title: title),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              CircleFace.of(person, size: 22, ring: false),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.circleHasACopy(person.shortName),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    if (person.ownedEditionLabel != null)
                      Text(
                        person.ownedEditionLabel!,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: AppColors.goldInk,
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                person.asked
                    ? '${l10n.circleRequested} ✓'
                    : '${l10n.circleAskToBorrow} ›',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: person.asked ? AppColors.moss : AppColors.oxblood,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TranslationLine extends StatelessWidget {
  const _TranslationLine({required this.translation});

  final CircleTranslation translation;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final names = translation.names.join(' & ');
    final editionId = translation.editionId;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: editionId == null
          ? null
          : () => context.push(
              Routes.bookDetailPath(translation.workId, editionId),
            ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.paperDeep,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.translate, size: 14, color: AppColors.inkSoft),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                l10n.circleTranslationLine(names, translation.title),
                style: TextStyle(fontSize: 11, color: AppColors.ink),
              ),
            ),
            Icon(Icons.chevron_right, size: 14, color: AppColors.inkSoft),
          ],
        ),
      ),
    );
  }
}

/// Mockup 1c — the book is on the reader's shelf, so the circle stops
/// persuading and simply keeps them company.
class _CircleStrip extends ConsumerWidget {
  const _CircleStrip({
    required this.circle,
    required this.title,
    required this.myStatus,
  });

  final CircleWork circle;
  final String title;
  final String myStatus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final folded = myStatus == 'reading';
    final readers = circle.readers;
    final reading = circle.readingNow;
    final me = ref.watch(meProvider).valueOrNull;
    final iRead = myStatus == 'read';
    String text;
    if (readers.isNotEmpty) {
      text = iRead
          ? l10n.circleStripYouAnd(readers.length)
          : l10n.circleStripRead(readers.length);
      final agree = readers.where((p) => p.rating == 5).firstOrNull;
      if (iRead && agree != null) {
        text = '$text · ${l10n.circleStripAgree(agree.shortName)}';
      }
    } else if (reading.isNotEmpty) {
      text = l10n.circleSearchReading(reading.first.shortName);
    } else if (circle.owners.isNotEmpty) {
      text = l10n.circleHasACopy(circle.owners.first.shortName);
    } else {
      text = l10n.circleTranslationsOnly;
    }
    final faces = [
      if (iRead && me != null && me['id'] is String)
        CircleFace(
          id: me['id'] as String,
          name:
              (me['full_name'] as String?) ?? (me['username'] as String?) ?? '',
          avatarUrl: me['avatar_url'] as String?,
        ),
      for (final p in [
        ...readers,
        ...reading,
        ...circle.owners.where((p) => p.status == null),
      ])
        CircleFace.of(p),
    ];
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => showCircleSheet(
          context,
          circle: circle,
          title: title,
          folded: folded,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            children: [
              CircleFaces(people: faces, max: 4),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.inkSoft,
                    height: 1.35,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, size: 16, color: AppColors.inkSoft),
            ],
          ),
        ),
      ),
    );
  }
}

/// The "See all" sheet (mockup 1d): grouped by what each person did, never a
/// feed. Every name is a door to their profile.
Future<void> showCircleSheet(
  BuildContext context, {
  required CircleWork circle,
  required String title,
  required bool folded,
}) {
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
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      builder: (context, scroll) => _CircleSheet(
        circle: circle,
        title: title,
        folded: folded,
        scroll: scroll,
      ),
    ),
  );
}

class _CircleSheet extends StatefulWidget {
  const _CircleSheet({
    required this.circle,
    required this.title,
    required this.folded,
    required this.scroll,
  });

  final CircleWork circle;
  final String title;
  final bool folded;
  final ScrollController scroll;

  @override
  State<_CircleSheet> createState() => _CircleSheetState();
}

class _CircleSheetState extends State<_CircleSheet> {
  late bool _folded = widget.folded;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final c = widget.circle;
    final ownersOnly = c.owners.where((p) => p.status == null).toList();
    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 2),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: AppColors.inkSoft,
        ),
      ),
    );
    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
      children: [
        const SheetGrabber(),
        Text(
          l10n.circleSheetTitle(widget.title),
          style: GoogleFonts.fraunces(fontSize: 19, color: AppColors.ink),
        ),
        const SizedBox(height: 2),
        Text(
          l10n.circleSheetSubtitle,
          style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft),
        ),
        if (_folded)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.circleFoldedNote,
                    style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _folded = false),
                  child: Text(l10n.circleShowAnyway),
                ),
              ],
            ),
          ),
        if (c.readers.isNotEmpty) ...[
          label(l10n.circleSheetRead(c.readers.length)),
          for (final p in c.readers)
            _PersonRow(
              person: p,
              title: widget.title,
              folded: _folded,
              canAsk: c.canAsk,
            ),
        ],
        if (c.readingNow.isNotEmpty) ...[
          label(l10n.circleSheetReading(c.readingNow.length)),
          for (final p in c.readingNow)
            _PersonRow(
              person: p,
              title: widget.title,
              folded: _folded,
              canAsk: c.canAsk,
            ),
        ],
        if (ownersOnly.isNotEmpty) ...[
          label(l10n.circleSheetOwns(ownersOnly.length)),
          for (final p in ownersOnly)
            _PersonRow(
              person: p,
              title: widget.title,
              folded: _folded,
              canAsk: c.canAsk,
            ),
        ],
        for (final t in c.translations) ...[
          const SizedBox(height: 12),
          _TranslationLine(translation: t),
        ],
      ],
    );
  }
}

class _PersonRow extends ConsumerWidget {
  const _PersonRow({
    required this.person,
    required this.title,
    required this.folded,
    required this.canAsk,
  });

  final CirclePerson person;
  final String title;
  final bool folded;

  /// False for a book the reader already has — no ask on any row.
  final bool canAsk;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final p = person;
    final details = <String>[
      if (p.hasRead && p.finishedOn != null)
        l10n.circleFinishedOn(DateFormat.yMMM().format(p.finishedOn!)),
      if (p.isReading && p.startedOn != null)
        l10n.circleStartedOn(DateFormat.MMMd().format(p.startedOn!)),
      if (p.readCount >= 2) l10n.circleReadTimes(p.readCount),
      if (p.owns && p.status != null) l10n.circleOwnsToo,
      if (p.status == null && p.ownedEditionLabel != null) p.ownedEditionLabel!,
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () =>
                context.push(Routes.publicProfilePath(p.userId), extra: p.name),
            child: CircleFace.of(p, size: 32, ring: false),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => context.push(
                    Routes.publicProfilePath(p.userId),
                    extra: p.name,
                  ),
                  child: Text(
                    p.name,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.oxblood,
                    ),
                  ),
                ),
                if (details.isNotEmpty)
                  Text(
                    details.join(' · '),
                    style: TextStyle(fontSize: 11, color: AppColors.inkSoft),
                  ),
                if (!folded && p.review != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '“${p.review}”',
                      style: GoogleFonts.fraunces(
                        fontSize: 12.5,
                        fontStyle: FontStyle.italic,
                        height: 1.4,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                if (p.owns && canAsk && p.asked)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${l10n.circleRequested} ✓',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.moss,
                      ),
                    ),
                  )
                else if (p.owns && canAsk)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () =>
                          askToBorrow(context, ref, person: p, title: title),
                      child: Text('${l10n.circleAskToBorrow} ›'),
                    ),
                  ),
              ],
            ),
          ),
          if (p.status != null)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 2),
              child: folded
                  ? const SizedBox.shrink()
                  : p.rating != null
                  ? Text(
                      _stars(p.rating!),
                      style: TextStyle(color: AppColors.gold, fontSize: 12),
                    )
                  : Text(
                      l10n.circleNoRatingShared,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: AppColors.inkSoft,
                      ),
                    ),
            ),
        ],
      ),
    );
  }
}

/// Ask a connection to lend the copy they share owning. Confirmed first,
/// because it buzzes a friend's phone; the server sends at most one ask a day
/// for the same copy, so a second tap is harmless anyway.
Future<void> askToBorrow(
  BuildContext context,
  WidgetRef ref, {
  required CirclePerson person,
  required String title,
}) async {
  final editionId = person.ownedEditionId;
  if (editionId == null) return;
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final api = ref.read(apiClientProvider);
  // Captured now: the surface that asked may be gone by the time it lands
  // (Home's card is replaced by the next pick), and the refresh must not be.
  final container = ProviderScope.containerOf(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.circleBorrowTitle(person.shortName)),
      content: Text(l10n.circleBorrowBody(title)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l10n.circleBorrowSend),
        ),
      ],
    ),
  );
  if (ok != true) return;
  Haptics.selection();
  try {
    await api.circleBorrowAsk(ownerId: person.userId, editionId: editionId);
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.circleBorrowSent(person.shortName))),
    );
  } on DioException catch (e) {
    final alreadyYours = e.response?.statusCode == 409;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          alreadyYours ? l10n.circleAlreadyYours : l10n.circleBorrowFailed,
        ),
      ),
    );
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.circleBorrowFailed)));
  }
  // Asked from one place, "Requested" everywhere (owner request, 14 Oct 2026):
  // every circle answer the app holds is re-read, not just this screen's.
  refreshCircleAnswers(container);
}

/// Re-read every circle answer the app is holding — after an ask, so the
/// book page, its sheet, search rows and Home's card agree at once.
void refreshCircleAnswers(ProviderContainer container) {
  container.invalidate(circleWorkProvider);
  container.invalidate(circleSignalsProvider);
  container.invalidate(circlePickProvider);
  container.invalidate(borrowAsksProvider);
}
