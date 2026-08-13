library;

import '../../../core/utils/json_utils.dart' hide jsonMap;
export '../../../core/utils/json_utils.dart' hide jsonMap;
export '../../../core/utils/format.dart' show formatDateTime;

/// 迁移模块把「非对象」视为缺失，而不是空 Map。
Map<String, dynamic>? jsonMap(dynamic v) => jsonMapOrNull(v);
