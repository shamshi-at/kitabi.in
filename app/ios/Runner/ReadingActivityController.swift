import ActivityKit
import Flutter
import Foundation

/// The app half of the reading Live Activity: starts, updates and ends the
/// activity the `ReadingActivity` widget extension draws.
///
/// Everything here is best-effort by design. Live Activities can be off in
/// Settings, unavailable below iOS 16.2, or refused by the system when too
/// many are running — none of which is a reason for the reader's sitting to
/// fail. The Dart side (`reading_live_activity.dart`) swallows errors for the
/// same reason; this side simply doesn't raise them.
enum ReadingActivityController {
  static let channelName = "in.kitabi.kitabi/reading_activity"

  /// Held as `Any?` because a stored property can't carry an `@available`
  /// annotation — the generic `Activity<…>` type only exists on 16.2+.
  private static var current: Any?

  static func register(with registrar: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "start":
        start(call.arguments as? [String: Any] ?? [:])
        result(nil)
      case "update":
        update(call.arguments as? [String: Any] ?? [:])
        result(nil)
      case "end":
        end()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func start(_ args: [String: Any]) {
    guard #available(iOS 16.2, *) else { return }
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
    // One sitting at a time — a stale activity from a session that ended
    // without us hearing about it must never sit next to the new one.
    end()

    let startedAt: Date
    if let seconds = args["startedAt"] as? Double {
      startedAt = Date(timeIntervalSince1970: seconds)
    } else if let seconds = args["startedAt"] as? Int {
      startedAt = Date(timeIntervalSince1970: TimeInterval(seconds))
    } else {
      startedAt = Date()
    }

    let attributes = ReadingActivityAttributes(
      title: args["title"] as? String ?? "",
      author: args["author"] as? String,
      startedAt: startedAt
    )
    let state = ReadingActivityAttributes.ContentState(
      currentPage: args["currentPage"] as? Int,
      pageCount: args["pageCount"] as? Int
    )

    do {
      current = try Activity.request(
        attributes: attributes,
        content: ActivityContent(state: state, staleDate: nil),
        pushType: nil
      )
    } catch {
      current = nil
    }
  }

  private static func update(_ args: [String: Any]) {
    guard #available(iOS 16.2, *),
          let activity = current as? Activity<ReadingActivityAttributes> else { return }
    let state = ReadingActivityAttributes.ContentState(
      currentPage: args["currentPage"] as? Int,
      pageCount: args["pageCount"] as? Int
    )
    Task {
      await activity.update(ActivityContent(state: state, staleDate: nil))
    }
  }

  /// Ends the activity this process started *and* any other reading activity
  /// still alive — a sitting stopped from a background isolate (the check-in's
  /// "No, stop it", the auto-stop task) never reaches this method channel, so
  /// the next foreground start/end has to clean up after it. This is the iOS
  /// half of the reconciliation the Dart side does on resume.
  private static func end() {
    guard #available(iOS 16.2, *) else { return }
    current = nil
    Task {
      for activity in Activity<ReadingActivityAttributes>.activities {
        await activity.end(nil, dismissalPolicy: .immediate)
      }
    }
  }
}
