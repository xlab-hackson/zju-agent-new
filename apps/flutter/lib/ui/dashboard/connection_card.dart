import 'package:flutter/material.dart';

import '../shared/ink_tag.dart';
import '../theme.dart';

class ConnectionCard extends StatelessWidget {
  const ConnectionCard({
    super.key,
    required this.title,
    required this.ok,
    required this.detail,
    required this.action,
    this.configured = false,
    this.statusLabel,
  });
  final String title, detail;
  final bool ok;
  final bool configured;
  final String? statusLabel;
  final VoidCallback action;
  @override
  Widget build(BuildContext context) => Paper(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            InkTag(
              label: statusLabel ?? (ok ? '已连接' : '未配置'),
              color: ok ? const Color(0xff2e7d32) : gold,
              dot: true,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(detail, style: const TextStyle(fontSize: 12, color: ink)),
        const SizedBox(height: 12),
        TextButton(
          onPressed: action,
          child: Text(ok || configured ? '管理配置  →' : '立即配置  →'),
        ),
      ],
    ),
  );
}
