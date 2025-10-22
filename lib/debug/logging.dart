import 'dart:convert';

import 'package:flutter/foundation.dart';

void logDebug(String tag, Object? msg, {Object? extra}) {
  if (!kDebugMode) return;
  final ts = DateTime.now().toIso8601String();
  final extraStr = extra == null ? '' : ' | extra=${_safe(extra)}';
  debugPrint('[${ts}][${tag}] ${_safe(msg)}$extraStr');
}

String _safe(Object? o) {
  if (o == null) return 'null';
  try {
    if (o is Map || o is List) {
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(o);
    }
    return o.toString();
  } catch (_) {
    return '$o';
  }
}
