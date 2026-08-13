import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../models/server.dart';
import 'api_exception.dart';

/// 拒绝平台安全策略本就不支持的明文面板连接。
///
/// 表单校验负责阻止新增 HTTP 配置；这里是网络层最后一道保护，用于旧版本
/// 已保存的配置以及未来新增的网络通道。
void ensureSecurePanelTransport(ServerConfig server) {
  final uri = Uri.tryParse(server.normalizedBaseUrl);
  if (uri == null || uri.scheme.toLowerCase() != 'https') {
    throw const ApiException('出于安全原因，面板地址必须使用 HTTPS。请先为面板配置 HTTPS，再更新服务器地址');
  }
}

/// 面板 HTTPS 证书的统一校验策略与 [HttpClient] 构造（TOFU：首次信任并固定指纹）。
///
/// App 的**全部**网络通道（core 的 `ApiClient`、WS 登录与握手（ws_client）、
/// 文件传输（transfer_client）、防火墙导入导出（security_raw_api）、
/// 备份上传（backup_transfer））都必须通过 [createPanelHttpClient] 获取
/// [HttpClient]，保证证书校验策略只有这一处实现，任何修复不会遗漏某个通道。
///
/// ## 为什么不能无条件放行自签名证书
///
/// WS 认证要先 `GET /api/user/key` 取 RSA 公钥，再用它加密面板用户名密码
/// `POST /api/user/login`。若对自签名证书无条件放行（包括主机名不匹配、
/// 任意伪造证书），中间人用任意证书接管连接即可替换公钥、解出明文面板密码，
/// 进而通过 `/api/ws/pty` 拿到服务器 root shell —— 信任根被移除后，
/// RSA-OAEP 实现再正确也无济于事。
///
/// ## TOFU 状态机（`badCertificateCallback` 只在系统信任链校验失败时触发）
///
/// 1. `allowSelfSigned == false`：**不设置**回调，完全走系统信任链，
///    自签名 / 无效证书一律握手失败；
/// 2. `allowSelfSigned == true` 且 [ServerConfig.pinnedCertSha256] 非空：
///    只接受 DER 的 SHA-256 指纹与已固定指纹一致的证书，其余一律拒绝，
///    拒绝经 [takeCertificateRejection] 转换为 [CertificateMismatchException]
///    （可能是中间人攻击，也可能是服务器换了证书，文案会引导用户处理）；
/// 3. `allowSelfSigned == true` 且指纹为空（首次连接）：记录证书信息并**拒绝**
///    本次连接，上层把握手失败经 [takeCertificateRejection] 转换为
///    [CertificateTrustRequiredException]，由 UI 弹窗展示指纹 / subject /
///    issuer / 有效期让用户核对；用户确认信任后把指纹写入
///    [ServerConfig.pinnedCertSha256] 并重试连接。
///
/// `badCertificateCallback` 是同步回调且可能在非 UI 线程语境下触发，
/// 绝不能在回调里直接弹窗，因此采用「记录并拒绝 → 上层转换异常 → UI 确认后
/// 写入指纹重试」的流程。
HttpClient createPanelHttpClient(ServerConfig server) {
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 15);
  if (server.allowSelfSigned) {
    client.badCertificateCallback = (cert, host, port) {
      final info = PanelCertificateInfo.fromCertificate(cert, host, port);
      switch (decideCertificate(
        pinnedSha256: server.pinnedCertSha256,
        certSha256Hex: info.sha256Hex,
      )) {
        case CertificateDecision.accepted:
          _lastRejected.remove(server.id);
          return true;
        case CertificateDecision.needsTrust:
          _lastRejected[server.id] = _RejectedCertificate(
            info,
            mismatch: false,
          );
          return false;
        case CertificateDecision.mismatch:
          _lastRejected[server.id] = _RejectedCertificate(info, mismatch: true);
          return false;
      }
    };
  }
  return client;
}

/// 指纹校验的三种结果（对应上方 TOFU 状态机的 2 / 3 两种开启态）。
enum CertificateDecision {
  /// 指纹与已固定指纹一致，放行。
  accepted,

  /// 尚未固定指纹（首次连接），需要用户确认后写入指纹。
  needsTrust,

  /// 指纹与已固定指纹不一致，拒绝。
  mismatch,
}

/// 纯函数形式的指纹判定（便于单元测试）。
///
/// [pinnedSha256] 为已固定的指纹（允许含大小写 / 冒号 / 空白，会先规范化），
/// [certSha256Hex] 为本次握手证书 DER 的 SHA-256 十六进制。
CertificateDecision decideCertificate({
  required String pinnedSha256,
  required String certSha256Hex,
}) {
  final pinned = normalizeFingerprint(pinnedSha256);
  if (pinned.isEmpty) return CertificateDecision.needsTrust;
  return normalizeFingerprint(certSha256Hex) == pinned
      ? CertificateDecision.accepted
      : CertificateDecision.mismatch;
}

/// 对证书 DER 字节求 SHA-256，输出小写十六进制。
String certificateSha256Hex(List<int> der) => sha256.convert(der).toString();

/// 规范化指纹：去掉空白与冒号分隔符，统一为小写。
String normalizeFingerprint(String fingerprint) =>
    fingerprint.replaceAll(RegExp(r'[\s:]'), '').toLowerCase();

