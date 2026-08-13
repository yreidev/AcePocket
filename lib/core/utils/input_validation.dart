/// 通用输入校验（域名、监听地址、邮箱、IP/CIDR、文件名）。
///
/// 与 `url_validation.dart` 同一风格：纯函数、返回 null 表示通过，
/// 否则返回能指导用户改对的中文文案。各模块专有的校验
/// （PEM、数据库主机、LVM 名称等）放在各自模块的 utils 中。
library;

import 'dart:io';

/// 单个域名标签（label）：字母 / 数字 / 下划线开头结尾，中间可含短横线。
/// 使用 Unicode 属性类以支持 IDN（如 中文.example.com）。
final RegExp _domainLabelPattern = RegExp(
  r'^[\p{L}\p{N}_]([\p{L}\p{N}_\-]*[\p{L}\p{N}_])?$',
  unicode: true,
);

/// 校验域名，如 `example.com`、`*.example.com`（泛域名）、IDN 域名。
///
/// 返回 null 表示通过。允许直接填 IP（网站可按 IP 访问）；
/// [allowWildcard] 为 false 时拒绝泛域名（如 SMTP 服务器地址）。
String? validateDomain(String input, {bool allowWildcard = true}) {
  final v = input.trim();
  if (v.isEmpty) return '请输入域名';
  if (v.contains('://')) {
    return '只填域名，不要带 http:// 等协议前缀';
  }
  if (v.contains('/')) {
    return '只填域名，不要带路径（/ 及其后的内容）';
  }
  if (v.contains('@')) {
    return '域名不应包含 @，只填如 example.com';
  }
  if (v.contains(RegExp(r'\s'))) {
    return '域名不能包含空格';
  }

  // 直接填 IP 视为合法（nginx server_name 支持 IP）。
  if (InternetAddress.tryParse(v) != null) return null;

  if (v.contains(':')) {
    return '域名不要带端口，端口请填在对应的端口设置中';
  }

  // 全为数字和点：按写错的 IPv4 处理，避免 999.999.999.999 这类值蒙混过关。
  if (RegExp(r'^[\d.]+$').hasMatch(v)) {
    return '看起来像 IPv4 地址但不合法（每段需在 0-255 之间），如 192.0.2.1';
  }

  var host = v;
  if (host.startsWith('*')) {
    if (!allowWildcard) {
      return '这里不支持泛域名，请填写具体域名，如 example.com';
    }
    if (!host.startsWith('*.') || host.length <= 2) {
      return '泛域名应写成 *.example.com 的形式（* 后跟点和主域名）';
    }
    host = host.substring(2);
  }
  if (host.contains('*')) {
    return '通配符 * 只能作为最前面的一级，如 *.example.com';
  }
  if (host.length > 253) {
    return '域名过长（最多 253 个字符）';
  }

  final labels = host.split('.');
  for (final label in labels) {
    if (label.isEmpty) {
      return '域名不能以点开头/结尾，也不能出现连续的点';
    }
    if (label.length > 63) {
      return '域名单级（两个点之间）最多 63 个字符';
    }
    if (!_domainLabelPattern.hasMatch(label)) {
      return '域名只能包含字母、数字、短横线和点，且每级不能以短横线开头或结尾';
    }
  }
  return null;
}

/// 校验网站监听地址，支持三种形态：
/// `80`（纯端口）、`192.0.2.1:80`（IPv4:端口）、`[::]:443`（IPv6:端口）。
///
/// 返回 null 表示通过；端口需在 1-65535 范围内。
String? validateListenAddress(String input) {
  final v = input.trim();
  if (v.isEmpty) return '请输入监听地址，如 80、0.0.0.0:80 或 [::]:443';
  if (v.contains('://')) {
    return '监听地址不要带协议前缀，填 80、0.0.0.0:80 或 [::]:443 这类形式';
  }
  if (v.contains(RegExp(r'\s'))) {
    return '监听地址不能包含空格';
  }

  // 纯端口。
  if (RegExp(r'^\d+$').hasMatch(v)) return _checkListenPort(v);

  // [IPv6]:端口。
  if (v.startsWith('[')) {
    final close = v.indexOf(']');
    if (close < 0) {
      return 'IPv6 地址的方括号没有闭合，应写成 [::]:443 的形式';
    }
    final ip = v.substring(1, close);
    final addr = InternetAddress.tryParse(ip);
    if (addr == null || addr.type != InternetAddressType.IPv6) {
      return '方括号内应为合法的 IPv6 地址，如 [::]:443 或 [2001:db8::1]:80';
    }
    final rest = v.substring(close + 1);
    if (rest.isEmpty) {
      return '缺少端口，请在 ] 后加 :端口，如 [$ip]:80';
    }
    if (!rest.startsWith(':')) {
      return '端口需用冒号分隔，如 [$ip]:80';
    }
    return _checkListenPort(rest.substring(1));
  }

  final colon = v.lastIndexOf(':');
  if (colon < 0) {
    if (InternetAddress.tryParse(v) != null) {
      return '请补充端口，如 $v:80';
    }
    return '监听地址应为端口（80）、IP:端口（0.0.0.0:80）或 [::]:443';
  }

  final host = v.substring(0, colon);
  final port = v.substring(colon + 1);
  final hostAddr = InternetAddress.tryParse(host);
  if (hostAddr == null) {
    // 形如 ::1 或 2001:db8::1 的裸 IPv6（没有方括号）。
    final whole = InternetAddress.tryParse(v);
    if (whole != null && whole.type == InternetAddressType.IPv6) {
      return 'IPv6 地址需要加方括号并带端口，如 [$v]:80';
    }
    return 'IP 部分不合法，应形如 0.0.0.0:80；IPv6 请写成 [::]:443';
  }
  if (hostAddr.type == InternetAddressType.IPv6) {
    return 'IPv6 地址需要加方括号，如 [$host]:$port';
  }
  return _checkListenPort(port);
}

