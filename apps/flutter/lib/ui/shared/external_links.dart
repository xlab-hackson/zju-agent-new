import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/models.dart';
import '../../domain/webvpn.dart';

Future<void> openExternal(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !['http', 'https'].contains(uri.scheme)) {
    throw const AppError('INVALID_INPUT', '链接地址无效。');
  }
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    throw const AppError('SERVICE_UNAVAILABLE', '无法打开外部链接。');
  }
}

/// 打开需要校园网才能直接访问的站点。
///
/// 处于校园网（含经 aTrust 等隧道接入）时直接打开；否则先与用户确认，
/// 再决定走 WebVPN 还是坚持直连。校园网判定会受网络切换、探测失败影响，
/// 因此对话框必须保留「仍然直连」这个出口，不能把用户困在 WebVPN 上。
Future<void> openCampusLink(
  BuildContext context,
  Uri uri, {
  required String label,
  required Future<bool> Function() onCampusNetwork,
}) async {
  if (await onCampusNetwork()) return openExternal(uri.toString());
  if (!context.mounted) return;
  final useWebvpn = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('当前不在校园网环境'),
      content: Text('「$label」需要通过校园网访问，也可以改用 WebVPN 打开。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('仍然直连'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('使用 WebVPN 访问'),
        ),
      ],
    ),
  );
  // 取消时 useWebvpn 为 null，此时不打开任何链接。
  if (useWebvpn == null) return;
  return openExternal(
    (useWebvpn ? webvpnUrl(uri) : uri).toString(),
  );
}
