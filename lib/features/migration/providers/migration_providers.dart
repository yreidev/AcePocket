import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../core/api/ws_client.dart';
import '../../../core/lifecycle/app_lifecycle.dart';
import '../../../core/models/server.dart';
import '../../../core/storage/server_store.dart';
import '../models/migration_connection.dart';
import '../models/migration_environment.dart';
import '../models/migration_items.dart';
import '../models/migration_status.dart';
import '../repo/migration_repo.dart';

/// 迁移数据仓库。
final migrationRepoProvider = Provider<MigrationRepository>(
  (ref) => MigrationRepository(ref.watch(apiClientProvider)),
);

/// 迁移结果（结果查看页使用，含全量日志）。
final migrationResultsProvider = FutureProvider.autoDispose<MigrationSnapshot>(
  (ref) => ref.watch(migrationRepoProvider).results(),
);

/// 向导阶段（本地展示用，与面板 [MigrationStep] 对应但不完全等同）。
enum MigrationStage {
  /// 第一步：填写远程面板连接信息。
  connect('连接信息'),

  /// 第二步：环境预检与对比。
  precheck('环境预检'),

  /// 第三步：选择迁移项。
  select('选择项目'),

  /// 第四步：迁移进行中。
  running('迁移中'),

  /// 第五步：迁移完成。
  done('完成');

  const MigrationStage(this.label);

  final String label;

  int get index0 => MigrationStage.values.indexOf(this);
}

/// 迁移向导的完整状态。
class MigrationFlowState {
  const MigrationFlowState({
    this.initializing = true,
    this.initError,
    this.stage = MigrationStage.connect,
    this.serverStep = MigrationStep.idle,
    this.connection = const MigrationConnection(),
    this.localEnv,
    this.remoteEnv,
    this.comparison = EnvComparison.empty,
    this.ignoreEnvCheck = false,
    this.items = MigrationItems.empty,
    this.selectedWebsites = const <int>{},
    this.selectedDatabases = const <String>{},
    this.selectedDatabaseUsers = const <int>{},
    this.selectedProjects = const <int>{},
    this.stopOnMig = true,
    this.results = const <MigrationItemResult>[],
    this.logs = const <String>[],
    this.startedAt,
    this.endedAt,
    this.busy = false,
    this.busyLabel,
    this.live = false,
    this.polling = false,
    this.authHint,
  });

  /// 首次进入页面时正在读取面板迁移状态。
  final bool initializing;

  /// 首次读取失败的错误（页面用 ErrorView 展示并可重试）。
  final Object? initError;

  final MigrationStage stage;

  /// 面板侧的迁移步骤。
  final MigrationStep serverStep;

  final MigrationConnection connection;

  /// 本机环境（`/home/installed_environment`）。
  final InstalledEnvironment? localEnv;

  /// 远程面板环境（预检返回）。
  final InstalledEnvironment? remoteEnv;

  final EnvComparison comparison;

  /// 用户是否已确认忽略环境不一致。
  final bool ignoreEnvCheck;

  final MigrationItems items;

  final Set<int> selectedWebsites;

  /// 数据库无主键，用 [MigrationDatabase.key] 标识。
  final Set<String> selectedDatabases;

  final Set<int> selectedDatabaseUsers;
  final Set<int> selectedProjects;

  /// 迁移期间是否停止本地服务。
  final bool stopOnMig;

  final List<MigrationItemResult> results;
  final List<String> logs;
  final DateTime? startedAt;
  final DateTime? endedAt;

  /// 正在执行某个请求（预检 / 取项目 / 开始 / 重置）。
  final bool busy;
  final String? busyLabel;

  /// WebSocket 实时通道已连接。
  final bool live;

  /// 已回退到 HTTP 轮询。
  final bool polling;

  /// WebSocket 会话认证失败提示（需去服务器配置补填面板账号密码）。
  final String? authHint;

  /// 是否可以进入下一步（环境校验通过或用户已确认忽略）。
  bool get canProceedAfterPrecheck =>
      remoteEnv != null && (comparison.passed || ignoreEnvCheck);

