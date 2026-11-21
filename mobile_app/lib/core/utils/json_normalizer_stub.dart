/// JSON normalization stub for Native platforms (Android, iOS, Windows, macOS, Linux).
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
  return <String, dynamic>{};
}

List<dynamic> normalizeJsonList(dynamic data) {
  if (data == null) return <dynamic>[];
  if (data is List) return data;
  return <dynamic>[];
}
