/// 数据库模块专有：数据库用户「允许访问的主机」校验。
library;

import 'dart:io';

import '../../../core/utils/input_validation.dart';

final RegExp _hostPatternChars = RegExp(r'^[A-Za-z0-9%_.:\-]+$');

/// 校验 MySQL 风格的用户主机限制。
///
/// 允许：`%`、`localhost`、IP（IPv4/IPv6）、主机名、
/// 含 `%`/`_` 通配符的模式（如 `192.0.2.%`）、
/// `IP/掩码` 网段（如 `192.0.2.0/255.255.255.0`）。
/// 返回 null 表示通过。
String? validateDbUserHost(String input) {
  final v = input.trim();
  if (v.isEmpty) return '请填写允许访问的主机，如 192.0.2.10，任意主机填 %';
  if (v == '%' || v == 'localhost') return null;
  if (v.contains(RegExp(r'\s'))) return '主机不能包含空格';

  // IP/掩码 形式的网段。
  if (v.contains('/')) {
    final parts = v.split('/');
    if (parts.length != 2 || !_isIpv4(parts[0]) || !_isIpv4(parts[1])) {
      return '网段请写成 IP/子网掩码 的形式，如 192.0.2.0/255.255.255.0';
    }
    return null;
  }

  // 含通配符的模式（MySQL 的 % 与 _）只做字符集检查。
  if (v.contains('%')) {
    if (!_hostPatternChars.hasMatch(v)) {
      return '主机只能包含字母、数字、点、冒号、短横线、下划线和 % 通配符';
    }
    return null;
  }

  if (InternetAddress.tryParse(v) != null) return null;
  if (validateDomain(v, allowWildcard: false) == null) return null;
  return '应为 IP、主机名或含 % 的模式，如 192.0.2.10、db.example.com、192.0.2.%';
}

bool _isIpv4(String text) {
  final addr = InternetAddress.tryParse(text);
  return addr != null && addr.type == InternetAddressType.IPv4;
}
