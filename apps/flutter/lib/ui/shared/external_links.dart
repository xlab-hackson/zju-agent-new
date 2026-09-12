import 'package:url_launcher/url_launcher.dart';

import '../../domain/models.dart';

Future<void> openExternal(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !['http', 'https'].contains(uri.scheme)) {
    throw const AppError('INVALID_INPUT', '链接地址无效。');
  }
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    throw const AppError('SERVICE_UNAVAILABLE', '无法打开外部链接。');
  }
}
