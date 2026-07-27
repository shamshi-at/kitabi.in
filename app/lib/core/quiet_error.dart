import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

/// One short human line for an exception — never the raw `toString()` dump.
/// Network-shaped failures collapse to nothing (the caller's own sentence
/// already says "couldn't save/load"); anything else keeps a trimmed detail so
/// real bugs stay diagnosable in the field.
String briefError(Object err) {
  if (err is DioException) {
    final code = err.response?.statusCode;
    final detail = err.response?.data;
    if (detail is Map && detail['detail'] is Map && detail['detail']['message'] is String) {
      return detail['detail']['message'] as String;
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
