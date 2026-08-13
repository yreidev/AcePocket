/// 证书模块专有：PEM 格式的基本校验。
///
/// 只做结构性检查（BEGIN/END 标记与 Base64 正文），
/// 证书内容是否有效最终由面板解析确认。
library;

const String _certBegin = '-----BEGIN CERTIFICATE-----';
const String _certEnd = '-----END CERTIFICATE-----';

final RegExp _keyBeginPattern = RegExp(
  r'-----BEGIN (RSA |EC |ENCRYPTED |OPENSSH )?PRIVATE KEY-----',
);
final RegExp _keyEndPattern = RegExp(
  r'-----END (RSA |EC |ENCRYPTED |OPENSSH )?PRIVATE KEY-----',
);

/// PEM 正文（去掉标记行后的内容）应为 Base64 字符。
final RegExp _base64BodyPattern = RegExp(r'^[A-Za-z0-9+/=]+$');

/// 校验 PEM 证书文本（fullchain.pem，可含多段证书）。返回 null 表示通过。
String? validatePemCertificate(String input) {
  final v = input.trim();
  if (v.isEmpty) return '请粘贴证书内容';
  if (_keyBeginPattern.hasMatch(v)) {
    return '这里应粘贴证书，私钥请填在私钥输入框中';
  }
  if (!v.startsWith(_certBegin)) {
    return '证书应为 PEM 文本，以 $_certBegin 开头，'
        '请粘贴 fullchain.pem 的完整内容';
  }
  if (!v.contains(_certEnd)) {
    return '证书缺少 $_certEnd 结尾，可能没有粘贴完整';
  }
  final begins = _certBegin.allMatches(v).length;
  final ends = _certEnd.allMatches(v).length;
  if (begins != ends) {
    return '证书的 BEGIN 与 END 标记数量不一致（$begins 个 BEGIN、$ends 个 END），'
        '请检查是否粘贴完整';
  }
  final bodyStart = v.indexOf(_certBegin) + _certBegin.length;
  final bodyEnd = v.indexOf(_certEnd);
  final body = v.substring(bodyStart, bodyEnd).replaceAll(RegExp(r'\s'), '');
  if (body.isEmpty || !_base64BodyPattern.hasMatch(body)) {
    return '证书正文不是有效的 Base64 内容，请重新完整复制证书文件';
  }
  return null;
}

/// 校验 PEM 私钥文本（PKCS#8 / RSA / EC 等）。返回 null 表示通过。
String? validatePemPrivateKey(String input) {
  final v = input.trim();
  if (v.startsWith(_certBegin)) {
    return '这里应粘贴私钥，证书请填在证书输入框中';
  }
  if (v.isEmpty) return '请粘贴私钥内容';
  final begin = _keyBeginPattern.firstMatch(v);
  if (begin == null || begin.start != 0) {
    return '私钥应为 PEM 文本，以 -----BEGIN PRIVATE KEY----- '
        '或 -----BEGIN RSA PRIVATE KEY----- 开头';
  }
  final end = _keyEndPattern.firstMatch(v);
  if (end == null) {
    return '私钥缺少 -----END … PRIVATE KEY----- 结尾，可能没有粘贴完整';
  }
  final body = v.substring(begin.end, end.start).replaceAll(RegExp(r'\s'), '');
  if (body.isEmpty || !_base64BodyPattern.hasMatch(body)) {
    return '私钥正文不是有效的 Base64 内容，请重新完整复制私钥文件';
  }
  return null;
}
