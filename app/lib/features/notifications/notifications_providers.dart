import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/api_client.dart';

/// The in-app inbox (owner request, 14 Oct 2026): every reader-to-reader
/// notification, kept by the server when it sends the push, so it can be found
/// again after the banner is gone — and on every device, including the ones
/// the push never reached. Online-only like connections: nothing here is
/// synced or queued.
class InboxItem {
  const InboxItem({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.data,
    this.imageUrl,
    this.createdAt,
    required this.read,
    this.actorId,
    this.actorName,
    this.actorAvatarUrl,
  });

  static InboxItem? fromJson(Map<String, dynamic> j) {
    final id = j['id'];
    if (id is! String) return null;
    final actor = j['actor'];
    final a = actor is Map
        ? Map<String, dynamic>.from(actor)
        : const <String, dynamic>{};
    final data = j['data'];
    return InboxItem(
      id: id,
      type: j['type'] as String? ?? '',
      title: j['title'] as String? ?? '',
      body: j['body'] as String? ?? '',
      data: {
        if (data is Map)
          for (final e in data.entries)
            if (e.value != null) '${e.key}': '${e.value}',
      },
      imageUrl: j['image_url'] as String?,
      createdAt: j['created_at'] is String
          ? DateTime.tryParse(j['created_at'] as String)
          : null,
      read: j['read'] == true,
      actorId: a['id'] as String?,
      actorName: a['name'] as String?,
      actorAvatarUrl: a['avatar_url'] as String?,
    );
  }

  final String id;
  final String type;
  final String title;
  final String body;

  /// The push's own data — a tap routes with the same rule ([pushTapRoute]).
  final Map<String, dynamic> data;
  final String? imageUrl;
  final DateTime? createdAt;
  final bool read;
  final String? actorId;
  final String? actorName;
  final String? actorAvatarUrl;

  InboxItem asRead() => InboxItem(
    id: id,
    type: type,
    title: title,
    body: body,
    data: data,
    imageUrl: imageUrl,
    createdAt: createdAt,
    read: true,
    actorId: actorId,
    actorName: actorName,
    actorAvatarUrl: actorAvatarUrl,
  );
}

class Inbox {
  const Inbox({this.unread = 0, this.items = const []});

  factory Inbox.fromJson(Map<String, dynamic> j) => Inbox(
    unread: (j['unread'] as num?)?.toInt() ?? 0,
    items: [
      if (j['items'] is List)
        for (final row in j['items'] as List)
          if (row is Map) ?InboxItem.fromJson(Map<String, dynamic>.from(row)),
    ],
  );

  final int unread;
  final List<InboxItem> items;
}

/// The full list, for the inbox screen.
final inboxProvider = FutureProvider.autoDispose<Inbox>((ref) async {
  final body = await ref.watch(apiClientProvider).getNotifications();
  return Inbox.fromJson(body);
});

/// The number on the bell. Re-read on resume, on every push and after any
/// change made in the inbox. A failure (offline, an API that predates the
/// inbox) is a quiet zero — the bell is never an error.
final unreadNotificationsProvider = FutureProvider<int>((ref) async {
  try {
    return await ref.watch(apiClientProvider).getUnreadNotifications();
  } catch (_) {
    return 0;
  }
});