  int get selectedCount =>
      selectedWebsites.length +
      selectedDatabases.length +
      selectedDatabaseUsers.length +
      selectedProjects.length;

  /// 已选中的网站（保持列表顺序）。
  List<MigrationWebsite> get pickedWebsites =>
      items.websites.where((e) => selectedWebsites.contains(e.id)).toList();

  List<MigrationDatabase> get pickedDatabases =>
      items.databases.where((e) => selectedDatabases.contains(e.key)).toList();

  List<MigrationDatabaseUser> get pickedDatabaseUsers => items.databaseUsers
      .where((e) => selectedDatabaseUsers.contains(e.id))
      .toList();

  List<MigrationProject> get pickedProjects =>
      items.projects.where((e) => selectedProjects.contains(e.id)).toList();

  bool get allSucceeded =>
      results.isNotEmpty &&
      results.every((r) => r.status == MigrationItemStatus.success);

  MigrationFlowState copyWith({
    bool? initializing,
    Object? initError,
    bool clearInitError = false,
    MigrationStage? stage,
    MigrationStep? serverStep,
    MigrationConnection? connection,
    InstalledEnvironment? localEnv,
    InstalledEnvironment? remoteEnv,
    EnvComparison? comparison,
    bool? ignoreEnvCheck,
    MigrationItems? items,
    Set<int>? selectedWebsites,
    Set<String>? selectedDatabases,
    Set<int>? selectedDatabaseUsers,
    Set<int>? selectedProjects,
    bool? stopOnMig,
    List<MigrationItemResult>? results,
    List<String>? logs,
    DateTime? startedAt,
    DateTime? endedAt,
    bool clearTimes = false,
    bool? busy,
    String? busyLabel,
    bool? live,
    bool? polling,
    String? authHint,
    bool clearAuthHint = false,
  }) =>
      MigrationFlowState(
        initializing: initializing ?? this.initializing,
        initError: clearInitError ? null : (initError ?? this.initError),
        stage: stage ?? this.stage,
        serverStep: serverStep ?? this.serverStep,
        connection: connection ?? this.connection,
        localEnv: localEnv ?? this.localEnv,
        remoteEnv: remoteEnv ?? this.remoteEnv,
        comparison: comparison ?? this.comparison,
        ignoreEnvCheck: ignoreEnvCheck ?? this.ignoreEnvCheck,
        items: items ?? this.items,
        selectedWebsites: selectedWebsites ?? this.selectedWebsites,
        selectedDatabases: selectedDatabases ?? this.selectedDatabases,
        selectedDatabaseUsers:
            selectedDatabaseUsers ?? this.selectedDatabaseUsers,
        selectedProjects: selectedProjects ?? this.selectedProjects,
        stopOnMig: stopOnMig ?? this.stopOnMig,
        results: results ?? this.results,
        logs: logs ?? this.logs,
        startedAt: clearTimes ? null : (startedAt ?? this.startedAt),
        endedAt: clearTimes ? null : (endedAt ?? this.endedAt),
        busy: busy ?? this.busy,
        busyLabel: busy == false ? null : (busyLabel ?? this.busyLabel),
        live: live ?? this.live,
        polling: polling ?? this.polling,
        authHint: clearAuthHint ? null : (authHint ?? this.authHint),
      );
}

/// 迁移向导控制器。
///
/// 负责：读取面板迁移状态、预检、拉取可迁移项、发起迁移、
/// 通过 `WS /ws/migration/progress` 实时接收进度（失败时回退 HTTP 轮询）、重置。
///
/// 采用常驻 Provider（非 autoDispose），离开页面后实时通道仍保持，
/// 迁移进度不会丢失；切换服务器时自动重建并断开旧连接。
class MigrationFlowNotifier extends Notifier<MigrationFlowState> {
  static const int _maxLogLines = 2000;
  static const Duration _pollInterval = Duration(seconds: 3);
  static const Duration _reconnectDelay = Duration(seconds: 3);

