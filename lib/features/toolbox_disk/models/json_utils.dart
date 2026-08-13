library;

export '../../../core/utils/json_utils.dart' hide jsonString;

String jsonString(dynamic v, [String fallback = '']) {
  if (v == null) return fallback;
  if (v is String) return v.trim();
  return '$v'.trim();
}
