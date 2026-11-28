import 'dart:convert';

/// JSON normalization stub for Native platforms (Android, iOS, Windows, macOS, Linux).
///
/// Matches `json_normalizer_web.dart` AND unwraps `List<dynamic>` event envelopes
/// emitted by `socket_io_client` 3.x when Socket.IO `connectionStateRecovery`
/// appends a recovery offset argument (e.g. `[payloadMap, recoveryOffset]`).
dynamic _normalizeDynamicValue(dynamic v) {
  if (v is Map) {
    final result = <String, dynamic>{};
    v.forEach((k, val) {
      if (k != null) result[k.toString()] = _normalizeDynamicValue(val);
    });
    return result;
  }
  if (v is List) return normalizeJsonList(v);
  return v;
}

Map<String, dynamic> normalizeJsonMap(dynamic data) {
  if (data == null) return <String, dynamic>{};
  if (data is Map) {
    final result = <String, dynamic>{};
    data.forEach((k, v) {
      if (k != null) result[k.toString()] = _normalizeDynamicValue(v);
    });
    return result;
  }
  if (data is List) {
    for (final item in data) {
      if (item is Map || item is String) {
        final parsed = normalizeJsonMap(item);
        if (parsed.isNotEmpty) return parsed;
      }
    }
    if (data.isNotEmpty) {
      return normalizeJsonMap(data.first);
    }
    return <String, dynamic>{};
  }
  if (data is String) {
    final trimmed = data.trim();
    if (trimmed.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map || decoded is List) {
        return normalizeJsonMap(decoded);
      }
    } catch (_) {}
  }
  return <String, dynamic>{};
}

List<dynamic> normalizeJsonList(dynamic data) {
  if (data == null) return <dynamic>[];
  if (data is List) return data.map(_normalizeDynamicValue).toList();
  return <dynamic>[];
}
