import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/server_store.dart';
import '../models/option_item.dart';
import '../repo/options_repo.dart';

/// 选项数据仓库（网站 / 数据库 / 容器 / 已安装应用）。
final optionsRepoProvider = Provider<OptionsRepo>((ref) {
  return OptionsRepo(ref.watch(apiClientProvider));
});

/// 网站名称选项。
final websiteOptionsProvider = FutureProvider.autoDispose<List<OptionItem>>((
  ref,
) async {
  return ref.watch(optionsRepoProvider).websites();
});

/// 指定类型的数据库选项（mysql / postgresql / clickhouse）。
final databaseOptionsProvider = FutureProvider.autoDispose
    .family<List<OptionItem>, String>((ref, type) async {
      return ref.watch(optionsRepoProvider).databases(type);
    });

/// 容器名称选项。
final containerOptionsProvider = FutureProvider.autoDispose<List<OptionItem>>((
  ref,
) async {
  return ref.watch(optionsRepoProvider).containers();
});

/// 指定应用（逗号分隔 slug）是否已安装。
final appInstalledProvider = FutureProvider.autoDispose.family<bool, String>((
  ref,
  slugs,
) async {
  return ref.watch(optionsRepoProvider).isInstalled(slugs);
});

/// 已安装的数据库类型集合。
final installedDatabaseTypesProvider = FutureProvider.autoDispose<Set<String>>((
  ref,
) async {
  return ref.watch(optionsRepoProvider).installedDatabaseTypes();
});
