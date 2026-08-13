import 'terminal_messages.dart';

/// 终端会话类型。
///
/// 三种类型都由面板的 `internal/route/ws.go` 提供，握手后的消息协议一致
/// （首帧可能是命令、`{"resize":true,...}` 调整窗口、`{"ping":true}` 心跳），
/// 差异见各字段注释：
/// - [pty]       `/api/ws/pty`，建连后**必须**先发一条命令（`service/ws.go` PTY），
///               输出为二进制帧（`pkg/shell/pty.go` Pipe）；
/// - [ssh]       `/api/ws/ssh?id=<id>`，建连即开 shell，无首帧命令，
///               输出为文本帧（`pkg/ssh/turn.go` Write）；
/// - [container] `/api/ws/container/<id>`，建连即 exec，无首帧命令，
///               输出为文本帧，且服务端**不处理** ping（`pkg/docker/turn.go`）。
enum TerminalSessionKind {
  pty('本机终端'),
  ssh('SSH 终端'),
  container('容器终端');

  const TerminalSessionKind(this.label);

  /// 中文名称。
  final String label;
}

/// 一次终端会话的连接参数（页面通过路由查询参数构造）。
///
/// 路由：`/terminal`
/// - `?command=<cmd>&title=<标题>` —— 本机 PTY，默认执行 `bash`；
/// - `?ssh=<主机 id>&title=<标题>` —— 面板中已保存的 SSH 主机；
/// - `?container=<容器 id>&title=<标题>` —— 容器终端。
class TerminalSessionSpec {
  const TerminalSessionSpec({
    required this.kind,
    required this.title,
    this.command = TerminalWsProtocol.defaultCommand,
    this.targetId = '',
  });

  /// 本机 bash 终端（默认会话）。
  factory TerminalSessionSpec.local() => const TerminalSessionSpec(
        kind: TerminalSessionKind.pty,
        title: '本机终端',
      );

  /// 从路由查询参数构造，参数缺失或非法时回退为本机 bash 终端。
  factory TerminalSessionSpec.fromQuery(Map<String, String> query) {
    final title = (query['title'] ?? '').trim();

    final sshId = (query['ssh'] ?? query['ssh_id'] ?? '').trim();
    if (sshId.isNotEmpty && int.tryParse(sshId) != null) {
      return TerminalSessionSpec(
        kind: TerminalSessionKind.ssh,
        title:
            title.isEmpty ? '${TerminalSessionKind.ssh.label} #$sshId' : title,
        targetId: sshId,
      );
    }

    final containerId = (query['container'] ?? '').trim();
    if (containerId.isNotEmpty) {
      return TerminalSessionSpec(
        kind: TerminalSessionKind.container,
        title: title.isEmpty
            ? '${TerminalSessionKind.container.label} ${_shortId(containerId)}'
            : title,
        targetId: containerId,
      );
    }

    final command = (query['command'] ?? '').trim();
    return TerminalSessionSpec(
      kind: TerminalSessionKind.pty,
      title: title.isEmpty ? TerminalSessionKind.pty.label : title,
      command: command.isEmpty ? TerminalWsProtocol.defaultCommand : command,
    );
  }

  final TerminalSessionKind kind;

  /// 页面标题（服务端下发 OSC 标题后会被覆盖显示）。
  final String title;

  /// PTY 会话要执行的命令（仅 [TerminalSessionKind.pty] 有效）。
  final String command;

  /// SSH 主机 id 或容器 id（[TerminalSessionKind.pty] 时为空）。
  final String targetId;

  /// WebSocket 路径（`/api` 之后的部分，交给 core 的 `wsConnect`）。
  String get wsPath => switch (kind) {
        TerminalSessionKind.pty => '/ws/pty',
        TerminalSessionKind.ssh => '/ws/ssh',
        TerminalSessionKind.container => '/ws/container/$targetId',
      };

  /// WebSocket 查询参数。
  Map<String, String>? get wsQuery =>
      kind == TerminalSessionKind.ssh ? {'id': targetId} : null;

  /// 建连后需要发送的第一条消息（PTY 为要执行的命令，其余为 null）。
  String? get initialMessage =>
      kind == TerminalSessionKind.pty ? command : null;

  /// 服务端是否会响应 `{"ping":true}` 心跳（容器终端不处理 ping）。
  bool get supportsPing => kind != TerminalSessionKind.container;

  /// 服务端 PTY 输出是否为二进制帧（SSH / 容器为文本帧）。
  bool get binaryOutput => kind == TerminalSessionKind.pty;

  /// 副标题：命令 / 目标 id，用于状态栏展示。
  String get subtitle => switch (kind) {
        TerminalSessionKind.pty => command,
        TerminalSessionKind.ssh => 'SSH #$targetId',
        TerminalSessionKind.container => _shortId(targetId),
      };

  /// 反向生成路由查询参数（供其他模块跳转时复用）。
  Map<String, String> toQuery() => switch (kind) {
        TerminalSessionKind.pty => {'command': command, 'title': title},
        TerminalSessionKind.ssh => {'ssh': targetId, 'title': title},
        TerminalSessionKind.container => {
            'container': targetId,
            'title': title
          },
      };

  static String _shortId(String id) =>
      id.length > 12 ? id.substring(0, 12) : id;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TerminalSessionSpec &&
          other.kind == kind &&
          other.title == title &&
          other.command == command &&
          other.targetId == targetId;

  @override
  int get hashCode => Object.hash(kind, title, command, targetId);

  @override
  String toString() =>
      'TerminalSessionSpec(${kind.name}, title: $title, command: $command, '
      'targetId: $targetId)';
}
