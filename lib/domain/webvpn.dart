/// 浙江大学 WebVPN（Wengine）链接构造。
///
/// WebVPN 会把目标站点的主机名用 AES-128-CFB 加密后放进路径：
///
///     https://webvpn.zju.edu.cn/{scheme}[-{port}]/{hex(iv) + hex(cipher)}{path}{?query}
///
/// 密钥与初始向量都是固定的 `wrdvpnisthebest!`，而且该常量会以明文 hex 的
/// 形式直接出现在生成后的 URL 里。因此构造链接**不需要登录、也不需要任何
/// 凭据**；这里的加密只用于混淆，不承担保密职责。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart' show AESEngine, KeyParameter;

/// WebVPN 服务地址。
const webvpnBaseUrl = 'https://webvpn.zju.edu.cn';

/// WebVPN 使用的固定密钥与初始向量。
const webvpnSecret = 'wrdvpnisthebest!';

/// AES-128-CFB（整块反馈）加密。
///
/// CFB 是流模式，输出长度与输入一致；每一段的密钥流由前一段密文加密得到，
/// 首段使用初始向量。这里只用到单块 AES 加密，因此直接调用 `processBlock`，
/// 不依赖各版本签名不一致的模式封装。
Uint8List aesCfb128Encrypt(Uint8List key, Uint8List iv, Uint8List input) {
  final engine = AESEngine()..init(true, KeyParameter(key));
  final output = Uint8List(input.length);
  final keystream = Uint8List(16);
  var feedback = Uint8List.fromList(iv);
  for (var offset = 0; offset < input.length; offset += 16) {
    engine.processBlock(feedback, 0, keystream, 0);
    final remaining = input.length - offset;
    final size = remaining < 16 ? remaining : 16;
    for (var i = 0; i < size; i++) {
      output[offset + i] = input[offset + i] ^ keystream[i];
    }
    // 下一段反馈使用本段密文；不足一整块时低位补零。
    feedback = Uint8List(16)..setRange(0, size, output, offset);
  }
  return output;
}

String _hex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// 把目标 [url] 转换为对应的 WebVPN 链接。
///
/// 只有主机名参与加密：协议（带非默认端口时形如 `https-8443`）作为路径段，
/// 路径与查询串原样拼接。主机名之后的路径为空时补 `/`，与门户生成的链接一致。
Uri webvpnUrl(Uri url) {
  final secret = Uint8List.fromList(ascii.encode(webvpnSecret));
  final host = Uint8List.fromList(utf8.encode(url.host));
  final token = _hex(secret) + _hex(aesCfb128Encrypt(secret, secret, host));
  final scheme = url.scheme.toLowerCase();
  final prefix = url.hasPort ? '$scheme-${url.port}' : scheme;
  final path = url.path.isEmpty ? '/' : url.path;
  final query = url.hasQuery ? '?${url.query}' : '';
  return Uri.parse('$webvpnBaseUrl/$prefix/$token$path$query');
}
