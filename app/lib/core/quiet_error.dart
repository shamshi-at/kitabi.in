import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

/// One short human line for an exception — never the raw `toString()` dump.
/// Network-shaped failures collapse to nothing (the caller's own sentence
/// already says "couldn't save/load"); anything else keeps a trimmed detail so
/// real bugs stay diagnosable in the field.
String briefError(Object err) {
  if (err is DioException) {
    final code = err.response?.statusCode;
    final data = err.response?.data;
    if (data is Map) {
      // Our own errors arrive FLAT: the API unwraps `HTTPException.detail` onto
      // the response root, so the body is {"code", "message"} with no envelope
      // (api/app/main.py's structured_http_error). Reading only the nested
      // shape meant every sentence the server wrote was dropped and the reader
      // got a bare "HTTP 500" instead — the rest of the app already reads the
      // flat shape, which is the tell. FastAPI's own built-in handlers still
      // nest under "detail", so both are read; a 422's `detail` is a *list*,
      // which the Map check steps over.
      final nested = data['detail'];
      final message = data['message'] ?? (nested is Map ? nested['message'] : null);
      if (message is String && message.isNotEmpty) return message;
    }
    if (code != null) return 'HTTP $code';
    return '';
  }
  final s = err.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
  return s.length > 140 ? '${s.substring(0, 140)}…' : s;
}

/// The house error surface: a quiet SnackBar with a plain [message] sentence,
/// plus the brief detail when one exists. Replaces raw `Text('$err')`.
void showQuietError(BuildContext context, String message, [Object? err]) {
  final detail = err == null ? '' : briefError(err);
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    duration: const Duration(seconds: 5),
    content: Text(detail.isEmpty ? message : '$message\n$detail'),
  ));
}
