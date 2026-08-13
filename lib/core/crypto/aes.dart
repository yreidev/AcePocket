import 'dart:typed_data';

/// AES-256 分组加密（FIPS-197），**只实现加密方向**。
///
/// 项目的依赖政策不允许为一处功能引入密码学库（同样的原因，
/// `core/api/ws_client.dart` 的 RSA-OAEP 也是手写的），因此这里按标准实现
/// AES-256。CTR 模式的加密与解密都只用到分组加密，逆向的 InvSubBytes /
/// InvMixColumns 用不上，不实现可以少一半出错面。
///
/// 正确性由 `test/core/aes_test.dart` 用 FIPS-197 附录 C.3 的官方向量锁定。
class Aes256 {
  /// [key] 必须是 32 字节。
  Aes256(Uint8List key) {
    if (key.length != _keyBytes) {
      throw ArgumentError.value(key.length, 'key.length', '必须为 $_keyBytes 字节');
    }
    _expandKey(key);
  }

  static const int blockSize = 16;
  static const int _keyBytes = 32;

  /// 密钥字数 Nk = 8，轮数 Nr = 14（FIPS-197 表 4）。
  static const int _nk = 8;
  static const int _nr = 14;

  /// 轮密钥，(Nr + 1) * 16 字节。
  final Uint8List _roundKeys = Uint8List((_nr + 1) * blockSize);

  /// 复用的状态缓冲，避免每个分组都分配。
  final Uint8List _state = Uint8List(blockSize);

  void _expandKey(Uint8List key) {
    // 前 Nk 个字直接取自密钥。
    _roundKeys.setRange(0, _keyBytes, key);
    final temp = Uint8List(4);
    for (var i = _nk; i < (_nr + 1) * 4; i++) {
      final prev = (i - 1) * 4;
      temp[0] = _roundKeys[prev];
      temp[1] = _roundKeys[prev + 1];
      temp[2] = _roundKeys[prev + 2];
      temp[3] = _roundKeys[prev + 3];

      if (i % _nk == 0) {
        // RotWord + SubWord + Rcon。
        final t = temp[0];
        temp[0] = _sBox[temp[1]] ^ _rcon[i ~/ _nk];
        temp[1] = _sBox[temp[2]];
        temp[2] = _sBox[temp[3]];
        temp[3] = _sBox[t];
      } else if (i % _nk == 4) {
        // AES-256 特有：每个密钥块的第 4 个字额外过一次 SubWord。
        temp[0] = _sBox[temp[0]];
        temp[1] = _sBox[temp[1]];
        temp[2] = _sBox[temp[2]];
        temp[3] = _sBox[temp[3]];
      }

      final base = i * 4;
      final back = (i - _nk) * 4;
      _roundKeys[base] = _roundKeys[back] ^ temp[0];
      _roundKeys[base + 1] = _roundKeys[back + 1] ^ temp[1];
      _roundKeys[base + 2] = _roundKeys[back + 2] ^ temp[2];
      _roundKeys[base + 3] = _roundKeys[back + 3] ^ temp[3];
    }
  }

  /// 加密 [input] 中从 [inputOffset] 起的一个分组，写入 [output] 的
  /// [outputOffset] 处。两者可以是同一个缓冲。
  void encryptBlock(
    Uint8List input,
    int inputOffset,
    Uint8List output,
    int outputOffset,
  ) {
    final s = _state;
    for (var i = 0; i < blockSize; i++) {
      s[i] = input[inputOffset + i] ^ _roundKeys[i];
    }

    for (var round = 1; round < _nr; round++) {
      _subBytes(s);
      _shiftRows(s);
      _mixColumns(s);
      _addRoundKey(s, round);
    }

    // 末轮没有 MixColumns。
    _subBytes(s);
    _shiftRows(s);
    _addRoundKey(s, _nr);

    output.setRange(outputOffset, outputOffset + blockSize, s);
  }

  void _addRoundKey(Uint8List s, int round) {
    final base = round * blockSize;
    for (var i = 0; i < blockSize; i++) {
      s[i] ^= _roundKeys[base + i];
    }
  }

  static void _subBytes(Uint8List s) {
    for (var i = 0; i < blockSize; i++) {
      s[i] = _sBox[s[i]];
    }
  }

  /// 状态按列主序存放：字节下标 i 对应第 i % 4 行、第 i ~/ 4 列。
  /// 第 r 行整体左移 r 列。
  static void _shiftRows(Uint8List s) {
    // 第 1 行左移 1。
    var t = s[1];
    s[1] = s[5];
    s[5] = s[9];
    s[9] = s[13];
    s[13] = t;

    // 第 2 行左移 2。
    t = s[2];
    s[2] = s[10];
    s[10] = t;
    t = s[6];
    s[6] = s[14];
    s[14] = t;

    // 第 3 行左移 3（等价于右移 1）。
    t = s[15];
    s[15] = s[11];
    s[11] = s[7];
    s[7] = s[3];
    s[3] = t;
  }

  static void _mixColumns(Uint8List s) {
    for (var c = 0; c < 4; c++) {
      final i = c * 4;
      final a0 = s[i];
      final a1 = s[i + 1];
      final a2 = s[i + 2];
      final a3 = s[i + 3];
      s[i] = _xtime(a0) ^ (_xtime(a1) ^ a1) ^ a2 ^ a3;
      s[i + 1] = a0 ^ _xtime(a1) ^ (_xtime(a2) ^ a2) ^ a3;
      s[i + 2] = a0 ^ a1 ^ _xtime(a2) ^ (_xtime(a3) ^ a3);
      s[i + 3] = (_xtime(a0) ^ a0) ^ a1 ^ a2 ^ _xtime(a3);
    }
  }

