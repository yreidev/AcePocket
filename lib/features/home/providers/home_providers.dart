import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/lifecycle/app_lifecycle.dart';
import '../../../core/router/router.dart';
import '../../../core/storage/server_store.dart';
import '../../app_settings/models/app_settings.dart';
import '../../app_settings/providers/app_settings_providers.dart';
import '../models/current_info.dart';
import '../models/panel_models.dart';
import '../models/runtime_models.dart';
import '../models/update_models.dart';
import '../repo/home_repo.dart';

/// 首页 Repository（依赖当前选中服务器的 ApiClient）。
final homeRepoProvider = Provider<HomeRepository>((ref) {
  return HomeRepository(ref.watch(apiClientProvider));
});

/// 面板基础信息。
final panelInfoProvider = FutureProvider.autoDispose<PanelInfo>((ref) {
  return ref.watch(homeRepoProvider).panel();
});

/// 系统信息。
final systemInfoProvider = FutureProvider.autoDispose<SystemInfo>((ref) {
  return ref.watch(homeRepoProvider).systemInfo();
});

/// 统计信息（网站 / 数据库 / 项目 / 计划任务 / 容器数量）。
final countInfoProvider = FutureProvider.autoDispose<CountInfo>((ref) {
  return ref.watch(homeRepoProvider).countInfo();
});

/// 首页展示应用。
final homeAppsProvider = FutureProvider.autoDispose<List<HomeApp>>((ref) {
  return ref.watch(homeRepoProvider).apps();
});

/// 面板健康问题。
final healthProvider = FutureProvider.autoDispose<List<HealthIssue>>((ref) {
  return ref.watch(homeRepoProvider).health();
});

/// 占用最高进程（type: cpu / memory / disk_io）。
final topProcessesProvider =
    FutureProvider.autoDispose.family<List<ProcessStat>, String>((ref, type) {
  return ref.watch(homeRepoProvider).topProcesses(type);
});

/// 面板是否有新版本。
///
/// 面板开启「离线模式」时 `/home/check_update` 返回 403，检查失败一律视为
/// 「无更新」，避免首页因非关键请求出错而打扰用户。
final panelUpdateProvider = FutureProvider.autoDispose<bool>((ref) async {
  try {
    return await ref.watch(homeRepoProvider).checkUpdate();
  } on ApiException {
    return false;
  }
});

/// 面板更新日志（当前版本之后的所有版本，新版本在前）。
///
/// 面板返回的顺序不保证，这里按版本号倒序整理，方便「最新版本在最上面」展示。
/// 已是最新版 / 离线模式 / 拉取失败时接口返回错误，交由页面展示。
final panelUpdateInfoProvider =
    FutureProvider.autoDispose<List<PanelVersion>>((ref) async {
  final versions = await ref.watch(homeRepoProvider).updateInfo();
  final sorted = [...versions]
    ..sort((a, b) => _compareVersion(b.version, a.version));
  return sorted;
});

/// 语义化版本号比较（非数字段按字符串比较，缺失段按 0 处理）。
int _compareVersion(String a, String b) {
  List<String> split(String v) =>
      v.replaceFirst(RegExp(r'^[vV]'), '').split(RegExp(r'[.\-+]'));
  final xs = split(a);
  final ys = split(b);
  final length = xs.length > ys.length ? xs.length : ys.length;
  for (var i = 0; i < length; i++) {
    final x = i < xs.length ? xs[i] : '0';
    final y = i < ys.length ? ys[i] : '0';
    final nx = int.tryParse(x);
    final ny = int.tryParse(y);
    final int result;
    if (nx != null && ny != null) {
      result = nx.compareTo(ny);
    } else {
      result = x.compareTo(y);
    }
    if (result != 0) return result;
  }
  return 0;
}

/// 面板 Go 运行时信息。
final runtimeInfoProvider = FutureProvider.autoDispose<RuntimeInfo>((ref) {
  return ref.watch(homeRepoProvider).runtimeInfo();
});

/// 面板协程堆栈（按协程编号升序）。
final goroutinesProvider =
    FutureProvider.autoDispose<List<GoroutineInfo>>((ref) async {
  final list = await ref.watch(homeRepoProvider).goroutines();
  return [...list]..sort((a, b) => a.id.compareTo(b.id));
});

/// 实时监控历史窗口长度（迷你图数据点数）。
const int kRealtimeHistoryLength = 30;

/// 首页实时监控状态：最新一次采样 + 由相邻两次采样算出的速率与迷你图序列。
class RealtimeState {
  const RealtimeState({
    required this.info,
    required this.netTxRate,
    required this.netRxRate,
    required this.diskReadRate,
    required this.diskWriteRate,
    required this.cpuHistory,
    required this.memHistory,
    required this.netTxHistory,
    required this.netRxHistory,
    required this.diskReadHistory,
    required this.diskWriteHistory,
  });