  late MigrationRepository _repo;
  ServerConfig? _server;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _pollTimer;
  Timer? _reconnectTimer;
  bool _disposed = false;

  /// 应用是否处于前台。后台时暂停 WS 重连尝试与 HTTP 轮询兜底
  /// （已建立的 WS 连接保留，由服务端推送，客户端无定时开销）。
  bool _appForeground = true;

  /// 后台期间被推迟的 WS 重连，回前台后立即补一次。
  bool _reconnectPending = false;

  /// 后台期间被暂停的 HTTP 轮询，回前台后恢复定时并立即拉一次。
  bool _pollPaused = false;

  @override
  MigrationFlowState build() {
    _repo = ref.watch(migrationRepoProvider);
    _server = ref.watch(activeServerProvider);
    _disposed = false;
    _reconnectPending = false;
    _pollPaused = false;
    // 用 ref.listen 而非 ref.watch：切前后台不应重建整个迁移向导状态。
    _appForeground = ref.read(appForegroundProvider);
    ref.listen(appForegroundProvider, (_, next) {
      if (_appForeground == next) return;
      _appForeground = next;
      if (next) {
        _onForeground();
      } else {
        _onBackground();
      }
    });
    ref.onDispose(() {
      _disposed = true;
      _closeChannel();
      _pollTimer?.cancel();
      _reconnectTimer?.cancel();
    });
    return const MigrationFlowState();
  }

  /// 切后台：取消尚未触发的重连 / 轮询定时器，记下待恢复标记。
  void _onBackground() {
    if (_reconnectTimer != null) {
      _reconnectTimer!.cancel();
      _reconnectTimer = null;
      _reconnectPending = true;
    }
    if (_pollTimer != null) {
      _pollTimer!.cancel();
      _pollTimer = null;
      _pollPaused = true;
    }
  }

  /// 回前台：迁移仍在进行时立即补一次重连；轮询兜底恢复定时并立即拉一次。
  void _onForeground() {
    if (_disposed) return;
    if (_reconnectPending) {
      _reconnectPending = false;
      if (state.stage == MigrationStage.running) {
        unawaited(_startProgressStream());
      }
    }
    if (_pollPaused) {
      _pollPaused = false;
      if (state.polling) _resumePollTimer();
    }
  }

  // ------------------------------------------------------------------ 初始化

  /// 进入页面时同步一次面板状态：迁移中则直接进入进度界面，
  /// 已完成则展示结果。
  Future<void> init({bool force = false}) async {
    if (!force && !state.initializing && state.initError == null) return;
    state = state.copyWith(initializing: true, clearInitError: true);
    try {
      final snapshot = await _repo.status();
      if (_disposed) return;
      switch (snapshot.step) {
        case MigrationStep.running:
          state = state.copyWith(
            initializing: false,
            serverStep: snapshot.step,
            stage: MigrationStage.running,
            results: snapshot.results,
            startedAt: snapshot.startedAt,
            endedAt: snapshot.endedAt,
            logs: const <String>[],
          );
          await _startProgressStream();
        case MigrationStep.done:
          state = state.copyWith(
            initializing: false,
            serverStep: snapshot.step,
            stage: MigrationStage.done,
            results: snapshot.results,
            startedAt: snapshot.startedAt,
            endedAt: snapshot.endedAt,
          );
          await loadResults();
        default:
          // 面板处于 idle/connect/precheck/select：向导阶段由本地维护，
          // 只有当本地停留在「迁移中 / 完成」而面板已被重置时才退回第一步。
          final reverted = state.stage == MigrationStage.running ||
              state.stage == MigrationStage.done;
          if (reverted) {
            _closeChannel();
            _stopPolling();
            _reconnectTimer?.cancel();
            _reconnectTimer = null;
            _reconnectPending = false;
          }
          state = state.copyWith(
            initializing: false,
            serverStep: snapshot.step,
            stage: reverted ? MigrationStage.connect : state.stage,
            results: snapshot.results,
            logs: reverted ? const <String>[] : state.logs,
            live: reverted ? false : state.live,
          );
      }
    } catch (e) {
      if (_disposed) return;
      state = state.copyWith(initializing: false, initError: e);
    }
  }