  /// GF(2^8) 上乘 2，模 x^8 + x^4 + x^3 + x + 1。
  static int _xtime(int b) => ((b << 1) ^ ((b >> 7) * 0x1b)) & 0xff;

  static const List<int> _rcon = <int>[
    0x00,
    0x01,
    0x02,
    0x04,
    0x08,
    0x10,
    0x20,
    0x40,
  ];

  static const List<int> _sBox = <int>[
    0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, //
    0x30, 0x01, 0x67, 0x2b, 0xfe, 0xd7, 0xab, 0x76,
    0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0,
    0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0,
    0xb7, 0xfd, 0x93, 0x26, 0x36, 0x3f, 0xf7, 0xcc,
    0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15,
    0x04, 0xc7, 0x23, 0xc3, 0x18, 0x96, 0x05, 0x9a,
    0x07, 0x12, 0x80, 0xe2, 0xeb, 0x27, 0xb2, 0x75,
    0x09, 0x83, 0x2c, 0x1a, 0x1b, 0x6e, 0x5a, 0xa0,
    0x52, 0x3b, 0xd6, 0xb3, 0x29, 0xe3, 0x2f, 0x84,
    0x53, 0xd1, 0x00, 0xed, 0x20, 0xfc, 0xb1, 0x5b,
    0x6a, 0xcb, 0xbe, 0x39, 0x4a, 0x4c, 0x58, 0xcf,
    0xd0, 0xef, 0xaa, 0xfb, 0x43, 0x4d, 0x33, 0x85,
    0x45, 0xf9, 0x02, 0x7f, 0x50, 0x3c, 0x9f, 0xa8,
    0x51, 0xa3, 0x40, 0x8f, 0x92, 0x9d, 0x38, 0xf5,
    0xbc, 0xb6, 0xda, 0x21, 0x10, 0xff, 0xf3, 0xd2,
    0xcd, 0x0c, 0x13, 0xec, 0x5f, 0x97, 0x44, 0x17,
    0xc4, 0xa7, 0x7e, 0x3d, 0x64, 0x5d, 0x19, 0x73,
    0x60, 0x81, 0x4f, 0xdc, 0x22, 0x2a, 0x90, 0x88,
    0x46, 0xee, 0xb8, 0x14, 0xde, 0x5e, 0x0b, 0xdb,
    0xe0, 0x32, 0x3a, 0x0a, 0x49, 0x06, 0x24, 0x5c,
    0xc2, 0xd3, 0xac, 0x62, 0x91, 0x95, 0xe4, 0x79,
    0xe7, 0xc8, 0x37, 0x6d, 0x8d, 0xd5, 0x4e, 0xa9,
    0x6c, 0x56, 0xf4, 0xea, 0x65, 0x7a, 0xae, 0x08,
    0xba, 0x78, 0x25, 0x2e, 0x1c, 0xa6, 0xb4, 0xc6,
    0xe8, 0xdd, 0x74, 0x1f, 0x4b, 0xbd, 0x8b, 0x8a,
    0x70, 0x3e, 0xb5, 0x66, 0x48, 0x03, 0xf6, 0x0e,
    0x61, 0x35, 0x57, 0xb9, 0x86, 0xc1, 0x1d, 0x9e,
    0xe1, 0xf8, 0x98, 0x11, 0x69, 0xd9, 0x8e, 0x94,
    0x9b, 0x1e, 0x87, 0xe9, 0xce, 0x55, 0x28, 0xdf,
    0x8c, 0xa1, 0x89, 0x0d, 0xbf, 0xe6, 0x42, 0x68,
    0x41, 0x99, 0x2d, 0x0f, 0xb0, 0x54, 0xbb, 0x16,
  ];
}

/// AES-256-CTR：对 [data] 做流式异或，加密与解密是同一个操作。
///
/// 计数块为 `nonce(12 字节) || 计数器(4 字节大端，从 0 开始)`，
/// 因此单次最多可处理 2^32 个分组（64 GB），远超配置备份的体量。
/// **同一密钥下 [nonce] 绝不能重复**，调用方必须用密码学随机数生成。
Uint8List aesCtrXor({
  required Uint8List key,
  required Uint8List nonce,
  required Uint8List data,
}) {
  if (nonce.length != 12) {
    throw ArgumentError.value(nonce.length, 'nonce.length', '必须为 12 字节');
  }
  final cipher = Aes256(key);
  final counterBlock = Uint8List(Aes256.blockSize);
  counterBlock.setRange(0, 12, nonce);
  final keyStream = Uint8List(Aes256.blockSize);
  final out = Uint8List(data.length);

  var counter = 0;
  for (var offset = 0; offset < data.length; offset += Aes256.blockSize) {
    counterBlock[12] = (counter >> 24) & 0xff;
    counterBlock[13] = (counter >> 16) & 0xff;
    counterBlock[14] = (counter >> 8) & 0xff;
    counterBlock[15] = counter & 0xff;
    cipher.encryptBlock(counterBlock, 0, keyStream, 0);

    final end = offset + Aes256.blockSize <= data.length
        ? offset + Aes256.blockSize
        : data.length;
    for (var i = offset; i < end; i++) {
      out[i] = data[i] ^ keyStream[i - offset];
    }
    counter++;
  }
  return out;
}
