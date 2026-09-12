import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:html/parser.dart' as html;

import '../../domain/formatters.dart';
import '../../domain/models.dart';
import '../theme.dart';

Future<void> showAssignmentDetail(
  BuildContext context,
  Json a, {
  required Future<void> Function(Json) onDownload,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: paperCard,
  builder: (ctx) => SizedBox(
    height: MediaQuery.sizeOf(ctx).height * .8,
    child: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          text(a, 'title'),
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Text(
          '${text(a, 'courseName')} · ${formatDateTime(text(a, 'deadline'))}',
          style: const TextStyle(color: ink),
        ),
        const Divider(height: 28),
        MarkdownBody(
          data: html.parse(text(a, 'description')).body?.text ?? '暂无作业说明',
          selectable: true,
        ),
        const SizedBox(height: 12),
        for (final f in rows(a['attachments'] ?? []))
          ListTile(
            title: Text(text(f, 'name')),
            leading: const Icon(Icons.attach_file),
            trailing: const Icon(Icons.download),
            onTap: () => onDownload({
              ...f,
              'courseId': a['courseId'],
              'courseName': a['courseName'],
            }),
          ),
      ],
    ),
  ),
);
