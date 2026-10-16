/// A calendar date as `/sync/push` sends it: `YYYY-MM-DD`, the reader's
/// **local** day.
///
/// The server's start/finish/lent/due/returned dates are plain Postgres `date`
/// columns — a day, not an instant — so a full timestamp is rejected as
/// invalid_payload (Pydantic accepts a datetime for a `date` only at zero
/// time). The day is the one the reader saw when they picked it. Converting
/// to UTC first, as every call site used to, sent the *previous* day for
/// anything recorded between midnight and 05:30 in IST: a book lent at
/// 01:22 on 13 Oct was stored as lent on 12 Oct, on both sides of the loan.
///
/// The pull reads the string back with `DateTime.parse`, which gives local
/// midnight of that same day, so the value round-trips unchanged.
String wireDate(DateTime d) {
  final local = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year.toString().padLeft(4, '0')}-${two(local.month)}-${two(local.day)}';
}
