import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// "7:42 PM – 8:31 PM" — the clock span of one sitting, for the book page's
/// reading log. Redundant with [formatDuration] shown beside it (there's no
/// pause, so the span always equals the length), but a range is what a reader
/// recognises: it says *when* the sitting sat in the day, which a bare start
/// plus a length makes you work out.
///
/// A sitting that ran past midnight gets a "(+1)" rather than reading as if it
/// ended in the small hours of the day it started. An end at or before the
/// start — nothing writes one, but a synced row could — degrades to the start
/// alone instead of printing a backwards range.
String formatSessionSpan(
  BuildContext context,
  AppLocalizations l10n, {
  required DateTime startedAt,
  required DateTime endedAt,
}) {
  final materialL10n = MaterialLocalizations.of(context);
  final start = startedAt.toLocal();
  final end = endedAt.toLocal();
  final from = materialL10n.formatTimeOfDay(TimeOfDay.fromDateTime(start));
  if (!end.isAfter(start)) return from;
  final to = materialL10n.formatTimeOfDay(TimeOfDay.fromDateTime(end));
  return DateUtils.isSameDay(start, end)
      ? l10n.bookLogTimeRange(from, to)
      : l10n.bookLogTimeRangeNextDay(from, to);
}

/// "1h 12m" / "34m" / "45s" — the short form used everywhere a reading
/// session's length is shown (book page log, wax seal, mini-bar, Insights).
/// Never a bare number of seconds/minutes — always this compact unit form.
String formatDuration(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  if (hours > 0) return '${hours}h ${minutes}m';
  if (d.inMinutes > 0) return '${d.inMinutes}m';
  return '${d.inSeconds}s';
}

/// "24:07" — the live clock face on the running-timer screen and mini-bar.
String formatClock(Duration d) {
  final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  final hours = d.inHours;
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}
