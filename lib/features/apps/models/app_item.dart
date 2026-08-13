import 'json_utils.dart';

/// 应用可安装的版本通道（对应源码 `types.AppDetail.Channels` 的元素）。
class AppChannel {
  const AppChannel({
    required this.slug,
    required this.name,
    required this.panel,
    required this.version,
    required this.log,
  });

  /// 通道 slug（安装时提交给 `/app/install` 的 `channel`）。
  final String slug;

  /// 通道显示名（如 `8.0`、`stable`）。
  final String name;

  /// 该通道要求的面板版本。
  final String panel;

  /// 该通道当前可安装的版本号。
  final String version;

  /// 更新日志。
  final String log;

  factory AppChannel.fromJson(Map<String, dynamic> json) => AppChannel(
    slug: jsonString(json['slug']),
    name: jsonString(json['name']),
    panel: jsonString(json['panel']),
    version: jsonString(json['version']),
    log: jsonString(json['log']),
  );
}

/// 应用运行状态（对应源码 `pkg/types/app.go` 的常量）。
class AppStatus {
  const AppStatus._();

  static const running = 'running';
  static const stopped = 'stopped';
  static const partial = 'partial';
  static const na = 'n/a';
}

/// 应用商店中的一个应用（对应源码 `types.AppDetail`，来源 `GET /api/app/list`）。
class AppItem {
  const AppItem({
    required this.name,
    required this.description,
    required this.categories,
    required this.slug,
    required this.channels,
    required this.installed,
    required this.installedChannel,
    required this.installedVersion,
    required this.updateExist,
    required this.show,
    required this.status,
    required this.customSupported,
  });

  /// 应用名称。
  final String name;

  /// 应用描述。
  final String description;

  /// 所属分类 slug 列表。
  final List<String> categories;

  /// 应用 slug（唯一标识，所有操作接口的入参）。
  final String slug;

  /// 可安装的版本通道。
  final List<AppChannel> channels;

  /// 是否已安装。
  final bool installed;

  /// 已安装的通道 slug（未安装时为空）。
  final String installedChannel;

  /// 已安装的版本号（未安装时为空）。
  final String installedVersion;

  /// 是否存在可用更新。
  final bool updateExist;

  /// 是否在面板首页显示。
  final bool show;

  /// 运行状态，见 [AppStatus]（未安装时为空字符串）。
  final String status;

  /// 是否支持自定义编译参数（源码编译类应用）。
  final bool customSupported;

  factory AppItem.fromJson(Map<String, dynamic> json) => AppItem(
    name: jsonString(json['name']),
    description: jsonString(json['description']),
    categories: jsonStringList(json['categories']),
    slug: jsonString(json['slug']),
    channels: jsonList(json['channels'], AppChannel.fromJson),
    installed: jsonBool(json['installed']),
    installedChannel: jsonString(json['installed_channel']),
    installedVersion: jsonString(json['installed_version']),
    updateExist: jsonBool(json['update_exist']),
    show: jsonBool(json['show']),
    status: jsonString(json['status']),
    customSupported: jsonBool(json['custom_supported']),
  );

  /// 已安装通道对应的通道信息（找不到时为 null）。
  AppChannel? get currentChannel {
    for (final c in channels) {
      if (c.slug == installedChannel) return c;
    }
    return null;
  }

  /// 可更新到的目标版本（无法确定时为空字符串）。
  String get targetVersion => currentChannel?.version ?? '';

  /// 状态展示文案；未安装或无 systemd 服务的应用返回 null（不展示状态标签）。
  String? get statusLabel {
    if (!installed) return null;
    switch (status) {
      case AppStatus.running:
        return '运行中';
      case AppStatus.stopped:
        return '已停止';
      case AppStatus.partial:
        return '部分运行';
      case AppStatus.na:
        return null;
      default:
        return status.isEmpty ? null : status;
    }
  }

  AppItem copyWith({
    bool? show,
    bool? installed,
    String? installedChannel,
    String? installedVersion,
    bool? updateExist,
    String? status,
  }) {
    return AppItem(
      name: name,
      description: description,
      categories: categories,
      slug: slug,
      channels: channels,
      installed: installed ?? this.installed,
      installedChannel: installedChannel ?? this.installedChannel,
      installedVersion: installedVersion ?? this.installedVersion,
      updateExist: updateExist ?? this.updateExist,
      show: show ?? this.show,
      status: status ?? this.status,
      customSupported: customSupported,
    );
  }
}