  // ------------------------------------------------------------ 第一步：连接

  void updateConnection(MigrationConnection connection) {
    state = state.copyWith(connection: connection);
  }

  /// 预检：连接远程面板并对比双方环境。
  ///
  /// 返回 null 表示成功，否则返回可展示的错误文案。
  Future<String?> precheck() async {
    if (!state.connection.isValid) return '请完整填写远程面板地址、令牌 ID 与令牌';
    state = state.copyWith(busy: true, busyLabel: '正在连接远程面板…');
    try {
      final remote = await _repo.precheck(state.connection);
      final local = await _repo.localEnvironment();
      if (_disposed) return null;
      state = state.copyWith(
        busy: false,
        stage: MigrationStage.precheck,
        serverStep: MigrationStep.precheck,
        remoteEnv: remote,
        localEnv: local,
        comparison: EnvComparison.compare(local, remote),
        ignoreEnvCheck: false,
      );
      return null;
    } catch (e) {
      if (!_disposed) state = state.copyWith(busy: false);
      return _message(e);
    }
  }

  // ------------------------------------------------------------ 第二步：预检

  void setIgnoreEnvCheck(bool value) {
    state = state.copyWith(ignoreEnvCheck: value);
  }

  /// 拉取本地可迁移项，进入选择步骤。
  Future<String?> loadItems() async {
    state = state.copyWith(busy: true, busyLabel: '正在读取可迁移项…');
    try {
      final items = await _repo.items();
      if (_disposed) return null;
      // 重新拉取时保留仍然存在的选择项。
      final websiteIds = items.websites.map((e) => e.id).toSet();
      final databaseKeys = items.databases.map((e) => e.key).toSet();
      final userIds = items.databaseUsers.map((e) => e.id).toSet();
      final projectIds = items.projects.map((e) => e.id).toSet();
      state = state.copyWith(
        busy: false,
        items: items,
        stage: MigrationStage.select,
        serverStep: MigrationStep.select,
        selectedWebsites: state.selectedWebsites.intersection(websiteIds),
        selectedDatabases: state.selectedDatabases.intersection(databaseKeys),
        selectedDatabaseUsers:
            state.selectedDatabaseUsers.intersection(userIds),
        selectedProjects: state.selectedProjects.intersection(projectIds),
      );
      return null;
    } catch (e) {
      if (!_disposed) state = state.copyWith(busy: false);
      return _message(e);
    }
  }

  // ------------------------------------------------------------ 第三步：选择

  void toggleWebsite(int id, bool selected) {
    final next = Set<int>.from(state.selectedWebsites);
    if (selected) {
      next.add(id);
    } else {
      next.remove(id);
    }
    state = state.copyWith(selectedWebsites: next);
  }

  void toggleDatabase(String key, bool selected) {
    final next = Set<String>.from(state.selectedDatabases);
    if (selected) {
      next.add(key);
    } else {
      next.remove(key);
    }
    state = state.copyWith(selectedDatabases: next);
  }

  void toggleDatabaseUser(int id, bool selected) {
    final next = Set<int>.from(state.selectedDatabaseUsers);
    if (selected) {
      next.add(id);
    } else {
      next.remove(id);
    }
    state = state.copyWith(selectedDatabaseUsers: next);
  }

  void toggleProject(int id, bool selected) {
    final next = Set<int>.from(state.selectedProjects);
    if (selected) {
      next.add(id);
    } else {
      next.remove(id);
    }
    state = state.copyWith(selectedProjects: next);
  }

  /// 全选 / 全不选某一类（仅对可迁移的项生效）。
  void selectAllWebsites(bool selected) {
    state = state.copyWith(
      selectedWebsites:
          selected ? state.items.websites.map((e) => e.id).toSet() : <int>{},
    );
  }

