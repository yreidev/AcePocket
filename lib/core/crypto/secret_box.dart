import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'aes.dart';

/// 口令加密封装：PBKDF2-HMAC-SHA256 派生密钥 + AES-256-CTR 加密 +
/// HMAC-SHA256 认证（Encrypt-then-MAC）。
///
/// 只用标准构造，不自创算法：CTR 与 HMAC 都是久经检验的组合，比手写 GCM 的
/// GHASH 稳妥得多。加密与认证使用**互相独立**的子密钥（同一次 PBKDF2 输出的
/// 前后两半），避免密钥复用。
///
/// 产物是自描述的 JSON 文本，参数（迭代次数、盐、随机数）随文件保存，
/// 因此以后调高迭代次数也能解开旧文件。

/// PBKDF2 迭代次数。
///
/// 取 OWASP 对 PBKDF2-HMAC-SHA256 的推荐档位。派生是纯 Dart 实现，
/// 低端机上约需一到数秒，因此调用方必须放到 isolate 里跑。
const int kPbkdf2Iterations = 210000;

/// 解密时允许的最大迭代次数，避免恶意信封触发拒绝服务。
const int kMaxPbkdf2Iterations = 1000000;

const String _format = 'acepocket.backup';
const int _version = 1;
const int _saltBytes = 16;
const int _nonceBytes = 12;
const int _subKeyBytes = 32;

/// 文件不是有效的备份，或版本 / 算法不被支持。
class SecretBoxFormatException implements Exception {
  const SecretBoxFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 认证失败：口令错误，或文件内容被改动过。
///
/// 两者不可区分是设计使然——HMAC 校验只回答「这份密文是否由该口令产生且未被
/// 篡改」，对外提示也应保持一致，不要泄露哪一种情况成立。
class SecretBoxAuthException implements Exception {
  const SecretBoxAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// PBKDF2-HMAC-SHA256（RFC 8018）。
Uint8List pbkdf2Sha256({
  required List<int> password,
  required List<int> salt,
  required int iterations,
  required int outputLength,
}) {
  if (iterations < 1) {
    throw ArgumentError.value(iterations, 'iterations', '必须为正数');
  }
  if (outputLength < 1) {
    throw ArgumentError.value(outputLength, 'outputLength', '必须为正数');
  }

  final hmac = Hmac(sha256, password);
  const hashLength = 32;
  final blockCount = (outputLength + hashLength - 1) ~/ hashLength;
  final out = Uint8List(outputLength);

  final block = Uint8List(salt.length + 4);
  block.setRange(0, salt.length, salt);

  for (var i = 1; i <= blockCount; i++) {
    block[salt.length] = (i >> 24) & 0xff;
    block[salt.length + 1] = (i >> 16) & 0xff;
    block[salt.length + 2] = (i >> 8) & 0xff;
    block[salt.length + 3] = i & 0xff;

    var u = Uint8List.fromList(hmac.convert(block).bytes);
    final acc = Uint8List.fromList(u);
    for (var j = 1; j < iterations; j++) {
      u = Uint8List.fromList(hmac.convert(u).bytes);
      for (var k = 0; k < hashLength; k++) {
        acc[k] ^= u[k];
      }
    }

    final start = (i - 1) * hashLength;
    final count = start + hashLength <= outputLength
        ? hashLength
        : outputLength - start;
    out.setRange(start, start + count, acc);
  }
  return out;
}

/// 用 [passphrase] 加密 [plaintext]，返回可直接落盘的 JSON 文本。
///
/// [random] 仅供测试注入确定性随机源；生产必须使用默认的 [Random.secure]。
String sealWithPassphrase({
  required String plaintext,
  required String passphrase,
  int iterations = kPbkdf2Iterations,
  Random? random,
}) {
  final rnd = random ?? Random.secure();
  final salt = Uint8List.fromList(
    List<int>.generate(_saltBytes, (_) => rnd.nextInt(256)),
  );
  final nonce = Uint8List.fromList(
    List<int>.generate(_nonceBytes, (_) => rnd.nextInt(256)),
  );

  final keys = pbkdf2Sha256(
    password: utf8.encode(passphrase),
    salt: salt,
    iterations: iterations,
    outputLength: _subKeyBytes * 2,
  );
  final encKey = Uint8List.sublistView(keys, 0, _subKeyBytes);
  final macKey = Uint8List.sublistView(keys, _subKeyBytes);

  final ciphertext = aesCtrXor(
    key: encKey,
    nonce: nonce,
    data: Uint8List.fromList(utf8.encode(plaintext)),
  );
  final mac = Hmac(sha256, macKey).convert(
    _macInput(
      iterations: iterations,
      salt: salt,
      nonce: nonce,
      ciphertext: ciphertext,
    ),
  );

  return const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
    'format': _format,
    'version': _version,
    'kdf': 'PBKDF2-HMAC-SHA256',
    'iterations': iterations,
    'cipher': 'AES-256-CTR',
    'salt': base64Encode(salt),
    'nonce': base64Encode(nonce),
    'ciphertext': base64Encode(ciphertext),
    'mac': base64Encode(mac.bytes),
  });
}

