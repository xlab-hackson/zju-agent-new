import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../application/page_loaders/downloads_loader.dart';
import '../../domain/models.dart';
import '../downloads/download_card.dart';
import '../shared/campus_page.dart';
import '../shared/page_empty.dart';
import '../shared/page_header.dart';
import '../theme.dart';

class DownloadsPage extends CampusDataPage {
  const DownloadsPage({super.key, required super.services});
  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends CampusPageState<DownloadsPage> {
  @override
  String get pageKey => '/downloads';
  @override
  String get title => '下载中心';

  @override
  bool get usesNetworkCache => false;
  @override
  Future<Json> load({bool refresh = false}) => loadDownloadsPage(s);
  @override
  PageContext buildPageContext({Json? activeCourse, String? courseTab}) =>
      PageContext.downloads();
  @override
  List<Widget> content(Json d, {required bool wide}) {
    final files = rows(d['items']);
    final courseNames = <String, String>{
      for (final course in rows(d['courses'] ?? []))
        text(course, 'id'): text(course, 'name'),
    };
    final grouped = <String, List<Json>>{};
    final groupNames = <String, String>{};
    for (final file in files) {
      final courseId = text(file, 'courseId');
      final storedName = text(file, 'courseName').trim();
      final storedFolder = text(file, 'courseFolder').trim();
      final lookedUpName = courseNames[courseId]?.trim() ?? '';
      final courseName = storedName.isNotEmpty
          ? storedName
          : lookedUpName.isNotEmpty
          ? lookedUpName
          : storedFolder.isNotEmpty
          ? storedFolder
          : courseId.isEmpty
          ? '未分类'
          : '课程 $courseId';
      final groupId = courseId.isNotEmpty
          ? courseId
          : storedFolder.isNotEmpty
          ? 'folder:$storedFolder'
          : 'uncategorized';
      groupNames[groupId] = courseName;
      grouped.putIfAbsent(groupId, () => []).add({
        ...file,
        'courseName': courseName,
      });
    }
    final groups = grouped.entries.toList()
      ..sort(
        (a, b) => (groupNames[a.key] ?? '').compareTo(groupNames[b.key] ?? ''),
      );
    return [
      Paper(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.folder_outlined, size: 18, color: ink),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '保存位置：${text(d, 'downloadDir')}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: ink),
              ),
            ),
            TextButton(
              onPressed: () => context.go('/settings'),
              child: const Text('更改'),
            ),
          ],
        ),
      ),
      if (files.isEmpty)
        Paper(
          child: PageEmpty(
            icon: 'folder',
            title: '还没有下载过文件',
            description: '前往「课程」页下载课件后会出现在这里。',
          ),
        )
      else
        for (final group in groups) ...[
          ChapterHead(
            title: groupNames[group.key] ?? '未分类',
            icon: 'book-open',
            trailing: Text(
              '${group.value.length} 个文件',
              style: const TextStyle(fontSize: 12, color: ink),
            ),
          ),
          for (final file in group.value)
            DownloadCard(services: s, record: file, onChanged: refresh),
        ],
    ];
  }
}