  void selectAllDatabases(bool selected) {
    state = state.copyWith(
      selectedDatabases: selected
          ? state.items.databases
              .where((e) => e.supported)
              .map((e) => e.key)
              .toSet()
          : <String>{},
    );
  }

  void selectAllDatabaseUsers(bool selected) {
    state = state.copyWith(
      selectedDatabaseUsers: selected
          ? state.items.databaseUsers
              .where((e) => e.supported)
              .map((e) => e.id)
              .toSet()
          : <int>{},
    );
  }

  void selectAllProjects(bool selected) {
    state = state.copyWith(
      selectedProjects:
          selected ? state.items.projects.map((e) => e.id).toSet() : <int>{},
    );
  }

  void setStopOnMig(bool value) {
    state = state.copyWith(stopOnMig: value);
  }

  /// 上一步（仅在非迁移中可用）。
  void back() {
    switch (state.stage) {
      case MigrationStage.precheck:
        state = state.copyWith(stage: MigrationStage.connect);
      case MigrationStage.select:
        state = state.copyWith(stage: MigrationStage.precheck);
      case MigrationStage.connect:
      case MigrationStage.running:
      case MigrationStage.done:
        break;
    }
  }

  /// 开始迁移，成功后建立实时进度通道。
  Future<String?> start() async {
    if (state.selectedCount == 0) return '请至少选择一个迁移项';
    state = state.copyWith(busy: true, busyLabel: '正在提交迁移任务…');
    try {
      await _repo.start(
        websites: state.pickedWebsites,
        databases: state.pickedDatabases,
        databaseUsers: state.pickedDatabaseUsers,
        projects: state.pickedProjects,
        stopOnMig: state.stopOnMig,
      );
      if (_disposed) return null;
      state = state.copyWith(
        busy: false,
        stage: MigrationStage.running,
        serverStep: MigrationStep.running,
        results: const <MigrationItemResult>[],
        logs: const <String>[],
        clearTimes: true,
        clearAuthHint: true,
      );
      await _startProgressStream();
      return null;
    } catch (e) {
      if (!_disposed) state = state.copyWith(busy: false);
      return _message(e);
    }
  }

  // ------------------------------------------------------------ 进度与结果

  /// 拉取一次完整结果（含全量日志）。
  Future<String?> loadResults() async {
    try {
      final snapshot = await _repo.results();
      if (_disposed) return null;
      state = state.copyWith(
        serverStep: snapshot.step,
        results: snapshot.results,
        logs: _trim(snapshot.logs ?? state.logs),
        startedAt: snapshot.startedAt,
        endedAt: snapshot.endedAt,
        stage: snapshot.step == MigrationStep.done
            ? MigrationStage.done
            : state.stage,
      );
      return null;
    } catch (e) {
      return _message(e);
    }
  }

  /// 重新连接实时进度通道（用户点击「重试连接」时调用）。
  Future<void> retryProgressStream() async {
    _reconnectTimer?.cancel();
    state = state.copyWith(clearAuthHint: true, polling: false);
    await _startProgressStream();
  }

  Future<void> _startProgressStream() async {
    _reconnectTimer?.cancel();
    _reconnectPending = false;
    _closeChannel();
    final server = _server;
    if (server == null) {
      state = state.copyWith(live: false, authHint: '尚未选择服务器');
      return;
    }

    try {
      final channel = await wsConnect(server, '/ws/migration/progress');
      await channel.ready;
      if (_disposed) {
        await channel.sink.close();
        return;
      }
      _stopPolling();
      _channel = channel;
      state = state.copyWith(live: true, polling: false, clearAuthHint: true);
      _subscription = channel.stream.listen(
        _onMessage,
        onError: (Object _) => _onStreamClosed(),
        onDone: _onStreamClosed,
        cancelOnError: true,
      );
    } on WsAuthException catch (e) {
      if (_disposed) return;
      state = state.copyWith(live: false, authHint: e.message);
      _startPolling();
    } catch (e) {
      if (_disposed) return;
      state = state.copyWith(live: false, authHint: _message(e));
      _startPolling();
    }
  }

