import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/server_store.dart';
import '../models/log_entry.dart';
import '../repo/log_repo.dart';

/// 面板日志数据仓库。
final logRepoProvider = Provider<LogRepository>(
  (ref) => LogRepository(ref.watch(apiClientProvider)),
);

/// 日志查询条件（family 参数，需值相等语义）。
class LogQuery {
  const LogQuery({required this.type, this.date = '', this.limit = 200});

  /// app / db / http（`internal/biz/log.go`）。
  final String type;

  /// `YYYY-MM-DD`，空串表示当天。
  final String date;

  /// 条数上限，服务端限制 1 - 1000。
  final int limit;

  LogQuery copyWith({String? type, String? date, int? limit}) => LogQuery(
    type: type ?? this.type,
    date: date ?? this.date,
    limit: limit ?? this.limit,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LogQuery &&
          other.type == type &&
          other.date == date &&
          other.limit == limit;

  @override
  int get hashCode => Object.hash(type, date, limit);
}

/// 指定类型可用的日志日期列表。
final logDatesProvider = FutureProvider.autoDispose
    .family<List<String>, String>((ref, type) {
      return ref.watch(logRepoProvider).dates(type);
    });

/// 日志列表。
final logListProvider = FutureProvider.autoDispose
    .family<List<LogEntry>, LogQuery>((ref, query) {
      return ref
          .watch(logRepoProvider)
          .list(type: query.type, limit: query.limit, date: query.date);
    });

/// SSH 登录日志（参数为条数上限）。
final sshLogProvider = FutureProvider.autoDispose
    .family<List<SshLoginLog>, int>((ref, limit) {
      return ref.watch(logRepoProvider).sshLogs(limit: limit);
    });
