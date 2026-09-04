import '../../data/api/api_client.dart';

/// The two halves of a cover read, both already in flight.
///
/// Splitting them is the whole point: the identity fields (title, authors,
/// publisher, series, language, type, ISBN) are a few dozen tokens and come
/// back in a second or two, while the back-cover blurb is up to 150 words —
/// and in Malayalam that tokenizes to well over a thousand, which is most of
/// the wait. Asked for together, the title the reader is staring at arrives
/// behind a paragraph they haven't asked for yet.
///
/// So the form awaits [identity], fills what it can, drops its spinner, and
/// lets [description] land behind it into a Description field the reader is
/// unlikely to have started typing in yet (and which `_applyExtracted` won't
/// clobber if they have).
class CoverExtractParts {
  const CoverExtractParts({required this.identity, required this.description});

  /// Title, authors, publisher, series, language, type, ISBN.
  final Future<Map<String, dynamic>> identity;

  /// The back-cover blurb. **Never throws** — it is a bonus that arrives after
  /// the reader already has their fields, so a failure here resolves empty
  /// rather than raising a second error over a form that looks fine. An empty
  /// map is also what a photo set with no back cover gets, with no request
  /// made at all.
  final Future<Map<String, dynamic>> description;
}

/// Start both halves of a cover read at once.
///
/// Both requests leave together, so the blurb is already being transcribed
/// while the reader reads the title. Returns immediately — the caller awaits
/// the futures in the order it wants to render them.
///
/// The blurb request goes out whether or not there is a back cover: the server
/// reads the back when there is one and falls back to the front when there
/// isn't, which is what a single-photo read already does today.
CoverExtractParts startCoverExtract(
  ApiClient api, {
  String? frontUrl,
  String? backUrl,
}) {
  return CoverExtractParts(
    identity: api.extractFromCovers(
      frontUrl: frontUrl,
      backUrl: backUrl,
      part: 'identity',
    ),
    // The blurb only needs one side, so the front is sent only when it is the
    // only photo there is — that is what keeps the split from paying for both
    // images twice.
    // `catchError` is attached here rather than at the await: this future is
    // created now but awaited several frames later, and an unhandled rejection
    // in between is an uncaught async error, not a caught one.
    description: api
        .extractFromCovers(
          frontUrl: backUrl == null ? frontUrl : null,
          backUrl: backUrl,
          part: 'description',
        )
        .catchError((_) => const <String, dynamic>{}),
  );
}
