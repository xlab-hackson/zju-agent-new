import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../../application/services.dart';
import '../../domain/formatters.dart';
import '../../domain/models.dart';
import '../theme.dart';
import 'file_presentation.dart';
import 'preview_sheet.dart';

class DownloadCard extends StatefulWidget {
  const DownloadCard({
    super.key,
    required this.services,
    required this.record,
    required this.onChanged,
  });
  final AppServices services;
  final Json record;
  final VoidCallback onChanged;
  @override
  State<DownloadCard> createState() => _DownloadCardState();
}

class _DownloadCardState extends State<DownloadCard> {
  bool confirming = false;
  bool busy = false;
  AppServices get s => widget.services;
  Json get r => widget.record;
  Future<void> run(Future<void> Function() fn) async {
    setState(() => busy = true);
    try {
      await fn();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is AppError ? e.message : '操作失败，请重试。')),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = text(r, 'fileName'), kind = fileKind(name);
    final inProgress = text(r, 'status') == 'downloading';
    final canRedownload =
        !inProgress &&
        text(r, 'fileId').isNotEmpty &&
        text(r, 'courseId').isNotEmpty;
    final completed = text(r, 'status') == 'completed';
    final actions = Wrap(
      alignment: WrapAlignment.end,
      spacing: 4,
      runSpacing: 2,
      children: [
        if (canPreview(kind))
          TextButton(
            onPressed: busy || inProgress ? null : () => preview(),
            child: const Text('预览'),
          ),
        if (inProgress)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Text('下载中…', style: TextStyle(color: blue)),
          ),
        if (canRedownload)
          TextButton(
            onPressed: busy ? null : () => run(redownload),
            child: Text(completed ? '重新下载' : '重试下载'),
          ),
        OutlinedButton(
          onPressed: busy || inProgress ? null : () => run(openLocal),
          child: const Text('打开'),
        ),
        if (!confirming)
          TextButton(
            onPressed: busy ? null : () => setState(() => confirming = true),
            child: const Text('删除'),
          )
        else ...[
          FilledButton(
            onPressed: busy
                ? null
                : () => run(() async {
                    await s.files.delete(r, purge: true);
                    widget.onChanged();
                  }),
            style: FilledButton.styleFrom(backgroundColor: seal),
            child: const Text('删文件'),
          ),
          TextButton(
            onPressed: busy
                ? null
                : () => run(() async {
                    await s.files.delete(r);
                    widget.onChanged();
                  }),
            child: const Text('仅删记录'),
          ),
          IconButton(
            onPressed: () => setState(() => confirming = false),
            icon: const Icon(Icons.close, size: 17),
          ),
        ],
      ],
    );
    return Paper(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final details = Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${formatBytes(integer(r['size']))} · ${formatDateTime(text(r, 'createdAt'))}',
                  style: const TextStyle(fontSize: 11, color: ink),
                ),
              ],
            ),
          );
          final header = Row(
            children: [
              Icon(fileIcon(kind), color: fileColor(kind), size: 24),
              const SizedBox(width: 14),
              details,
            ],
          );
          if (constraints.maxWidth < 620) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerRight, child: actions),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: header),
              const SizedBox(width: 12),
              Flexible(child: actions),
            ],
          );
        },
      ),
    );
  }

  Future<void> openLocal() async {
    final file = await s.files.file(r);
    final result = await OpenFilex.open(file.path);
    if (result.type != ResultType.done) {
      throw AppError('FILE_OPEN_FAILED', result.message);
    }
  }

  Future<void> redownload() async {
    await s.files.download({
      'courseId': text(r, 'courseId'),
      'courseName': text(r, 'courseName'),
      'fileId': text(r, 'fileId'),
      'fileName': text(r, 'fileName'),
      'officePdf': r['officePdf'] == true,
    });
    if (text(r, 'status') != 'completed') await s.files.delete(r);
    widget.onChanged();
  }

  Future<void> preview() async {
    final file = await s.files.file(r);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: paperCard,
      builder: (ctx) => PreviewSheet(
        file: file,
        name: text(r, 'fileName'),
        kind: fileKind(text(r, 'fileName')),
        onOpen: openLocal,
      ),
    );
  }
}
