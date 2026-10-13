/// "Your circle" — the shapes the `/circle` endpoints send
/// (api/app/schemas/circle.py). Parsed eagerly, field by field, so a payload
/// change fails here at the boundary rather than inside some widget's build
/// (CLAUDE.md, 21 Jul 2026), and every field tolerates being absent: an API
/// deployed behind the app is a normal state, not an edge case.
library;

String? _str(Object? v) => v is String && v.isNotEmpty ? v : null;
int _int(Object? v) => v is num ? v.toInt() : 0;
int? _intOrNull(Object? v) => v is num ? v.toInt() : null;
DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v) : null;

List<T> _list<T>(Object? v, T Function(Map<String, dynamic>) parse) => [
  if (v is List)
    for (final row in v)
      if (row is Map) parse(Map<String, dynamic>.from(row)),
];

/// What the signed-in reader shares with their circle, from `/me`. Ratings
/// ride on reading, so sharing ratings alone shares nothing ([any]).
class CircleSharing {
  const CircleSharing({
    required this.reading,
    required this.ratings,
    required this.owned,
  });

  factory CircleSharing.fromMe(Map<String, dynamic> me) => CircleSharing(
    reading: me['circle_share_reading'] == true,
    ratings: me['circle_share_ratings'] == true,
    owned: me['circle_share_owned'] == true,
  );

  final bool reading;
  final bool ratings;
  final bool owned;

  bool get any => reading || owned;
}

/// One connection, as far as they agreed to be seen on one book.
class CirclePerson {
  const CirclePerson({
    required this.userId,
    required this.name,
    this.avatarUrl,
    this.status,
    this.readCount = 0,
    this.finishedOn,
    this.startedOn,
    this.rating,
    this.review,
    this.owns = false,
    this.ownedEditionId,
    this.ownedEditionLabel,
    this.asked = false,
  });

  factory CirclePerson.fromJson(Map<String, dynamic> j) => CirclePerson(
    userId: j['user_id'] as String,
    name: _str(j['name']) ?? '',
    avatarUrl: _str(j['avatar_url']),
    status: _str(j['status']),
    readCount: _int(j['read_count']),
    finishedOn: _date(j['finished_on']),
    startedOn: _date(j['started_on']),
    rating: _intOrNull(j['rating']),
    review: _str(j['review']),
    owns: j['owns'] == true,
    ownedEditionId: _str(j['owned_edition_id']),
    ownedEditionLabel: _str(j['owned_edition_label']),
    asked: j['asked'] == true,
  );

  final String userId;
  final String name;
  final String? avatarUrl;

  /// 'read' | 'reading' | null (shown only because they own a copy).
  final String? status;
  final int readCount;
  final DateTime? finishedOn;
  final DateTime? startedOn;
  final int? rating;
  final String? review;
  final bool owns;
  final String? ownedEditionId;
  final String? ownedEditionLabel;

  /// The reader has an open ask with this owner for this book — every surface
  /// says "Requested" instead of offering to ask again.
  final bool asked;

  bool get hasRead => status == 'read';
  bool get isReading => status == 'reading';

  /// First name — the search line says "Anu, Lakshmi & 2 more".
  String get shortName {
    final trimmed = name.trim();
    if (trimmed.startsWith('@')) return trimmed;
    return trimmed.split(RegExp(r'\s+')).first;
  }
}

/// A search row's one line.
class CircleSignal {
  const CircleSignal({
    this.readCount = 0,
    this.readingCount = 0,
    this.ownsCount = 0,
    this.readers = const [],
    this.reading = const [],
    this.owners = const [],
    this.avgRating,
    this.canAsk = true,
  });

  factory CircleSignal.fromJson(Map<String, dynamic> j) => CircleSignal(
    readCount: _int(j['read_count']),
    readingCount: _int(j['reading_count']),
    ownsCount: _int(j['owns_count']),
    readers: _list(j['readers'], CirclePerson.fromJson),
    reading: _list(j['reading'], CirclePerson.fromJson),
    owners: _list(j['owners'], CirclePerson.fromJson),
    avgRating: (j['avg_rating'] as num?)?.toDouble(),
    canAsk: j['can_ask'] != false,
  );

