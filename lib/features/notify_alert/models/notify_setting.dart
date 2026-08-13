import 'json_utils.dart';

/// 可订阅的系统事件（`internal/biz/notify.go` 的 `NotifyEvent*` 常量）。
class NotifyEventMeta {
  const NotifyEventMeta({
    required this.value,
    required this.label,
    required this.description,
  });

  /// 接口取值。
  final String value;

  /// 中文名称。
  final String label;

  /// 说明文案。
  final String description;
}

/// 全部可订阅事件（顺序与面板前端一致）。
const List<NotifyEventMeta> kNotifyEvents = <NotifyEventMeta>[
  NotifyEventMeta(
    value: 'cert_renew',
    label: '证书续签失败',
    description: 'ACME 证书自动续签出错时通知',
  ),
  NotifyEventMeta(
    value: 'backup',
    label: '备份失败',
    description: '网站 / 数据库 / 面板备份任务失败时通知',
  ),
  NotifyEventMeta(
    value: 'task_failed',
    label: '后台任务失败',
    description: '任务中心的后台任务执行失败时通知',
  ),
  NotifyEventMeta(
    value: 'cron_failed',
    label: '计划任务执行失败',
    description: '计划任务返回非零退出码时通知',
  ),
  NotifyEventMeta(
    value: 'website_expire',
    label: '网站到期关停',
    description: '网站到达到期时间被自动关停时通知',
  ),
  NotifyEventMeta(
    value: 'tamper',
    label: '防篡改拦截',
    description: '防篡改规则拦截到写入操作时通知',
  ),
  NotifyEventMeta(value: 'health', label: '面板健康问题', description: '面板自检发现异常时通知'),
  NotifyEventMeta(value: 'login', label: '面板登录', description: '有账号登录面板时通知'),
  NotifyEventMeta(
    value: 'login_failed',
    label: '面板登录失败过多',
    description: '面板登录连续失败触发限制时通知',
  ),
  NotifyEventMeta(
    value: 'ssh_login',
    label: 'SSH 登录',
    description: '检测到 SSH 登录成功时通知',
  ),
  NotifyEventMeta(
    value: 'ssh_bruteforce',
    label: 'SSH 爆破尝试',
    description: '检测到 SSH 密码爆破时通知',
  ),
];

/// 事件通知设置（`request.NotifySetting`）。
class NotifySetting {
  const NotifySetting({required this.events, required this.channels});

  /// 已订阅的事件列表。
  final List<String> events;

  /// 接收事件通知的渠道 ID 列表。
  final List<int> channels;

  static const NotifySetting empty = NotifySetting(
    events: <String>[],
    channels: <int>[],
  );

  factory NotifySetting.fromJson(Map<String, dynamic> json) => NotifySetting(
    events: jsonStringList(json['events']),
    channels: jsonIntList(json['channels']),
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'events': events,
    'channels': channels,
  };

  NotifySetting copyWith({List<String>? events, List<int>? channels}) =>
      NotifySetting(
        events: events ?? this.events,
        channels: channels ?? this.channels,
      );

  /// 值相等（列表逐元素比较）。
  ///
  /// 事件通知页用它判断草稿与服务端当前值是否一致：勾了又取消、改回原样时
  /// 不应再被当成「未保存的修改」拦截返回。
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NotifySetting &&
          _sameItems<String>(events, other.events) &&
          _sameItems<int>(channels, other.channels);

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(events),
    Object.hashAllUnordered(channels),
  );

  /// 忽略顺序比较：勾选顺序不同但内容相同的两份设置等价
  /// （面板侧 events / channels 都按集合语义处理）。
  static bool _sameItems<T>(List<T> a, List<T> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    final rest = List<T>.from(b);
    for (final item in a) {
      if (!rest.remove(item)) return false;
    }
    return true;
  }
}
