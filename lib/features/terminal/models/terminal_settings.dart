/// 终端偏好设置（保存在 shared_preferences）。
class TerminalSettings {
  const TerminalSettings({
    this.fontSize = defaultFontSize,
    this.showKeyboardBar = true,
    this.scrollback = defaultScrollback,
    this.autoReconnect = true,
  });

  /// 从持久化的 JSON 还原，字段缺失 / 类型不符时回退默认值。
  factory TerminalSettings.fromJson(Map<String, dynamic> json) {
    final rawFont = json['font_size'];
    final rawScrollback = json['scrollback'];
    return TerminalSettings(
      fontSize: rawFont is num
          ? rawFont.toDouble().clamp(minFontSize, maxFontSize).toDouble()
          : defaultFontSize,
      showKeyboardBar: json['show_keyboard_bar'] is bool
          ? json['show_keyboard_bar'] as bool
          : true,
      scrollback: rawScrollback is num
          ? rawScrollback.toInt().clamp(minScrollback, maxScrollback).toInt()
          : defaultScrollback,
      autoReconnect: json['auto_reconnect'] is bool
          ? json['auto_reconnect'] as bool
          : true,
    );
  }

  static const double minFontSize = 9;
  static const double maxFontSize = 24;
  static const double defaultFontSize = 13;

  static const int minScrollback = 500;
  static const int maxScrollback = 20000;
  static const int defaultScrollback = 3000;

  /// 终端字号。
  final double fontSize;

  /// 是否展示快捷键条。
  final bool showKeyboardBar;

  /// 回滚缓冲行数（新建会话时生效）。
  final int scrollback;

  /// 断线后是否自动尝试重连一次。
  final bool autoReconnect;

  TerminalSettings copyWith({
    double? fontSize,
    bool? showKeyboardBar,
    int? scrollback,
    bool? autoReconnect,
  }) {
    return TerminalSettings(
      fontSize: fontSize ?? this.fontSize,
      showKeyboardBar: showKeyboardBar ?? this.showKeyboardBar,
      scrollback: scrollback ?? this.scrollback,
      autoReconnect: autoReconnect ?? this.autoReconnect,
    );
  }

  Map<String, dynamic> toJson() => {
    'font_size': fontSize,
    'show_keyboard_bar': showKeyboardBar,
    'scrollback': scrollback,
    'auto_reconnect': autoReconnect,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TerminalSettings &&
          other.fontSize == fontSize &&
          other.showKeyboardBar == showKeyboardBar &&
          other.scrollback == scrollback &&
          other.autoReconnect == autoReconnect;

  @override
  int get hashCode =>
      Object.hash(fontSize, showKeyboardBar, scrollback, autoReconnect);
}
