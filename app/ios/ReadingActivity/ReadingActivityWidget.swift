import ActivityKit
import SwiftUI
import WidgetKit

/// The Reading Room palette, hard-coded here because a widget extension is a
/// separate binary — it can't reach the Flutter app's theme. Kept in step with
/// `docs/screen-design.md` and `lib/core/theme/app_theme.dart` by hand; these
/// five are the only ones the lock-screen card uses.
private enum Ink {
  static let paper = Color(red: 0.965, green: 0.941, blue: 0.890)
  static let ink = Color(red: 0.169, green: 0.129, blue: 0.094)
  static let inkSoft = Color(red: 0.478, green: 0.416, blue: 0.333)
  static let oxblood = Color(red: 0.494, green: 0.165, blue: 0.200)
  static let gold = Color(red: 0.722, green: 0.525, blue: 0.169)
}

@available(iOS 16.2, *)
private struct ReadingClock: View {
  let startedAt: Date
  let font: Font

  var body: some View {
    // The system renders and ticks this — the app is not woken once a second
    // to keep the lock screen honest.
    Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
      .font(font)
      .monospacedDigit()
      .foregroundColor(Ink.oxblood)
  }
}

@available(iOS 16.2, *)
private struct ProgressLine: View {
  let state: ReadingActivityAttributes.ContentState

  private var text: String? {
    if let page = state.currentPage, let total = state.pageCount, total > 0 {
      return "p. \(page) of \(total)"
    }
    if let page = state.currentPage { return "p. \(page)" }
    return nil
  }

  var body: some View {
    if let text {
      Text(text)
        .font(.system(size: 12))
        .foregroundColor(Ink.inkSoft)
    }
  }
}

/// The lock-screen card: a gold rule, the book, the clock. Deliberately quiet —
/// the Reading Room voice on a surface the reader sees without asking for it.
@available(iOS 16.2, *)
private struct LockScreenCard: View {
  let context: ActivityViewContext<ReadingActivityAttributes>

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      Rectangle()
        .fill(Ink.gold)
        .frame(width: 3)
        .cornerRadius(2)
      VStack(alignment: .leading, spacing: 2) {
        Text(context.attributes.title)
          .font(.system(size: 15, weight: .semibold, design: .serif))
          .foregroundColor(Ink.ink)
          .lineLimit(1)
        if let author = context.attributes.author, !author.isEmpty {
          Text(author)
            .font(.system(size: 11))
            .foregroundColor(Ink.inkSoft)
            .lineLimit(1)
        }
        ProgressLine(state: context.state)
      }
      Spacer(minLength: 6)
      VStack(alignment: .trailing, spacing: 1) {
        ReadingClock(startedAt: context.attributes.startedAt, font: .system(size: 22, weight: .semibold, design: .serif))
        Text("READING")
          .font(.system(size: 8, weight: .bold))
          .tracking(1.2)
          .foregroundColor(Ink.inkSoft)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
  }
}

/// Where a tap goes: this book's running timer. The custom scheme is the one
/// already declared in the app's `CFBundleURLTypes`; `reading-timer` is its own
/// host so it can never be confused with the Supabase OAuth callback that
/// shares the scheme. `DeepLinkListener` on the Dart side turns it into the
/// `/reading-timer/:id` route.
@available(iOS 16.2, *)
private func timerURL(_ libraryEntryId: String) -> URL? {
  guard !libraryEntryId.isEmpty else { return nil }
  return URL(string: "in.kitabi.kitabi://reading-timer/\(libraryEntryId)")
}

@available(iOS 16.2, *)
struct ReadingActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: ReadingActivityAttributes.self) { context in
      LockScreenCard(context: context)
        .activityBackgroundTint(Ink.paper)
        .activitySystemActionForegroundColor(Ink.oxblood)
        .widgetURL(timerURL(context.attributes.libraryEntryId))
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Image(systemName: "book.closed.fill")
            .foregroundColor(Ink.gold)
        }
        DynamicIslandExpandedRegion(.trailing) {
          ReadingClock(startedAt: context.attributes.startedAt, font: .system(size: 16, weight: .semibold, design: .serif))
        }
        DynamicIslandExpandedRegion(.center) {
          VStack(spacing: 1) {
            Text(context.attributes.title)
              .font(.system(size: 13, weight: .semibold, design: .serif))
              .lineLimit(1)
            ProgressLine(state: context.state)
          }
        }
      } compactLeading: {
        Image(systemName: "book.closed.fill")
          .foregroundColor(Ink.gold)
      } compactTrailing: {
        ReadingClock(startedAt: context.attributes.startedAt, font: .system(size: 13, weight: .medium))
      } minimal: {
        Image(systemName: "book.closed.fill")
          .foregroundColor(Ink.gold)
      }
      .widgetURL(timerURL(context.attributes.libraryEntryId))
      .keylineTint(Ink.gold)
    }
  }
}

@main
struct ReadingActivityBundle: WidgetBundle {
  var body: some Widget {
    ReadingActivityWidget()
  }
}