  /// 最新一次 `POST /home/current` 采样。
  final CurrentInfo info;

  /// 上行速率（字节 / 秒，所有非 lo 网卡合计）。
  final double netTxRate;

  /// 下行速率（字节 / 秒）。
  final double netRxRate;

  /// 磁盘读取速率（字节 / 秒，所有磁盘合计）。
  final double diskReadRate;

  /// 磁盘写入速率（字节 / 秒）。
  final double diskWriteRate;

  /// CPU 使用率历史（0-100）。
  final List<double> cpuHistory;

  /// 内存使用率历史（0-100）。
  final List<double> memHistory;

  final List<double> netTxHistory;
  final List<double> netRxHistory;
  final List<double> diskReadHistory;
  final List<double> diskWriteHistory;
}

/// 首页实时数据轮询（间隔可在「应用设置」中配置，默认 3 秒，可关闭；
/// 页面离开后自动停止）。
///
/// 首页 tab 常驻于 `StatefulShellRoute.indexedStack`，本 Provider 不会因
/// 切换 tab / 压栈子页而自动释放，因此额外做两层暂停控制：
/// - 应用切后台 / 锁屏（[appForegroundProvider] 为 false）时暂停定时器；
/// - 当前路由不是首页（切到其他 tab 或压栈了任何页面）时暂停定时器。
///
/// 恢复（回前台且回到首页）时立即拉取一次并重启定时。
final homeRealtimeProvider =
    AsyncNotifierProvider.autoDispose<HomeRealtimeNotifier, RealtimeState>(
        HomeRealtimeNotifier.new);

class HomeRealtimeNotifier extends AutoDisposeAsyncNotifier<RealtimeState> {
  /// 轮询间隔（秒），来自「应用设置」（homePollIntervalProvider）；0 = 关闭轮询。
  int _intervalSeconds = kDefaultHomePollIntervalSeconds;

  Timer? _timer;
  bool _fetching = false;
  bool _disposed = false;

  /// 应用是否处于前台（resumed）。
  bool _appForeground = true;

  /// 首页 tab 是否可见。
  ///
  /// 判断依据：路由可见性——GoRouter 当前匹配路径为 `/`（首页分支的根路由）
  /// 时首页才在最上层。切到「网站」「更多」tab、在任意 tab 内压栈子页、
  /// push 顶层全屏路由时，匹配路径都会变为其他值，且此时首页要么被
  /// IndexedStack 置为 Offstage、要么被不透明路由完全遮挡，均无需刷新。
  /// 不用 TickerMode.of(context) 是因为那需要在页面 Widget 里上报，
  /// 而路由可见性可完全在 Provider 内监听 routerDelegate 实现。
  bool _routeVisible = true;

  // 上一次采样的累计值，用于差分计算速率。
  CurrentInfo? _prev;

  // 迷你图历史序列。
  final List<double> _cpuHistory = [];
  final List<double> _memHistory = [];
  final List<double> _netTxHistory = [];
  final List<double> _netRxHistory = [];
  final List<double> _diskReadHistory = [];
  final List<double> _diskWriteHistory = [];

