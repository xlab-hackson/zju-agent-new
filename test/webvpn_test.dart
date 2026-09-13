import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zju_campus_agent/domain/webvpn.dart';

void main() {
  test('cc98 的 WebVPN 链接与门户生成的结果完全一致', () {
    // 该结果来自 webvpn.zju.edu.cn 实际生成的链接，并已验证可在校外打开。
    expect(
      webvpnUrl(Uri.parse('https://www.cc98.org/')).toString(),
      'https://webvpn.zju.edu.cn/https/'
      '77726476706e69737468656265737421e7e056d22433310830079bab/',
    );
  });

  test('主机名后没有路径时补上 /', () {
    expect(
      webvpnUrl(Uri.parse('https://www.cc98.org')).path,
      '/https/77726476706e69737468656265737421e7e056d22433310830079bab/',
    );
  });

  test('AES-128-CFB 首段密钥流与手工验算一致', () {
    final key = Uint8List.fromList(ascii.encode(webvpnSecret));
    final out = aesCfb128Encrypt(
      key,
      key,
      Uint8List.fromList(ascii.encode('www.cc98.org')),
    );
    expect(
      out.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      'e7e056d22433310830079bab',
    );
  });

  test('带端口的协议作为路径段', () {
    final url = webvpnUrl(Uri.parse('http://10.214.160.13:10002/a/b'));
    expect(url.path.startsWith('/http-10002/'), isTrue);
    expect(url.path.endsWith('/a/b'), isTrue);
  });

  test('路径与查询串原样保留', () {
    final url = webvpnUrl(Uri.parse('https://www.cc98.org/topic/1?page=2'));
    expect(url.path.endsWith('/topic/1'), isTrue);
    expect(url.query, 'page=2');
  });

  test('长主机名跨多个密钥流块（与独立的 .NET CFB-128 实现交叉核对）', () {
    final key = Uint8List.fromList(ascii.encode(webvpnSecret));
    final cipher = aesCfb128Encrypt(
      key,
      key,
      Uint8List.fromList(utf8.encode('booking.lib.zju.edu.cn')),
    );
    // 22 字节，跨越两个密钥流块，覆盖多块反馈路径。
    expect(
      cipher.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      'f2f84e972e3e6f1e72018be2825f367ba51af91afb83',
    );
  });
}
