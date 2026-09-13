import 'package:flutter/material.dart';

import '../../application/campus.dart';
import '../../domain/models.dart';
import '../shared/campus_page.dart';
import '../shared/external_links.dart';
import '../shared/ink_tag.dart';
import '../shared/page_empty.dart';
import '../theme.dart';

class SchoolInfoPage extends CampusDataPage {
  const SchoolInfoPage({super.key, required super.services});
  @override
  State<SchoolInfoPage> createState() => _SchoolInfoPageState();
}

class _SchoolInfoPageState extends CampusPageState<SchoolInfoPage> {
  @override
  String get pageKey => '/school-info';
  @override
  String get title => '学校信息';

  String noticeSource = 'all';
  @override
  String? get subtitle => '素质拓展平台与教务系统的最新通知公告，点击条目在浏览器打开原文';
  @override
  String get refreshTooltip => '刷新通知';
  @override
  bool get allowPullRefresh => false;
  @override
  Future<Json> load({bool refresh = false}) =>
      s.campus.notices(refresh: refresh);
  @override
  bool usesCache(String key) => key.startsWith('notices:');
  @override
  PageContext buildPageContext({Json? activeCourse, String? courseTab}) =>
      PageContext.schoolInfo(source: noticeSource);
  @override
  List<Widget> content(Json d, {required bool wide}) {
    final all = rows(d['items']);
    final failures = (d['failures'] as List? ?? []).map((e) => '$e').toList();
    final items = noticeSource == 'all'
        ? all
        : all.where((n) => n['source'] == noticeSource).toList();
    return [
      Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final choice in [
            ('all', '全部'),
            ('sztz', '素质拓展'),
            ('zdbk', '教务系统'),
          ])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(choice.$2),
                selected: noticeSource == choice.$1,
                onSelected: (_) {
                  setState(() => noticeSource = choice.$1);
                  syncPageContext();
                },
              ),
            ),
        ],
      ),
      if (failures.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: gold.withValues(alpha: .1),
            border: Border.all(color: gold.withValues(alpha: .45)),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Row(
            children: [
              const Icon(Icons.notifications_none, color: gold, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  failures.join('；'),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      if (items.isEmpty)
        Paper(
          child: const PageEmpty(icon: 'announcement-horn', title: '暂无通知'),
        )
      else
        for (final notice in items) _noticeCard(notice),
    ];
  }

  Widget _noticeCard(Json notice) {
    final summary = stripHtmlText(text(notice, 'summary'));
    return Paper(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: InkWell(
        onTap: () => act(() => openExternal(text(notice, 'url'))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (notice['important'] == true)
                        const InkTag(label: '置顶', color: seal, filled: true),
                      InkTag(
                        label: notice['source'] == 'sztz' ? '素质拓展' : '教务系统',
                        color: notice['source'] == 'sztz'
                            ? const Color(0xff2e7d32)
                            : seal,
                      ),
                      Text(
                        text(notice, 'title'),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  if (summary.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, height: 1.5),
                      ),
                    ),
                  const SizedBox(height: 7),
                  Text(
                    '${text(notice, 'date')}  ${text(notice, 'publisher')}',
                    style: const TextStyle(fontSize: 11, color: ink),
                  ),
                ],
              ),
            ),
            const Icon(Icons.open_in_new, size: 16, color: gold),
          ],
        ),
      ),
    );
  }
}
