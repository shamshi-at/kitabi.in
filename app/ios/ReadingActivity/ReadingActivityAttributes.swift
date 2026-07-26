import ActivityKit
import Foundation

/// The shape of the reading Live Activity, compiled into **both** the app
/// (which starts/updates/ends it) and the widget extension (which draws it).
/// One file, two targets — the two sides have to agree on this type exactly,
/// so it must never be duplicated.
///
/// `startedAt` lives in the static attributes rather than the content state
/// because it never changes for the life of a sitting: the lock-screen clock
/// is a SwiftUI `Text(timerInterval:)`, which counts on its own from that
/// instant without the app pushing an update every second (the same
/// let-the-system-tick-it trick Android's notification chronometer uses).
@available(iOS 16.2, *)
struct ReadingActivityAttributes: ActivityAttributes {
  /// Only what can actually change mid-sitting: the page. The elapsed time
  /// isn't here on purpose — see the note above.
  struct ContentState: Codable, Hashable {
    var currentPage: Int?
    var pageCount: Int?
  }

  var title: String
  var author: String?
  var startedAt: Date

  /// Which sitting this is — the widget turns it into the deep link that
  /// opens this book's timer when the card is tapped.
  var libraryEntryId: String
}