  final int readCount;
  final int readingCount;
  final int ownsCount;
  final List<CirclePerson> readers;
  final List<CirclePerson> reading;
  final List<CirclePerson> owners;
  final double? avgRating;

  /// See [CircleWork.canAsk].
  final bool canAsk;

  bool get isEmpty => readCount == 0 && readingCount == 0 && ownsCount == 0;

  static Map<String, CircleSignal> parseAll(Map<String, dynamic> body) {
    final raw = body['signals'];
    if (raw is! Map) return const {};
    return {
      for (final e in raw.entries)
        if (e.value is Map)
          e.key as String: CircleSignal.fromJson(
            Map<String, dynamic>.from(e.value as Map),
          ),
    };
  }
}

/// The same book in another language, read by someone in the circle.
class CircleTranslation {
  const CircleTranslation({
    required this.workId,
    this.editionId,
    required this.title,
    this.language,
    required this.readCount,
    required this.names,
  });

  factory CircleTranslation.fromJson(Map<String, dynamic> j) =>
      CircleTranslation(
        workId: j['work_id'] as String,
        editionId: _str(j['edition_id']),
        title: _str(j['title']) ?? '',
        language: _str(j['language']),
        readCount: _int(j['read_count']),
        names: [
          if (j['names'] is List)
            for (final n in j['names'] as List)
              if (n is String) n,
        ],
      );

  final String workId;
  final String? editionId;
  final String title;
  final String? language;
  final int readCount;
  final List<String> names;
}

/// The book page's card and sheet.
class CircleWork {
  const CircleWork({
    this.invite,
    this.people = const [],
    this.readCount = 0,
    this.readingCount = 0,
    this.ownsCount = 0,
    this.avgRating,
    this.translations = const [],
    this.canAsk = true,
  });

  factory CircleWork.fromJson(Map<String, dynamic> j) => CircleWork(
    invite: _intOrNull(j['invite']),
    people: _list(j['people'], CirclePerson.fromJson),
    readCount: _int(j['read_count']),
    readingCount: _int(j['reading_count']),
    ownsCount: _int(j['owns_count']),
    avgRating: (j['avg_rating'] as num?)?.toDouble(),
    translations: _list(j['translations'], CircleTranslation.fromJson),
    canAsk: j['can_ask'] != false,
  );

  /// False when the book is already on one of the reader's shelves (any but
  /// Wishlist): nobody asks to borrow a book they hold or have read.
  final bool canAsk;

  /// Set instead of people when the reader shares nothing themselves.
  final int? invite;
  final List<CirclePerson> people;
  final int readCount;
  final int readingCount;
  final int ownsCount;
  final double? avgRating;
  final List<CircleTranslation> translations;

  /// For a reader who already has the book: who *owns* a copy is no news to
  /// them, so people known only for owning it drop out (readers stay).
  CircleWork withoutCopies() => CircleWork(
    invite: invite,
    people: people.where((p) => p.status != null).toList(),
    readCount: readCount,
    readingCount: readingCount,
    avgRating: avgRating,
    translations: translations,
    canAsk: canAsk,
  );

  List<CirclePerson> get readers => people.where((p) => p.hasRead).toList();
  List<CirclePerson> get readingNow =>
      people.where((p) => p.isReading).toList();
  List<CirclePerson> get owners => people.where((p) => p.owns).toList();

  /// Nothing worth a card: the empty state is silence, never "0 connections".
  bool get isEmpty => people.isEmpty && translations.isEmpty;
}

/// Home's one card.
class CirclePick {
  const CirclePick({
    required this.kind,
    required this.work,
    this.person,
    this.people = const [],
    this.alsoReadCount = 0,
    this.myRating,
  });

