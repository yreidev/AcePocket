/// 文件/目录条目。
///
/// 字段与面板 `internal/service/file.go` 的 `formatDir()` / `Info()` 响应对齐：
/// name / full / size / mode_str / mode / owner / group / uid / gid /
/// hidden / symlink / link / dir / modify / immutable。
class FileItem {
  const FileItem({
    required this.name,
    required this.full,
    required this.size,
    required this.modeStr,
    required this.mode,
    required this.owner,
    required this.group,
    required this.uid,
    required this.gid,
    required this.hidden,
    required this.symlink,
    required this.link,
    required this.dir,
    required this.modify,
    required this.immutable,
  });

  /// 文件名（不含路径）。
  final String name;

  /// 完整路径。
  final String full;

  /// 已格式化的大小（如 `1.25 MB`）；目录为空字符串，需调用 size 接口计算。
  final String size;

  /// 形如 `drwxr-xr-x` 的权限字符串。
  final String modeStr;

  /// 4 位八进制权限（如 `0755`）。
  final String mode;

  /// 属主名。
  final String owner;

  /// 属组名。
  final String group;

  final int uid;
  final int gid;

  /// 是否隐藏文件（以 . 开头）。
  final bool hidden;

  /// 是否符号链接。
  final bool symlink;

  /// 符号链接指向（非链接时为空）。
  final String link;

  /// 是否目录。
  final bool dir;

  /// 修改时间（面板格式化后的 `yyyy-MM-dd HH:mm:ss` 字符串）。
  final String modify;

  /// 是否带 immutable（chattr +i）属性。
  final bool immutable;

  factory FileItem.fromJson(Map<String, dynamic> json) {
    return FileItem(
      name: json['name'] as String? ?? '',
      full: json['full'] as String? ?? '',
      size: json['size'] as String? ?? '',
      modeStr: json['mode_str'] as String? ?? '',
      mode: json['mode'] as String? ?? '',
      owner: json['owner'] as String? ?? '',
      group: json['group'] as String? ?? '',
      uid: (json['uid'] as num?)?.toInt() ?? 0,
      gid: (json['gid'] as num?)?.toInt() ?? 0,
      hidden: json['hidden'] as bool? ?? false,
      symlink: json['symlink'] as bool? ?? false,
      link: json['link'] as String? ?? '',
      dir: json['dir'] as bool? ?? false,
      modify: json['modify'] as String? ?? '',
      immutable: json['immutable'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'full': full,
    'size': size,
    'mode_str': modeStr,
    'mode': mode,
    'owner': owner,
    'group': group,
    'uid': uid,
    'gid': gid,
    'hidden': hidden,
    'symlink': symlink,
    'link': link,
    'dir': dir,
    'modify': modify,
    'immutable': immutable,
  };

  /// 面板 `pkg/io/compress.go` 支持的压缩包扩展名。
  static const archiveExtensions = <String>[
    '.zip',
    '.tar.gz',
    '.tgz',
    '.tar.bz2',
    '.tar.xz',
    '.tar.zst',
    '.tar',
    '.gz',
    '.bz2',
    '.xz',
    '.zst',
    '.7z',
  ];

  /// 是否为可解压的压缩包。
  bool get isArchive {
    if (dir) return false;
    final lower = name.toLowerCase();
    return archiveExtensions.any(lower.endsWith);
  }
}

/// 把面板格式化后的大小文案（如 `1.25 MB`、`512 B`、`3.4 GB`）解析为字节数。
///
/// 用于在进入编辑器前按 [FileItem.size] 做大小预检。格式不可识别
/// （如目录的空字符串）时返回 null，调用方应放行而非拦截。
int? parseFormattedSize(String size) {
  final match = RegExp(
    r'^\s*([\d,]+(?:\.\d+)?)\s*([KMGTPE]?)I?B?\s*$',
    caseSensitive: false,
  ).firstMatch(size);
  if (match == null) return null;
  final value = double.tryParse(match.group(1)!.replaceAll(',', ''));
  if (value == null) return null;
  const units = {'': 0, 'K': 1, 'M': 2, 'G': 3, 'T': 4, 'P': 5, 'E': 6};
  final exponent = units[match.group(2)!.toUpperCase()];
  if (exponent == null) return null;
  var multiplier = 1.0;
  for (var i = 0; i < exponent; i++) {
    multiplier *= 1024;
  }
  return (value * multiplier).round();
}

/// 文件列表分页结果（`GET /api/file/list` 的 `{total, items}`）。
class FileListPage {
  const FileListPage({required this.total, required this.items});

  final int total;
  final List<FileItem> items;

  factory FileListPage.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return FileListPage(
      total: (json['total'] as num?)?.toInt() ?? 0,
      items: rawItems is List
          ? rawItems
                .whereType<Map<String, dynamic>>()
                .map(FileItem.fromJson)
                .toList()
          : const [],
    );
  }
}

/// 文件内容（`GET /api/file/content` 的 `{mime, content}`，content 为 base64）。
class FileContent {
  const FileContent({required this.mime, required this.text});