  @override
  Future<RealtimeState> build() async {
    // 切换服务器时 apiClientProvider 变化，本 Notifier 会重建，重置全部状态。
    final repo = ref.watch(homeRepoProvider);

    _timer?.cancel();
    _prev = null;
    _cpuHistory.clear();
    _memHistory.clear();
    _netTxHistory.clear();
    _netRxHistory.clear();
    _diskReadHistory.clear();
    _diskWriteHistory.clear();

    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      _timer?.cancel();
      _timer = null;
    });

    // 应用前后台切换：后台暂停轮询，回前台立即拉一次并恢复。
    // 用 ref.listen 而非 ref.watch，避免每次切换都重建本 Notifier
    // （重建会清空迷你图历史）。
    _appForeground = ref.read(appForegroundProvider);
    ref.listen(appForegroundProvider, (_, next) {
      if (_appForeground == next) return;
      _appForeground = next;
      _syncPolling(refreshOnResume: true);
    });

    // 轮询间隔来自「应用设置」。与 appForegroundProvider 同理，用 read + listen
    // 而非 watch，避免调整间隔时重建本 Notifier（重建会清空迷你图历史）。
    _intervalSeconds = ref.read(homePollIntervalProvider);
    ref.listen(homePollIntervalProvider, (_, next) {
      if (_intervalSeconds == next) return;
      _intervalSeconds = next;
      // 重建定时器以应用新间隔；间隔为 0（关闭）时 _syncPolling 会停表。
      _timer?.cancel();
      _timer = null;
      _syncPolling(refreshOnResume: false);
    });

    // 路由可见性（见 _routeVisible 的注释）：监听 GoRouter 的 routerDelegate，
    // 每次导航后根据当前匹配路径判断首页是否仍在最上层。
    final delegate = ref.read(routerProvider).routerDelegate;
    bool homeOnTop() => delegate.currentConfiguration.uri.path == '/';
    void syncRouteVisible() {
      final visible = homeOnTop();
      if (_routeVisible == visible) return;
      _routeVisible = visible;
      _syncPolling(refreshOnResume: true);
    }

    _routeVisible = homeOnTop();
    delegate.addListener(syncRouteVisible);
    ref.onDispose(() => delegate.removeListener(syncRouteVisible));

    _syncPolling(refreshOnResume: false);

    final info = await repo.current();
    return _merge(info);
  }

  /// 按当前可见性开启 / 暂停轮询定时器。
  ///
  /// [refreshOnResume] 为 true 时，恢复轮询的同时立即拉取一次，
  /// 让用户回到首页 / 回到前台后马上看到最新数据。
  void _syncPolling({required bool refreshOnResume}) {
    final visible = !_disposed && _appForeground && _routeVisible;
    if (!visible || _intervalSeconds <= 0) {
      _timer?.cancel();
      _timer = null;
      // 轮询已关闭但页面可见时，回到首页 / 回到前台仍拉取一次，
      // 保证「关闭」档位下进入页面能看到当前数据。
      if (visible && refreshOnResume) unawaited(_tick());
      return;
    }
    if (_timer != null) return;
    _timer =
        Timer.periodic(Duration(seconds: _intervalSeconds), (_) => _tick());
    if (refreshOnResume) unawaited(_tick());
  }

  /// 手动立即刷新一次（下拉刷新用）。
  Future<void> refreshNow() => _tick();

  Future<void> _tick() async {
    if (_disposed || _fetching) return;
    _fetching = true;
    try {
      final repo = ref.read(homeRepoProvider);
      final info = await repo.current();
      if (_disposed) return;
      state = AsyncData(_merge(info));
    } catch (e, st) {
      if (_disposed) return;
      // 已有数据时保留旧数据继续轮询（网络抖动不打断页面），同时把错误一并暴露，
      // 页面据此展示「刷新失败」轻提示；首次加载失败则为纯错误态，由页面展示重试。
      state = AsyncError<RealtimeState>(e, st).copyWithPrevious(state);
    } finally {
      _fetching = false;
    }
  }

  RealtimeState _merge(CurrentInfo info) {
    var netTx = 0.0;
    var netRx = 0.0;
    var diskRead = 0.0;
    var diskWrite = 0.0;

    final prev = _prev;
    if (prev != null) {
      var elapsed = (_intervalSeconds > 0
              ? _intervalSeconds
              : kDefaultHomePollIntervalSeconds)
          .toDouble();
      final t1 = prev.time;
      final t2 = info.time;
      if (t1 != null && t2 != null) {
        final diff = t2.difference(t1).inMilliseconds / 1000.0;
        if (diff >= 0.5) elapsed = diff;
      }
      double rate(int now, int before) {
        final delta = now - before;
        return delta <= 0 ? 0 : delta / elapsed;
      }

      netTx = rate(info.totalBytesSent, prev.totalBytesSent);
      netRx = rate(info.totalBytesRecv, prev.totalBytesRecv);
      diskRead = rate(info.totalReadBytes, prev.totalReadBytes);
      diskWrite = rate(info.totalWriteBytes, prev.totalWriteBytes);
    }
    _prev = info;

    void push(List<double> list, double value) {
      list.add(value);
      if (list.length > kRealtimeHistoryLength) list.removeAt(0);
    }

    push(_cpuHistory, info.percent.clamp(0, 100).toDouble());
    push(_memHistory, info.mem.usedPercent.clamp(0, 100).toDouble());
    if (prev != null) {
      push(_netTxHistory, netTx);
      push(_netRxHistory, netRx);
      push(_diskReadHistory, diskRead);
      push(_diskWriteHistory, diskWrite);
    }

    return RealtimeState(
      info: info,
      netTxRate: netTx,
      netRxRate: netRx,
      diskReadRate: diskRead,
      diskWriteRate: diskWrite,
      cpuHistory: List.unmodifiable(_cpuHistory),
      memHistory: List.unmodifiable(_memHistory),
      netTxHistory: List.unmodifiable(_netTxHistory),
      netRxHistory: List.unmodifiable(_netRxHistory),
      diskReadHistory: List.unmodifiable(_diskReadHistory),
      diskWriteHistory: List.unmodifiable(_diskWriteHistory),
    );
  }
}