String? _checkListenPort(String portText) {
  if (portText.isEmpty) return '缺少端口号，如 80';
  final port = int.tryParse(portText);
  if (port == null) return '端口应为数字，如 80';
  if (port < 1 || port > 65535) return '端口需在 1-65535 之间';
  return null;
}

/// 邮箱本地部分（@ 前）允许的字符。
final RegExp _emailLocalPattern = RegExp(
  r"^[A-Za-z0-9!#$%&'*+/=?^_`{|}~.\-]+$",
);

/// 校验邮箱地址的基本格式（`user@example.com`）。
///
/// 返回 null 表示通过。不做 DNS 层面的存在性校验。
String? validateEmail(String input) {
  final v = input.trim();
  if (v.isEmpty) return '请输入邮箱地址';
  if (v.contains(RegExp(r'\s'))) return '邮箱不能包含空格';
  final at = v.indexOf('@');
  if (at < 0) return '邮箱缺少 @，应形如 user@example.com';
  if (v.indexOf('@', at + 1) >= 0) return '邮箱只能包含一个 @';
  final local = v.substring(0, at);
  final domain = v.substring(at + 1);
  if (local.isEmpty) return '@ 前缺少用户名，应形如 user@example.com';
  if (domain.isEmpty) return '@ 后缺少域名，应形如 user@example.com';
  if (!_emailLocalPattern.hasMatch(local)) {
    return '邮箱 @ 前包含不支持的字符';
  }
  if (local.startsWith('.') || local.endsWith('.') || local.contains('..')) {
    return '邮箱 @ 前的点号位置不正确（不能开头、结尾或连续出现）';
  }
  if (validateDomain(domain, allowWildcard: false) != null) {
    return '@ 后的域名格式不正确，应形如 user@example.com';
  }
  return null;
}

/// 校验单个 IP 地址（IPv4 或 IPv6）。
///
/// [family] 传 `ipv4` / `ipv6` 时要求地址类型与之匹配（用于防火墙表单
/// 已选定网络协议的场景）；返回 null 表示通过。
String? validateIpAddress(String input, {String? family}) {
  final v = input.trim();
  if (v.isEmpty) return '请输入 IP 地址';
  final addr = InternetAddress.tryParse(v);
  if (addr == null) {
    if (v.contains('/')) {
      return '这里只能填单个 IP，不能带 / 前缀长度';
    }
    return '不是合法的 IP 地址，应形如 192.0.2.1 或 2001:db8::1';
  }
  if (family == 'ipv4' && addr.type != InternetAddressType.IPv4) {
    return '当前选择了 IPv4，请填写 IPv4 地址（如 192.0.2.1），或改选 IPv6';
  }
  if (family == 'ipv6' && addr.type != InternetAddressType.IPv6) {
    return '当前选择了 IPv6，请填写 IPv6 地址（如 2001:db8::1），或改选 IPv4';
  }
  return null;
}

/// 校验 IP 或 CIDR 网段（如 `192.0.2.1`、`192.0.2.0/24`、`2001:db8::/32`）。
///
/// 前缀长度上限：IPv4 为 32，IPv6 为 128。[family] 含义同 [validateIpAddress]。
String? validateIpOrCidr(String input, {String? family}) {
  final v = input.trim();
  if (v.isEmpty) return '请输入 IP 地址或网段';
  final slash = v.indexOf('/');
  if (slash < 0) return validateIpAddress(v, family: family);

  final ipPart = v.substring(0, slash);
  final prefixPart = v.substring(slash + 1);
  final ipError = validateIpAddress(ipPart, family: family);
  if (ipError != null) return ipError;

  final prefix = int.tryParse(prefixPart);
  if (prefix == null) {
    return '/ 后应为前缀长度数字，如 192.0.2.0/24';
  }
  final addr = InternetAddress.tryParse(ipPart)!;
  final max = addr.type == InternetAddressType.IPv4 ? 32 : 128;
  if (prefix < 0 || prefix > max) {
    return addr.type == InternetAddressType.IPv4
        ? 'IPv4 的前缀长度需在 0-32 之间，如 192.0.2.0/24'
        : 'IPv6 的前缀长度需在 0-128 之间，如 2001:db8::/32';
  }
  return null;
}

/// 校验文件 / 目录名称（单级名称，不是路径）。
///
/// 拦截空白名、`.`、`..`、包含 `/` 与控制字符的名称。
String? validateFileName(String input) {
  final v = input.trim();
  if (v.isEmpty) return '名称不能为空';
  if (v == '.' || v == '..') {
    return '名称不能是 . 或 ..（它们表示当前/上级目录）';
  }
  if (v.contains('/')) {
    return '名称不能包含 /，如需放入子目录请先进入该目录';
  }
  if (v.runes.any((r) => r < 0x20 || r == 0x7f)) {
    return '名称不能包含换行等控制字符';
  }
  return null;
}
