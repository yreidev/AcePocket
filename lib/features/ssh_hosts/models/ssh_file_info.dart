/// SFTP 文件信息与路径工具。
///
/// 字段与面板源码 `internal/biz/ssh.go` 的 `SSHFileInfo` 对齐：
/// name / size / mode / mod_time（Unix 秒）/ is_dir / is_link。
library;

/// 远程主机上的一个文件或目录（GET /ssh/{id}/file 的元素）。
class SshFileInfo {
  const SshFileInfo({
    required this.name,
    required this.size,
    required this.mode,
    required this.modTime,
    required this.isDir,
    required this.isLink,
  });

  final String name;

  /// 字节数（目录无意义）。
  final int size;

  /// Go `os.FileMode.String()` 结果，如 `-rw-r--r--`。
  final String mode;

  /// 修改时间；面板返回 Unix 秒，0 / 负数表示未知。
  final DateTime? modTime;

  final bool isDir;
  final bool isLink;

  /// 目录或指向目录的软链接（面板 Web 端同样允许点进软链接）。
  bool get navigable => isDir || isLink;

  factory SshFileInfo.fromJson(Map<String, dynamic> json) {
    final seconds = (json['mod_time'] as num?)?.toInt() ?? 0;
    return SshFileInfo(
      name: json['name'] as String? ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
      mode: json['mode'] as String? ?? '',
      // Unix 时间戳转本地时间（fromMillisecondsSinceEpoch 默认即本地时区）。
      modTime: seconds > 0
          ? DateTime.fromMillisecondsSinceEpoch(seconds * 1000)
          : null,
      isDir: json['is_dir'] as bool? ?? false,
      isLink: json['is_link'] as bool? ?? false,
    );
  }
}

/// 规范化绝对路径：确保以 `/` 开头、去掉重复与结尾的 `/`。
String normalizePath(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '/';
  final segments = trimmed
      .split('/')
      .where((segment) => segment.isNotEmpty)
      .toList();
  if (segments.isEmpty) return '/';
  return '/${segments.join('/')}';
}

/// 拼接子路径。
String joinPath(String parent, String name) {
  final base = normalizePath(parent);
  final child = name.trim();
  if (child.isEmpty) return base;
  return base == '/' ? '/$child' : '$base/$child';
}

/// 上级目录（根目录返回自身）。
String parentPath(String path) {
  final base = normalizePath(path);
  if (base == '/') return '/';
  final index = base.lastIndexOf('/');
  return index <= 0 ? '/' : base.substring(0, index);
}

/// 面包屑分段：返回 `(显示名, 绝对路径)` 列表，首项恒为根目录。
List<(String, String)> breadcrumbSegments(String path) {
  final base = normalizePath(path);
  final result = <(String, String)>[('/', '/')];
  if (base == '/') return result;
  final segments = base.split('/').where((segment) => segment.isNotEmpty);
  var current = '';
  for (final segment in segments) {
    current = '$current/$segment';
    result.add((segment, current));
  }
  return result;
}
