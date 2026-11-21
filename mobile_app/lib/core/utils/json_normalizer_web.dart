import 'dart:convert';
import 'dart:js_interop';

@JS('JSON.stringify')
external String? _jsStringify(JSAny? object);

/// JSON normalization for Flutter Web.
/// Handles raw JavaScript objects (JSObject), JSON strings, and Dart Maps reliably.
Map<String, dynamic> normalizeJsonMap(dynamic data) {
  if (data == null) return <String, dynamic>{};
  if (data is Map<String, dynamic>) return data;
  if (data is Map) {
    final result = <String, dynamic>{};
    data.forEach((k, v) {
      if (k != null) result[k.toString()] = v;
    });
    return result;
  }
  if (data is String) {
    try {
      final decoded = jsonDecode(data);
      if (decoded is Map) {
        final result = <String, dynamic>{};
        decoded.forEach((k, v) {
          if (k != null) result[k.toString()] = v;
        });
        return result;
      }
    } catch (_) {}
    return <String, dynamic>{};
  }
  if (data is List) {
    if (data.isNotEmpty) {
      return normalizeJsonMap(data.first);
    }
    return <String, dynamic>{};
  }
  try {
    // ignore: invalid_runtime_check_with_js_interop_types
    if (data is JSAny) {
      final rawStr = _jsStringify(data);
      if (rawStr != null && rawStr.isNotEmpty && rawStr != 'null') {
        final decoded = jsonDecode(rawStr);
        if (decoded is Map) {
          final result = <String, dynamic>{};
          decoded.forEach((k, v) {
            if (k != null) result[k.toString()] = v;
          });
          return result;
        }
      }
    }
  } catch (_) {}
  return <String, dynamic>{};
}
