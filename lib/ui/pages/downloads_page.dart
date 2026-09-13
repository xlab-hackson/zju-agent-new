import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

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
      _buildDirectoryCard(d, wide: wide),
      const SizedBox(height: 16),
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

  Widget _buildDirectoryCard(Json d, {required bool wide}) {
    final downloadDir = text(d, 'downloadDir');
    final defaultDir = text(d, 'defaultDownloadDir');
    final isCustom = d['isCustomDownloadDir'] == true ||
        (defaultDir.isNotEmpty && downloadDir != defaultDir);

    return Paper(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 620;

          final infoColumn = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.folder_outlined, color: blue, size: 18),
                  const SizedBox(width: 8),
                  const Text(
                    '下载保存目录',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: ink,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: isCustom ? gold.withAlpha(25) : ink.withAlpha(16),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isCustom
                            ? gold.withAlpha(120)
                            : ink.withAlpha(40),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      isCustom ? '自定义' : '默认',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isCustom ? gold : ink.withAlpha(160),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              SelectableText(
                downloadDir,
                style: const TextStyle(
                  fontSize: 12,
                  color: ink,
                  fontFamily: 'monospace',
                ),
                maxLines: 2,
              ),
            ],
          );

          final actions = Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: () => _openDirectory(downloadDir),
                icon: const Icon(Icons.folder_open_outlined, size: 16),
                label: const Text('打开目录'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  minimumSize: const Size(0, 32),
                ),
              ),
              FilledButton.icon(
                onPressed: () => _showChangeDirectoryDialog(
                  currentDir: downloadDir,
                  defaultDir: defaultDir,
                ),
                icon: const Icon(Icons.drive_file_move_outlined, size: 16),
                label: const Text('更改目录'),
                style: FilledButton.styleFrom(
                  backgroundColor: blue,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  minimumSize: const Size(0, 32),
                ),
              ),
              if (isCustom)
                TextButton(
                  onPressed: _resetDirectory,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    minimumSize: const Size(0, 32),
                    foregroundColor: seal,
                  ),
                  child: const Text('恢复默认'),
                ),
            ],
          );

          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                infoColumn,
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerRight, child: actions),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: infoColumn),
              const SizedBox(width: 16),
              actions,
            ],
          );
        },
      ),
    );
  }

  Future<void> _showChangeDirectoryDialog({
    required String currentDir,
    required String defaultDir,
  }) async {
    final controller = TextEditingController(text: currentDir);
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: paperCard,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            title: const Row(
              children: [
                Icon(Icons.folder_outlined, color: blue, size: 22),
                SizedBox(width: 8),
                Text(
                  '配置下载目标目录',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '新下载的课件、资料将保存到此目录。各课程将以课程名作为子文件夹分类存放。',
                    style: TextStyle(fontSize: 13, color: ink),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controller,
                          decoration: InputDecoration(
                            labelText: '下载目录路径',
                            hintText: '请输入或选择保存目录绝对路径',
                            errorText: errorText,
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                          onChanged: (_) {
                            if (errorText != null) {
                              setDialogState(() => errorText = null);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () async {
                          try {
                            final picked = await FilePicker.getDirectoryPath(
                              dialogTitle: '选择下载保存目录',
                              initialDirectory:
                                  controller.text.trim().isNotEmpty
                                      ? controller.text.trim()
                                      : null,
                            );
                            if (picked != null && picked.trim().isNotEmpty) {
                              controller.text = picked.trim();
                              setDialogState(() => errorText = null);
                            }
                          } catch (e) {
                            setDialogState(() => errorText = '选择目录失败：$e');
                          }
                        },
                        icon: const Icon(Icons.folder_open, size: 16),
                        label: const Text('浏览...'),
                      ),
                    ],
                  ),
                  if (defaultDir.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text(
                          '默认目录：',
                          style: TextStyle(fontSize: 11, color: ink),
                        ),
                        Expanded(
                          child: Text(
                            defaultDir,
                            style: TextStyle(
                              fontSize: 11,
                              color: ink.withAlpha(160),
                              fontFamily: 'monospace',
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        InkWell(
                          onTap: () {
                            controller.text = defaultDir;
                            setDialogState(() => errorText = null);
                          },
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            child: Text(
                              '填入默认',
                              style: TextStyle(fontSize: 11, color: blue),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () async {
                  final target = controller.text.trim();
                  if (target.isEmpty) {
                    setDialogState(() => errorText = '目录路径不能为空');
                    return;
                  }
                  try {
                    await s.files.setDownloadDirectory(target);
                    if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('下载目录已更新为：$target')),
                      );
                      refresh();
                    }
                  } catch (e) {
                    setDialogState(() {
                      errorText = e is AppError ? e.message : '无法访问或创建该目录：$e';
                    });
                  }
                },
                style: FilledButton.styleFrom(backgroundColor: blue),
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openDirectory(String dirPath) async {
    try {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final result = await OpenFilex.open(dirPath);
      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开目录失败：${result.message}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开目录失败：$e')),
        );
      }
    }
  }

  Future<void> _resetDirectory() async {
    try {
      await s.files.setDownloadDirectory(null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已恢复为默认下载目录')),
        );
        refresh();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('恢复默认目录失败：$e')),
        );
      }
    }
  }
}

