import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/server_store.dart';
import 'panel_feature.dart';

/// 当前服务器的面板版本。
///
/// 取自 `GET /api/home/system_info` 的 `panel_version` 字段
/// （面板源码 `internal/service/home.go` 中 `"panel_version": app.Version`）。
///
/// 依赖 [apiClientProvider]，因此切换服务器会自动重新获取；
/// 拿不到版本（接口不通、字段缺失、格式无法解析）时返回 null，
/// 此时所有功能按「可用」处理，不因版本探测失败而误伤入口。
final panelVersionProvider = FutureProvider<PanelVersion?>((ref) async {
  final api = ref.watch(apiClientProvider);
  try {
    final data = await api.get('/home/system_info');
    if (data is! Map) return null;
    return PanelVersion.tryParse(data['panel_version'] as String?);
  } catch (_) {
    return null;
  }
});

/// 同步读取已缓存的面板版本；尚未加载完成或失败时为 null。
///
/// 供「更多」页这类需要在 build 中同步判断大量入口的场景使用，
/// 避免每个入口都去 watch 一个 AsyncValue。
final cachedPanelVersionProvider = Provider<PanelVersion?>((ref) {
  return ref.watch(panelVersionProvider).valueOrNull;
});

/// 某功能在当前服务器上是否可用。
final featureSupportedProvider = Provider.family<bool, PanelFeature>((
  ref,
  feature,
) {
  return isFeatureSupported(feature, ref.watch(cachedPanelVersionProvider));
});
