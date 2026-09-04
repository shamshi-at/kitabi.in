// What the reader is actually told when a request fails.
//
// `briefError` looked for the server's sentence at `detail.message` — an
// envelope the API does not send. Its own exception handler unwraps
// `HTTPException.detail` onto the response root (api/app/main.py), so every
// structured message ever written was dropped and the reader got a bare
// "HTTP 500" instead. Nothing failed; the fallback simply always won, which is
// why it survived. Found chasing a duplicate-ISBN 409 whose whole value was
// the sentence it carried (4 Sep 2026).
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitabi/core/quiet_error.dart';

DioException _withBody(Object? body, {int status = 409}) {
  final request = RequestOptions(path: '/catalog/works');
  return DioException(
    requestOptions: request,
    response: Response<Object?>(
      requestOptions: request,
      statusCode: status,
      data: body,
    ),
  );
}

void main() {
  test('the flat shape our API actually sends reaches the reader', () {
    final err = _withBody({
      'code': 'isbn_exists',
      'message': 'Dharmapuranam is already in the catalogue with this ISBN.',
      'work_id': '62ab34ad-6957-4f3f-bd5b-a55bbdabab26',
    });
    expect(
      briefError(err),
      'Dharmapuranam is already in the catalogue with this ISBN.',
    );
  });

  test("FastAPI's own nested shape still works", () {
    final err = _withBody({
      'detail': {'code': 'not_found', 'message': 'Work not found'},
    }, status: 404);
    expect(briefError(err), 'Work not found');
  });

  test('a 422 whose detail is a list falls back rather than crashing', () {
    // Pydantic validation errors arrive as {"detail": [ ... ]} — a List, not a
    // Map. Indexing it with a String would throw inside an error handler, which
    // is the worst place in the app to throw.
    final err = _withBody({
      'detail': [
        {'loc': ['body', 'title'], 'msg': 'Field required'},
      ],
    }, status: 422);
    expect(briefError(err), 'HTTP 422');
  });

  test('a body with no message at all still says something', () {
    expect(briefError(_withBody({'code': 'error'}, status: 500)), 'HTTP 500');
    expect(briefError(_withBody('plain text', status: 502)), 'HTTP 502');
  });

  test('an empty message is not preferred over the status code', () {
    expect(briefError(_withBody({'message': ''}, status: 500)), 'HTTP 500');
  });

  test('an offline error keeps collapsing to nothing', () {
    // No response object: the caller's own "couldn't save" sentence is the
    // whole story, and "HTTP null" would be noise.
    final err = DioException(
      requestOptions: RequestOptions(path: '/catalog/works'),
      type: DioExceptionType.connectionError,
    );
    expect(briefError(err), '');
  });
}
