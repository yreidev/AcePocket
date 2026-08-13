/// 解析辅助统一由 core 提供。
library;

export '../../../core/utils/json_utils.dart';
export '../../../core/utils/format.dart' show formatDateTime, formatRelative;

/// 截断长 ID（Docker ID 通常展示前 12 位；`sha256:` 前缀会被去掉）。
String shortId(String id, [int length = 12]) {
  var value = id;
  final colon = value.indexOf(':');
  if (colon >= 0 && colon < value.length - 1) {
    value = value.substring(colon + 1);
  }
  return value.length > length ? value.substring(0, length) : value;
}