/// 解密 [sealWithPassphrase] 的产物。
///
/// 结构不合法抛 [SecretBoxFormatException]；口令错误或内容被篡改抛
/// [SecretBoxAuthException]。
String openWithPassphrase({
  required String envelopeJson,
  required String passphrase,
}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(envelopeJson);
  } catch (_) {
    throw const SecretBoxFormatException('文件不是有效的备份（JSON 解析失败）');
  }
  if (decoded is! Map<String, dynamic>) {
    throw const SecretBoxFormatException('文件不是有效的备份');
  }
  if (decoded['format'] != _format) {
    throw const SecretBoxFormatException('文件不是 AcePocket 配置备份');
  }
  if (decoded['version'] != _version) {
    throw SecretBoxFormatException(
      '备份版本 ${decoded['version']} 不受支持，请用更新版本的 App 导入',
    );
  }
  if (decoded['kdf'] != 'PBKDF2-HMAC-SHA256' ||
      decoded['cipher'] != 'AES-256-CTR') {
    throw const SecretBoxFormatException('备份使用了不支持的算法');
  }

  final iterations = decoded['iterations'];
  if (iterations is! int ||
      iterations < 1 ||
      iterations > kMaxPbkdf2Iterations) {
    throw const SecretBoxFormatException('备份的密钥派生参数不合法');
  }

  final salt = _decodeBase64(decoded['salt'], 'salt', _saltBytes);
  final nonce = _decodeBase64(decoded['nonce'], 'nonce', _nonceBytes);
  final mac = _decodeBase64(decoded['mac'], 'mac', 32);
  final rawCiphertext = decoded['ciphertext'];
  if (rawCiphertext is! String) {
    throw const SecretBoxFormatException('备份缺少密文');
  }
  final Uint8List ciphertext;
  try {
    ciphertext = base64Decode(rawCiphertext);
  } catch (_) {
    throw const SecretBoxFormatException('备份的密文编码损坏');
  }

  final keys = pbkdf2Sha256(
    password: utf8.encode(passphrase),
    salt: salt,
    iterations: iterations,
    outputLength: _subKeyBytes * 2,
  );
  final encKey = Uint8List.sublistView(keys, 0, _subKeyBytes);
  final macKey = Uint8List.sublistView(keys, _subKeyBytes);

  final expected = Hmac(sha256, macKey).convert(
    _macInput(
      iterations: iterations,
      salt: salt,
      nonce: nonce,
      ciphertext: ciphertext,
    ),
  );
  // 先验证再解密：认证失败时绝不把任何明文交出去。
  if (!_constantTimeEquals(expected.bytes, mac)) {
    throw const SecretBoxAuthException('口令错误，或备份文件已损坏');
  }

  final plain = aesCtrXor(key: encKey, nonce: nonce, data: ciphertext);
  try {
    return utf8.decode(plain);
  } catch (_) {
    throw const SecretBoxFormatException('备份内容不是合法的 UTF-8 文本');
  }
}

/// MAC 覆盖算法参数与密文全体，防止有人改小迭代次数或换掉 nonce 后重放。
/// salt 与 nonce 长度固定，拼接无歧义。
List<int> _macInput({
  required int iterations,
  required Uint8List salt,
  required Uint8List nonce,
  required Uint8List ciphertext,
}) {
  final header = utf8.encode('$_format.v$_version');
  final out = BytesBuilder(copy: false)
    ..add(header)
    ..add(<int>[
      (iterations >> 24) & 0xff,
      (iterations >> 16) & 0xff,
      (iterations >> 8) & 0xff,
      iterations & 0xff,
    ])
    ..add(salt)
    ..add(nonce)
    ..add(ciphertext);
  return out.takeBytes();
}

Uint8List _decodeBase64(Object? raw, String field, int expectedLength) {
  if (raw is! String) {
    throw SecretBoxFormatException('备份缺少 $field 字段');
  }
  final Uint8List bytes;
  try {
    bytes = base64Decode(raw);
  } catch (_) {
    throw SecretBoxFormatException('备份的 $field 字段编码损坏');
  }
  if (bytes.length != expectedLength) {
    throw SecretBoxFormatException('备份的 $field 字段长度不正确');
  }
  return bytes;
}

/// 定长常量时间比较：比较耗时不随相同前缀的长度变化，避免逐字节试探 MAC。
bool _constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
