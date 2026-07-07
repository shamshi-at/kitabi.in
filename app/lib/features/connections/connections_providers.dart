import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/api_client.dart';

/// The other party in a connection — minimal public identity.
class ConnectionUser {
  ConnectionUser({required this.id, this.username, this.fullName});

  factory ConnectionUser.fromJson(Map<String, dynamic> json) => ConnectionUser(
        id: json['id'] as String,
        username: json['username'] as String?,
        fullName: json['full_name'] as String?,
      );

  final String id;
  final String? username;
  final String? fullName;

  /// Prefer the real name; fall back to the @handle.
  String get display {
    final name = fullName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return username != null ? '@$username' : 'Unknown';
  }
}

class Connection {
  Connection({
    required this.id,
    required this.status,
    required this.role,
    required this.other,
  });

  factory Connection.fromJson(Map<String, dynamic> json) => Connection(
        id: json['id'] as String,
        status: json['status'] as String,
        role: json['role'] as String, // requester | addressee
        other: ConnectionUser.fromJson((json['other'] as Map).cast<String, dynamic>()),
      );

  final String id;
  final String status;
  final String role;
  final ConnectionUser other;
}

class ConnectionsData {
  ConnectionsData({
    required this.incoming,
    required this.outgoing,
    required this.accepted,
    this.rejected = const [],
    this.blocked = const [],
  });

  factory ConnectionsData.fromJson(Map<String, dynamic> json) {
    List<Connection> parse(String key) =>
        ((json[key] as List?) ?? const [])
            .map((e) => Connection.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
    return ConnectionsData(
      incoming: parse('incoming'),
      outgoing: parse('outgoing'),
      accepted: parse('accepted'),
      rejected: parse('rejected'),
      blocked: parse('blocked'),
    );
  }

  /// Pending requests addressed to me — the ones needing a decision.
  final List<Connection> incoming;

  /// Pending requests I sent, awaiting the other person.
  final List<Connection> outgoing;

  /// Confirmed both-ways connections.
  final List<Connection> accepted;

  /// Requests I sent that were declined — I can re-send these (until blocked).
  final List<Connection> rejected;

  /// People I've blocked — I can unblock them.
  final List<Connection> blocked;

  /// My standing with a specific user id, or null if there's no connection —
  /// drives the ledger's pending/linked pill. 'accepted' | 'pending_out' |
  /// 'pending_in'.
  String? statusForUser(String userId) {
    if (accepted.any((c) => c.other.id == userId)) return 'accepted';
    if (outgoing.any((c) => c.other.id == userId)) return 'pending_out';
    if (incoming.any((c) => c.other.id == userId)) return 'pending_in';
    if (rejected.any((c) => c.other.id == userId)) return 'rejected';
    return null;
  }

  /// The borrower declined the lender's connection request — the loan stands, but
  /// it can't link to their account until they accept (or it's made a private
  /// contact instead).
  bool isRejected(String userId) => rejected.any((c) => c.other.id == userId);
}

/// The connections inbox + status source. autoDispose so it refetches each time
/// the inbox is opened and after an accept/decline invalidation.
final connectionsProvider = FutureProvider.autoDispose<ConnectionsData>((ref) async {
  final data = await ref.watch(apiClientProvider).getConnections();
  return ConnectionsData.fromJson(data);
});