  void _onMessage(dynamic raw) {
    if (_disposed) return;
    final text = raw is String
        ? raw
        : raw is List<int>
            ? utf8.decode(raw, allowMalformed: true)
            : '$raw';
    dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      return;
    }
    final map = decoded is Map<String, dynamic>
        ? decoded
        : decoded is Map
            ? decoded.map((key, value) => MapEntry('$key', value))
            : null;
    if (map == null) return;

    final snapshot = MigrationSnapshot.fromJson(map);
    final logs = snapshot.newLogs == null || snapshot.newLogs!.isEmpty
        ? state.logs
        : _trim([...state.logs, ...snapshot.newLogs!]);

    state = state.copyWith(
      serverStep: snapshot.step,
      results: snapshot.results,
      logs: logs,
      startedAt: snapshot.startedAt,
      endedAt: snapshot.endedAt,
      stage: snapshot.step == MigrationStep.done
          ? MigrationStage.done
          : snapshot.step == MigrationStep.running
              ? MigrationStage.running
              : state.stage,
    );

    if (snapshot.step == MigrationStep.done) {
      _closeChannel();
      state = state.copyWith(live: false);
    }
  }

  /// WS 断开：迁移仍在进行时自动重连，否则同步一次最终结果。
  void _onStreamClosed() {
    if (_disposed) return;
    _closeChannel();
    state = state.copyWith(live: false);
    if (state.stage == MigrationStage.running) {
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      if (!_appForeground) {
        // 后台不重连，回前台后由 _onForeground 立即补一次。
        _reconnectPending = true;
        return;
      }
      _reconnectTimer = Timer(_reconnectDelay, () {
        if (_disposed || state.stage != MigrationStage.running) return;
        unawaited(_startProgressStream());
      });
    } else {
      unawaited(loadResults());
    }
  }

  /// WebSocket 不可用时的兜底：定时拉取 `/results`。
  void _startPolling() {
    if (_pollTimer != null || _pollPaused) return;
    state = state.copyWith(polling: true);
    if (!_appForeground) {
      // 后台不起轮询定时器，回前台后由 _onForeground 恢复。
      _pollPaused = true;
      return;
    }
    _resumePollTimer();
  }

  /// 创建轮询定时器并立即拉取一次（首次启动与回前台恢复共用）。
  void _resumePollTimer() {
    if (_pollTimer != null) return;
    unawaited(loadResults());
    _pollTimer = Timer.periodic(_pollInterval, (_) async {
      if (_disposed) return;
      await loadResults();
      if (state.stage != MigrationStage.running) _stopPolling();
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _pollPaused = false;
    if (!_disposed && state.polling) state = state.copyWith(polling: false);
  }

  void _closeChannel() {
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
  }

  // ------------------------------------------------------------------ 重置

  /// 重置迁移状态并回到第一步（迁移进行中时面板会拒绝）。
  Future<String?> reset() async {
    state = state.copyWith(busy: true, busyLabel: '正在重置…');
    try {
      await _repo.reset();
      if (_disposed) return null;
      _closeChannel();
      _stopPolling();
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      _reconnectPending = false;
      state = MigrationFlowState(
        initializing: false,
        connection: state.connection.copyWith(token: ''),
      );
      return null;
    } catch (e) {
      if (!_disposed) state = state.copyWith(busy: false);
      return _message(e);
    }
  }

  static List<String> _trim(List<String> logs) => logs.length <= _maxLogLines
      ? logs
      : logs.sublist(logs.length - _maxLogLines);

  static String _message(Object error) {
    final text = error.toString();
    return text.replaceFirst(RegExp(r'^\w+Exception:\s*'), '');
  }
}

/// 迁移向导控制器 Provider。
final migrationFlowProvider =
    NotifierProvider<MigrationFlowNotifier, MigrationFlowState>(
  MigrationFlowNotifier.new,
);
