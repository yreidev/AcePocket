import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/storage/server_store.dart';
import '../models/system_service.dart';
import '../repo/systemctl_repo.dart';
import 'apps_providers.dart';

/// 系统服务仓库；未选择服务器时为 null。
final systemctlRepoProvider = Provider<SystemctlRepo?>((ref) {
  final server = ref.watch(activeServerProvider);
  if (server == null) return null;
  return SystemctlRepo(ref.watch(apiClientProvider));
});

/// 用户手动添加的自定义服务名（按服务器隔离，本地持久化）。
///
/// 面板没有「列出所有 systemd 服务」的接口，除已安装应用推导出的服务外，
/// 其余服务需用户自行添加，这里用 shared_preferences 保存。
final customServicesProvider =
    AsyncNotifierProvider<CustomServicesNotifier, List<String>>(
      CustomServicesNotifier.new,
    );

class CustomServicesNotifier extends AsyncNotifier<List<String>> {
  static const _keyPrefix = 'acepanel.apps.custom_services.';

  String? _serverId;

  @override
  Future<List<String>> build() async {
    _serverId = ref.watch(activeServerProvider)?.id;
    final id = _serverId;
    if (id == null) return const <String>[];
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('$_keyPrefix$id') ?? const <String>[];
  }

  /// 添加自定义服务（重复时忽略）。
  Future<void> add(String name) async {
    final service = name.trim();
    if (service.isEmpty) return;
    final current = state.value ?? const <String>[];
    if (current.contains(service)) return;
    await _save([...current, service]);
  }

  /// 移除自定义服务。
  Future<void> remove(String name) async {
    final current = state.value ?? const <String>[];
    if (!current.contains(name)) return;
    await _save(current.where((s) => s != name).toList());
  }

  Future<void> _save(List<String> services) async {
    final id = _serverId;
    if (id == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('$_keyPrefix$id', services);
    state = AsyncData(services);
  }
}

/// 服务列表：已安装应用推导出的服务 + 用户自定义服务。
final serviceListProvider = FutureProvider.autoDispose<List<ServiceRef>>((
  ref,
) async {
  final appsRepo = ref.watch(appsRepoProvider);
  final custom = await ref.watch(customServicesProvider.future);
  if (appsRepo == null) {
    return custom
        .map((name) => ServiceRef(name: name, source: ServiceSource.custom))
        .toList();
  }

  // 已安装应用一次取足（面板应用总数远小于 200）。
  final installed = await appsRepo.list(
    page: 1,
    limit: 200,
    installedOnly: true,
  );

  final result = <ServiceRef>[];
  final seen = <String>{};
  for (final app in installed.items) {
    List<String> names;
    if (app.slug == 'supervisor') {
      // supervisor 的 unit 名依发行版而异，向面板询问实际名称。
      String name = '';
      try {
        name = await appsRepo.supervisorServiceName();
      } catch (_) {
        name = '';
      }
      names = [
        name.isEmpty ? AppServiceCatalog.supervisorFallbackService : name,
      ];
    } else {
      names = AppServiceCatalog.servicesOf(app.slug);
    }
    for (final name in names) {
      if (!seen.add(name)) continue;
      result.add(
        ServiceRef(
          name: name,
          source: ServiceSource.app,
          appName: app.name,
          appSlug: app.slug,
        ),
      );
    }
  }
  result.sort((a, b) => a.name.compareTo(b.name));

  for (final name in custom) {
    if (!seen.add(name)) continue;
    result.add(ServiceRef(name: name, source: ServiceSource.custom));
  }
  return result;
});

/// 单个服务的运行 / 自启状态。
final serviceStateProvider = FutureProvider.autoDispose
    .family<ServiceState, String>((ref, name) async {
      final repo = ref.watch(systemctlRepoProvider);
      if (repo == null) {
        throw StateError('尚未选择服务器');
      }
      return repo.state(name);
    });