/// 两个指纹是否一致（规范化后比较；空指纹不与任何指纹匹配）。
bool fingerprintMatches(String a, String b) {
  final na = normalizeFingerprint(a);
  return na.isNotEmpty && na == normalizeFingerprint(b);
}

/// 每 4 字节（8 个十六进制字符）一组、以空格分隔，便于人工核对指纹。
String formatFingerprintGroups(String fingerprint) {
  final hex = normalizeFingerprint(fingerprint);
  final groups = <String>[];
  for (var i = 0; i < hex.length; i += 8) {
    groups.add(hex.substring(i, i + 8 > hex.length ? hex.length : i + 8));
  }
  return groups.join(' ');
}

/// 一张服务器证书的关键信息（用于 TOFU 确认弹窗展示与指纹固定）。
class PanelCertificateInfo {
  const PanelCertificateInfo({
    required this.sha256Hex,
    required this.subject,
    required this.issuer,
    required this.validFrom,
    required this.validTo,
    required this.host,
    required this.port,
  });

  factory PanelCertificateInfo.fromCertificate(
    X509Certificate cert,
    String host,
    int port,
  ) {
    return PanelCertificateInfo(
      sha256Hex: certificateSha256Hex(cert.der),
      subject: cert.subject,
      issuer: cert.issuer,
      validFrom: cert.startValidity,
      validTo: cert.endValidity,
      host: host,
      port: port,
    );
  }

  /// 证书 DER 的 SHA-256 指纹（小写十六进制，64 字符）。
  final String sha256Hex;

  /// 证书使用者（Subject DN）。
  final String subject;

  /// 证书颁发者（Issuer DN）。
  final String issuer;

  /// 有效期起。
  final DateTime validFrom;

  /// 有效期止。
  final DateTime validTo;

  /// 本次握手的目标主机。
  final String host;

  /// 本次握手的目标端口。
  final int port;

  /// 分组显示的指纹（每 4 字节一段），便于人工核对。
  String get groupedSha256 => formatFingerprintGroups(sha256Hex);
}

/// 首次连接（TOFU）需要用户确认服务器证书。
///
/// 由 [takeCertificateRejection] 在握手失败后抛出（携带证书信息），
/// 服务器表单 / 连接测试流程捕获后弹出证书确认对话框；
/// 其他场景（文件传输、WS 等）直接展示 [message] 引导用户去服务器设置确认。
class CertificateTrustRequiredException implements Exception {
  const CertificateTrustRequiredException(this.serverId, this.certificate);

  /// 对应的 [ServerConfig.id]。
  final String serverId;

  /// 本次握手遇到的证书信息。
  final PanelCertificateInfo certificate;

  String get message =>
      '首次连接该服务器需要确认其身份：'
      '请在服务器设置中执行连接测试，核对证书 SHA-256 指纹后选择信任。'
      '确认后指纹会被记住，日后证书变化时连接将被拒绝。';

  @override
  String toString() => message;
}

/// 服务器证书与已固定指纹不一致，连接被拒绝。
class CertificateMismatchException implements Exception {
  const CertificateMismatchException(
    this.serverId,
    this.certificate,
    this.pinnedSha256,
  );

  /// 对应的 [ServerConfig.id]。
  final String serverId;

  /// 本次握手遇到的（被拒绝的）证书信息。
  final PanelCertificateInfo certificate;

  /// 之前信任的指纹（规范化后的小写十六进制）。
  final String pinnedSha256;

  String get message =>
      '服务器证书与之前信任的指纹不一致，连接已被拒绝。'
      '这可能意味着连接正在被中间人攻击，也可能是服务器更换了证书。'
      '若确认服务器确实更换了证书，请在服务器编辑页清除已记住的证书指纹，'
      '然后重新执行连接测试确认新证书。';

  @override
  String toString() => message;
}

/// 若 [error] 是（或包裹着）由本工厂拒绝证书导致的 TLS 握手失败，
/// 取出记录并返回对应的 [CertificateTrustRequiredException] /
/// [CertificateMismatchException]；否则返回 null（调用方走原有错误处理）。
///
/// 各网络通道在捕获 [DioException] / [HandshakeException] 时应先调用本函数。
Exception? takeCertificateRejection(ServerConfig server, Object error) {
  if (!_isTlsRejection(error)) return null;
  final rejected = _lastRejected.remove(server.id);
  if (rejected == null) return null;
  if (rejected.mismatch) {
    return CertificateMismatchException(
      server.id,
      rejected.info,
      normalizeFingerprint(server.pinnedCertSha256),
    );
  }
  return CertificateTrustRequiredException(server.id, rejected.info);
}

bool _isTlsRejection(Object error) {
  // HandshakeException / CertificateException 均实现 TlsException。
  if (error is TlsException) return true;
  if (error is DioException) {
    if (error.type == DioExceptionType.badCertificate) return true;
    final inner = error.error;
    return inner != null && _isTlsRejection(inner);
  }
  return false;
}

/// 各服务器最近一次被回调拒绝的证书（key 为 [ServerConfig.id]）。
///
/// 回调是同步的，只能在这里暂存证书信息；随后的握手失败由
/// [takeCertificateRejection] 消费（读取后即移除）。
final Map<String, _RejectedCertificate> _lastRejected = {};

class _RejectedCertificate {
  const _RejectedCertificate(this.info, {required this.mismatch});

  final PanelCertificateInfo info;

  /// true 表示与已固定指纹不一致；false 表示尚未固定指纹（待用户确认）。
  final bool mismatch;
}
