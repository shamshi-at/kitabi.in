import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A monotonic tick bumped each time a footer tab is tapped, so that tab's
/// screen can reset to a fresh top-level state — the first page, never the last
/// visited sub-view (owner request, 19 Jul 2026: tapping Library from a
/// drilled-in shelf should land on "All books", fresh). Per-tab, so tapping one
/// footer item never resets an unrelated screen. `goBranch(initialLocation:
/// true)` only pops nested *routes*; these carry the in-screen state resets
/// (the All-books/Shelves toggle, an opened shelf, filters, the lending tab).
final libraryTabResetProvider = StateProvider<int>((ref) => 0);
final lendingTabResetProvider = StateProvider<int>((ref) => 0);
