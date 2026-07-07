import UserNotifications

/// Notification Service Extension — lets remote (FCM) notifications show a rich
/// image (the book cover). iOS invokes this for any push with `mutable-content: 1`;
/// we pull the image URL out of the FCM payload (`fcm_options.image`), download it,
/// and attach it so the banner/expanded notification shows the cover.
class NotificationService: UNNotificationServiceExtension {
  var contentHandler: ((UNNotificationContent) -> Void)?
  var bestAttempt: UNMutableNotificationContent?

  override func didReceive(
    _ request: UNNotificationRequest,
    withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
  ) {
    self.contentHandler = contentHandler
    bestAttempt = request.content.mutableCopy() as? UNMutableNotificationContent
    guard let bestAttempt = bestAttempt else {
      contentHandler(request.content)
      return
    }

    // FCM delivers the image URL under fcm_options.image; fall back to a plain
    // "image" key just in case.
    let info = request.content.userInfo
    var urlString: String?
    if let fcm = info["fcm_options"] as? [String: Any], let img = fcm["image"] as? String {
      urlString = img
    } else if let img = info["image"] as? String {
      urlString = img
    }

    guard let urlString = urlString, let url = URL(string: urlString) else {
      contentHandler(bestAttempt)
      return
    }

    let task = URLSession.shared.downloadTask(with: url) { location, _, _ in
      defer { contentHandler(bestAttempt) }
      guard let location = location else { return }
      // Preserve the file extension so UNNotificationAttachment infers the type.
      let name = UUID().uuidString + "-" + url.lastPathComponent
      let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(name)
      try? FileManager.default.moveItem(at: location, to: tmp)
      if let attachment = try? UNNotificationAttachment(identifier: "cover", url: tmp, options: nil) {
        bestAttempt.attachments = [attachment]
      }
    }
    task.resume()
  }

  override func serviceExtensionTimeWillExpire() {
    // The system is about to kill us — hand back whatever we have.
    if let contentHandler = contentHandler, let bestAttempt = bestAttempt {
      contentHandler(bestAttempt)
    }
  }
}
