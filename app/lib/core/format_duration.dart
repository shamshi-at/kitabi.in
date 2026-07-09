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
