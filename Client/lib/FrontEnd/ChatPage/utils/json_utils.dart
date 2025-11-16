Map<String, dynamic> asStringKeyMap(dynamic x) {
  if (x is Map<String, dynamic>) return x;
  if (x is Map) return x.map((k, v) => MapEntry(k.toString(), v));
  return <String, dynamic>{};
}
