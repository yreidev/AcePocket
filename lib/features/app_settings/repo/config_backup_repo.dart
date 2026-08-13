import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/crypto/secret_box.dart';
import '../../../core/models/server.dart';
import '../../../core/storage/server_store.dart';
import '../models/config_backup.dart';

/// 配置备份的加解密与文件负载构造。
///
/// 备份里含 API 令牌与面板登录密码，因此**只以口令加密后的形式**离开安全存储：
/// 明文 JSON 绝不落盘，也不进日志。加密细节见 `core/crypto/secret_box.dart`。
///
/// 密钥派生（PBKDF2 21 万次迭代）是纯 Dart 实现，主线程跑会明显卡顿，
/// 因此 [encode] / [decode] 都通过 [compute] 放到后台 isolate。
class ConfigBackupRepo {
  const ConfigBackupRepo();

  /// 备份文件名前缀，落盘时会补上时间戳。
  static const String fileNamePrefix = 'acepocket-backup';

  /// 口令最小长度。
  ///
  /// 备份文件可能被同步到网盘或聊天工具，一旦泄露就只剩这道口令挡在
  /// API 令牌前面，太短的口令离线爆破成本极低。
  static const int minPassphraseLength = 8;

  /// 采集当前设备上的全部可备份配置。
  Future<ConfigBackup> collect({required BackupPreferences preferences}) async {
    await ServerStore.instance.init();
    return ConfigBackup(
      servers: ServerStore.instance.servers,
      activeServerId: ServerStore.instance.activeId,
      preferences: preferences,
      createdAt: DateTime.now(),
      appVersion: await _appVersion(),
    );
  }

  /// 加密为可落盘的文本。
  Future<String> encode(ConfigBackup backup, String passphrase) {
    final plaintext = jsonEncode(backup.toJson());
    return compute(
      _sealInIsolate,
      _SealRequest(plaintext: plaintext, passphrase: passphrase),
    );
  }

  /// 解密并解析备份文件。
  ///
  /// 口令错误或文件被篡改抛 [SecretBoxAuthException]，
  /// 结构不合法抛 [SecretBoxFormatException]。
  Future<ConfigBackup> decode(String fileContent, String passphrase) async {
    final plaintext = await compute(
      _openInIsolate,
      _OpenRequest(envelopeJson: fileContent, passphrase: passphrase),
    );
    final Object? decoded;
    try {
      decoded = jsonDecode(plaintext);
    } catch (_) {
      throw const SecretBoxFormatException('备份内容损坏，无法解析');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const SecretBoxFormatException('备份内容格式不正确');
    }
    return ConfigBackup.fromJson(decoded);
  }

  /// 把服务器配置写回安全存储。
  ///
  /// [merge] 的含义见 [mergeServers]。
  Future<void> restoreServers(
    ConfigBackup backup, {
    required bool merge,
  }) async {
    await ServerStore.instance.init();
    final localActiveId = ServerStore.instance.activeId;
    final next = merge
        ? mergeServers(ServerStore.instance.servers, backup.servers)
        : backup.servers;
    await ServerStore.instance.saveServers(next);
    await ServerStore.instance.saveActiveId(
      resolveActiveId(
        next,
        backup.activeServerId,
        fallback: merge ? localActiveId : null,
      ),
    );
  }

  Future<String> _appVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return info.version;
    } catch (_) {
      // 拿不到版本不影响备份本身。
      return '';
    }
  }
}

/// 按 id 合并本机与备份的服务器列表：同 id 以备份为准，备份独有的追加在后，
/// 本机独有的保留。
///
/// 保持本机原有顺序，避免导入后列表整体重排、用户找不到常用的那台。
List<ServerConfig> mergeServers(
  List<ServerConfig> local,
  List<ServerConfig> incoming,
) {
  final byId = <String, ServerConfig>{
    for (final server in local) server.id: server,
  };
  for (final server in incoming) {
    byId[server.id] = server;
  }
  return byId.values.toList();
}

/// 选出导入后应当激活的服务器。
///
/// 依次尝试备份选中项、本机选中项，最后退回第一台。列表为空时返回 null。
String? resolveActiveId(
  List<ServerConfig> servers,
  String? desired, {
  String? fallback,
}) {
  if (servers.isEmpty) return null;
  if (desired != null && servers.any((s) => s.id == desired)) return desired;
  if (fallback != null && servers.any((s) => s.id == fallback)) return fallback;
  return servers.first.id;
}

class _SealRequest {
  const _SealRequest({required this.plaintext, required this.passphrase});

  final String plaintext;
  final String passphrase;
}

class _OpenRequest {
  const _OpenRequest({required this.envelopeJson, required this.passphrase});

  final String envelopeJson;
  final String passphrase;
}

String _sealInIsolate(_SealRequest request) => sealWithPassphrase(
  plaintext: request.plaintext,
  passphrase: request.passphrase,
);

String _openInIsolate(_OpenRequest request) => openWithPassphrase(
  envelopeJson: request.envelopeJson,
  passphrase: request.passphrase,
);
