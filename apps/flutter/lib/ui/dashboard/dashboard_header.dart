import 'package:flutter/material.dart';

import '../../domain/formatters.dart';
import '../../domain/models.dart';
import '../avatar.dart';
import '../shared/ink_tag.dart';
import '../theme.dart';

class DashboardHeader extends StatelessWidget {
  const DashboardHeader({
    super.key,
    required this.name,
    required this.info,
    required this.campusStatus,
    required this.avatarDataUrl,
    required this.updatedLabel,
    required this.onRefresh,
  });
  final String name, campusStatus, avatarDataUrl;
  final Json info;
  final String? updatedLabel;
  final VoidCallback onRefresh;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 30),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${DateTime.now().year} 年   ${monthName(DateTime.now().month)} ${DateTime.now().day}   ${weekday(DateTime.now().weekday)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: gold,
                  fontSize: 12,
                  letterSpacing: 2,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(height: 1, color: gold.withValues(alpha: .45)),
            ),
            IconButton(
              onPressed: onRefresh,
              tooltip: '刷新工作台',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              icon: const Icon(Icons.refresh, size: 18),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            UserAvatar(dataUrl: avatarDataUrl, radius: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '你好，$name',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (info.isNotEmpty)
                        InkTag(
                          label:
                              '${text(info, 'semesterId')} · ${text(info, 'weekString', '本学期')}',
                          color: blue,
                        ),
                      if (info['isHoliday'] == true)
                        InkTag(
                          label: '休：${text(info, 'holidayName', '放假')}',
                          color: gold,
                          dot: true,
                        ),
                      InkTag(
                        label: switch (campusStatus) {
                          'connected' => '教务已同步',
                          'invalid' => '登录已失效',
                          'unknown' => '待验证登录',
                          _ => '待绑定账号',
                        },
                        color: campusStatus == 'connected'
                            ? const Color(0xff2e7d32)
                            : gold,
                        dot: true,
                      ),
                    ],
                  ),
                  if (updatedLabel != null) ...[
                    const SizedBox(height: 7),
                    Text(
                      updatedLabel!,
                      style: TextStyle(
                        fontSize: 11,
                        color: ink.withValues(alpha: .58),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Transform.rotate(
              angle: .08,
              child: Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(color: seal, width: 2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '浙大\n助手',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: seal, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
