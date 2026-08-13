/// 服务器跑分（`internal/route/toolbox_benchmark.go`）相关数据模型。
///
/// 面板 `POST /toolbox_benchmark/test` 一次只跑一个项目，`name` 取值见
/// `request.ToolboxBenchmarkTest`：image / machine / compile / encryption /
/// compression / physics / json / memory / disk。
/// CPU 类项目返回一个整数分值，memory 与 disk 返回对象。
library;

/// 跑分项目分类。
enum BenchmarkGroup { cpu, memory, disk }

/// 一个跑分项目的定义。
class BenchmarkTest {
  const BenchmarkTest({
    required this.key,
    required this.title,
    required this.description,
    required this.group,
  });

  final String key;
  final String title;
  final String description;
  final BenchmarkGroup group;
}

/// 全部跑分项目（顺序与面板 Web 端一致）。
const List<BenchmarkTest> kBenchmarkTests = <BenchmarkTest>[
  BenchmarkTest(
    key: 'image',
    title: '图像处理',
    description: '4000×4000 图像卷积模糊',
    group: BenchmarkGroup.cpu,
  ),
  BenchmarkTest(
    key: 'machine',
    title: '机器学习',
    description: '900×900 矩阵乘法',
    group: BenchmarkGroup.cpu,
  ),
  BenchmarkTest(
    key: 'compile',
    title: '程序编译',
    description: '1000 次斐波那契大数计算',
    group: BenchmarkGroup.cpu,
  ),
  BenchmarkTest(
    key: 'encryption',
    title: 'AES 加密',
    description: '512 MB 数据 AES-GCM 加密',
    group: BenchmarkGroup.cpu,
  ),
  BenchmarkTest(
    key: 'compression',
    title: '压缩解压',
    description: 'gzip 压缩与解压约 400 MB 数据',
    group: BenchmarkGroup.cpu,
  ),
  BenchmarkTest(
    key: 'physics',
    title: '物理仿真',
    description: '4000 星体 N 体问题 30 步迭代',
    group: BenchmarkGroup.cpu,
  ),
  BenchmarkTest(
    key: 'json',
    title: 'JSON 解析',
    description: '50 万元素序列化与反序列化',
    group: BenchmarkGroup.cpu,
  ),
  BenchmarkTest(
    key: 'memory',
    title: '内存性能',
    description: '100 MB 内存带宽与随机访问延迟',
    group: BenchmarkGroup.memory,
  ),
  BenchmarkTest(
    key: 'disk',
    title: '磁盘 IO',
    description: '4K / 64K / 1M 块直写直读',
    group: BenchmarkGroup.disk,
  ),
];

/// 内存跑分结果（`{"bandwidth": "...", "latency": "...", "score": 123}`）。
class MemoryBenchmark {
  const MemoryBenchmark({
    required this.score,
    required this.bandwidth,
    required this.latency,
  });

  final int score;
  final String bandwidth;
  final String latency;

  factory MemoryBenchmark.fromJson(Map<String, dynamic> json) =>
      MemoryBenchmark(
        score: (json['score'] as num?)?.toInt() ?? 0,
        bandwidth: json['bandwidth'] as String? ?? 'N/A',
        latency: json['latency'] as String? ?? 'N/A',
      );
}

/// 单个块大小的磁盘读写速度。
class DiskIoResult {
  const DiskIoResult({required this.readSpeed, required this.writeSpeed});

  final String readSpeed;
  final String writeSpeed;

  factory DiskIoResult.fromJson(Map<String, dynamic> json) => DiskIoResult(
    readSpeed: (json['read_speed'] as String?)?.trim().isNotEmpty == true
        ? (json['read_speed'] as String).trim()
        : 'N/A',
    writeSpeed: (json['write_speed'] as String?)?.trim().isNotEmpty == true
        ? (json['write_speed'] as String).trim()
        : 'N/A',
  );
}

/// 磁盘跑分结果（`{"4": {...}, "64": {...}, "1024": {...}, "score": 123}`）。
class DiskBenchmark {
  const DiskBenchmark({required this.score, required this.blocks});

  final int score;

  /// 键为块大小（KB）：`4` / `64` / `1024`。
  final Map<String, DiskIoResult> blocks;

  static const List<String> blockKeys = <String>['4', '64', '1024'];

  static String blockLabel(String key) => switch (key) {
    '4' => '4 KB',
    '64' => '64 KB',
    '1024' => '1 MB',
    _ => '$key KB',
  };

  factory DiskBenchmark.fromJson(Map<String, dynamic> json) {
    final blocks = <String, DiskIoResult>{};
    for (final key in blockKeys) {
      final raw = json[key];
      if (raw is Map<String, dynamic>) {
        blocks[key] = DiskIoResult.fromJson(raw);
      }
    }
    return DiskBenchmark(
      score: (json['score'] as num?)?.toInt() ?? 0,
      blocks: blocks,
    );
  }

  DiskIoResult? operator [](String key) => blocks[key];
}

/// 跑分页整体状态。
class BenchmarkState {
  const BenchmarkState({
    this.running = false,
    this.currentKey,
    this.completed = 0,
    this.planned = 0,
    this.cpuScores = const <String, int>{},
    this.memory,
    this.disk,
    this.errors = const <String, String>{},
    this.finishedAt,
    this.stopping = false,
    this.startedAt,
    this.stopped = false,
  });

  final bool running;

  /// 正在跑的项目 key。
  final String? currentKey;

  /// 本轮已完成项目数。
  final int completed;

  /// 本轮计划项目数。
  final int planned;

  final Map<String, int> cpuScores;
  final MemoryBenchmark? memory;
  final DiskBenchmark? disk;

  /// 项目 key → 失败原因。
  final Map<String, String> errors;

  /// 最近一次跑分结束时间（本地时间）。
  final DateTime? finishedAt;

  /// 用户已请求停止，等待当前项目跑完。
  final bool stopping;

  /// 本轮开始时间（本地时间），用于展示已用时。
  final DateTime? startedAt;

  /// 最近一轮是被用户中止的（而非跑完全部项目）。
  final bool stopped;

  int get cpuTotal => cpuScores.values.fold<int>(0, (sum, v) => sum + v);

  int get memoryScore => memory?.score ?? 0;

  int get diskScore => disk?.score ?? 0;

  bool get hasAnyResult =>
      cpuScores.isNotEmpty || memory != null || disk != null;

  double get progress =>
      planned == 0 ? 0 : (completed / planned).clamp(0.0, 1.0);

  BenchmarkState copyWith({
    bool? running,
    String? currentKey,
    bool clearCurrentKey = false,
    int? completed,
    int? planned,
    Map<String, int>? cpuScores,
    MemoryBenchmark? memory,
    DiskBenchmark? disk,
    Map<String, String>? errors,
    DateTime? finishedAt,
    bool? stopping,
    DateTime? startedAt,
    bool? stopped,
  }) => BenchmarkState(
    running: running ?? this.running,
    currentKey: clearCurrentKey ? null : (currentKey ?? this.currentKey),
    completed: completed ?? this.completed,
    planned: planned ?? this.planned,
    cpuScores: cpuScores ?? this.cpuScores,
    memory: memory ?? this.memory,
    disk: disk ?? this.disk,
    errors: errors ?? this.errors,
    finishedAt: finishedAt ?? this.finishedAt,
    stopping: stopping ?? this.stopping,
    startedAt: startedAt ?? this.startedAt,
    stopped: stopped ?? this.stopped,
  );
}