  static CirclePick? fromJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    final kind = _str(j['kind']);
    final work = j['work'];
    if (kind == null || work is! Map) return null;
    final person = j['person'];
    return CirclePick(
      kind: kind,
      work: Map<String, dynamic>.from(work),
      person: person is Map
          ? CirclePerson.fromJson(Map<String, dynamic>.from(person))
          : null,
      people: _list(j['people'], CirclePerson.fromJson),
      alsoReadCount: _int(j['also_read_count']),
      myRating: _intOrNull(j['my_rating']),
    );
  }

  /// 'borrow' | 'read_along' | 'loved' | 'cluster' | 'kindred'.
  final String kind;

  /// A `WorkSummaryOut` — the same map every catalog row is built from.
  final Map<String, dynamic> work;
  final CirclePerson? person;
  final List<CirclePerson> people;
  final int alsoReadCount;
  final int? myRating;

  String get workId => work['id'] as String;
  String get title => work['title'] as String? ?? '';
  Map<String, dynamic>? get edition => work['edition'] is Map
      ? Map<String, dynamic>.from(work['edition'] as Map)
      : null;
  String? get editionId => edition?['id'] as String?;
}

/// `GET /circle/pick` — at most one of [invite] and [pick] is meaningful.
class CirclePickResponse {
  const CirclePickResponse({this.invite, this.pick});

  factory CirclePickResponse.fromJson(Map<String, dynamic> j) =>
      CirclePickResponse(
        invite: _intOrNull(j['invite']),
        pick: CirclePick.fromJson(
          j['pick'] is Map ? Map<String, dynamic>.from(j['pick'] as Map) : null,
        ),
      );

  final int? invite;
  final CirclePick? pick;
}

/// One open ask to borrow (`BorrowAskOut`). The person is the other side: who
/// asked, on the owner's list; whom you asked, on the asker's.
class BorrowAsk {
  const BorrowAsk({
    required this.id,
    required this.personId,
    required this.personName,
    this.personUsername,
    this.personAvatarUrl,
    required this.workId,
    required this.editionId,
    required this.title,
    this.author,
    this.coverUrl,
    this.createdAt,
  });

  static BorrowAsk? fromJson(Map<String, dynamic> j) {
    final person = j['person'];
    final id = _str(j['id']);
    final workId = _str(j['work_id']);
    final editionId = _str(j['edition_id']);
    if (person is! Map || id == null || workId == null || editionId == null) {
      return null;
    }
    final p = Map<String, dynamic>.from(person);
    final personId = _str(p['user_id']);
    if (personId == null) return null;
    return BorrowAsk(
      id: id,
      personId: personId,
      personName: _str(p['name']) ?? '',
      personUsername: _str(p['username']),
      personAvatarUrl: _str(p['avatar_url']),
      workId: workId,
      editionId: editionId,
      title: _str(j['title']) ?? '',
      author: _str(j['author']),
      coverUrl: _str(j['cover_url']),
      createdAt: _date(j['created_at']),
    );
  }

  final String id;
  final String personId;
  final String personName;
  final String? personUsername;
  final String? personAvatarUrl;
  final String workId;
  final String editionId;
  final String title;
  final String? author;
  final String? coverUrl;
  final DateTime? createdAt;

  String get personShortName {
    final trimmed = personName.trim();
    if (trimmed.startsWith('@')) return trimmed;
    return trimmed.split(RegExp(r'\s+')).first;
  }
}

class BorrowAsks {
  const BorrowAsks({this.incoming = const [], this.outgoing = const []});

  factory BorrowAsks.fromJson(Map<String, dynamic> j) {
    List<BorrowAsk> parse(Object? v) => [
      if (v is List)
        for (final row in v)
          if (row is Map) ?BorrowAsk.fromJson(Map<String, dynamic>.from(row)),
    ];
    return BorrowAsks(
      incoming: parse(j['incoming']),
      outgoing: parse(j['outgoing']),
    );
  }

  final List<BorrowAsk> incoming;
  final List<BorrowAsk> outgoing;

  bool get isEmpty => incoming.isEmpty && outgoing.isEmpty;
}