  /// MIME 类型（如 `text/plain; charset=utf-8`）。
  final String mime;

  /// 解码后的文本内容（二进制文件会以宽容模式解码，可能出现替换字符）。
  final String text;

  /// 粗略判断是否文本类内容（用于编辑器提示，不做强限制）。
  bool get looksLikeText {
    final m = mime.toLowerCase();
    if (m.startsWith('text/')) return true;
    return m.contains('json') ||
        m.contains('xml') ||
        m.contains('yaml') ||
        m.contains('javascript') ||
        m.contains('x-sh') ||
        m.contains('x-empty') ||
        m.contains('empty') ||
        m.isEmpty;
  }
}

/// 复制 / 移动操作的一项（对应面板 `request.FileControl`）。
class FileTransferItem {
  const FileTransferItem({
    required this.source,
    required this.target,
    this.force = false,
  });

  final String source;
  final String target;
  final bool force;

  Map<String, dynamic> toJson() => {
    'source': source,
    'target': target,
    'force': force,
  };
}

// ---------------------------------------------------------------------------
// POSIX 路径工具（面板只运行于类 Unix 系统，路径分隔符固定为 /）。
// ---------------------------------------------------------------------------

/// 拼接目录与名称，如 `posixJoin('/www', 'a.txt')` → `/www/a.txt`。
String posixJoin(String dir, String name) {
  var d = dir;
  while (d.length > 1 && d.endsWith('/')) {
    d = d.substring(0, d.length - 1);
  }
  if (d == '/') return '/$name';
  return '$d/$name';
}

/// 取父目录，如 `/www/a.txt` → `/www`；根目录的父目录仍为 `/`。
String posixParent(String path) {
  var p = path;
  while (p.length > 1 && p.endsWith('/')) {
    p = p.substring(0, p.length - 1);
  }
  final idx = p.lastIndexOf('/');
  if (idx <= 0) return '/';
  return p.substring(0, idx);
}

/// 取文件名部分，如 `/www/a.txt` → `a.txt`。
String posixBaseName(String path) {
  var p = path;
  while (p.length > 1 && p.endsWith('/')) {
    p = p.substring(0, p.length - 1);
  }
  if (p == '/') return '/';
  final idx = p.lastIndexOf('/');
  return idx < 0 ? p : p.substring(idx + 1);
}

/// 归一化为绝对路径：去掉多余的末尾 `/`，保证以 `/` 开头。
String posixNormalize(String path) {
  var p = path.trim();
  if (p.isEmpty) return '/';
  if (!p.startsWith('/')) p = '/$p';
  while (p.length > 1 && p.endsWith('/')) {
    p = p.substring(0, p.length - 1);
  }
  return p;
}

/// 将路径拆分为面包屑段列表：`/www/wwwroot` → [('/', '/'), ('www', '/www'), ...]。
List<(String name, String path)> breadcrumbSegments(String path) {
  final normalized = posixNormalize(path);
  final result = <(String, String)>[('/', '/')];
  if (normalized == '/') return result;
  var current = '';
  for (final seg in normalized.split('/')) {
    if (seg.isEmpty) continue;
    current = '$current/$seg';
    result.add((seg, current));
  }
  return result;
}
