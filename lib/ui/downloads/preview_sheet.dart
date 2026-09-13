import 'dart:io';

import 'package:flutter/material.dart';

import '../theme.dart';

class PreviewSheet extends StatelessWidget {
  const PreviewSheet({
    super.key,
    required this.file,
    required this.name,
    required this.kind,
    required this.onOpen,
  });
  final File file;
  final String name, kind;
  final Future<void> Function() onOpen;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * .86,
    child: Column(
      children: [
        ListTile(
          leading: const Icon(Icons.article_outlined, color: gold),
          title: const Text(
            '预览',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(name),
          trailing: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _body(context)),
      ],
    ),
  );
  Widget _body(BuildContext context) {
    if (kind == 'image') {
      return Center(
        child: InteractiveViewer(child: Image.file(file, fit: BoxFit.contain)),
      );
    }
    if (kind == 'text') {
      return FutureBuilder<String>(
        future: file.readAsString(),
        builder: (context, snapshot) => SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: SelectableText(
            snapshot.data ?? '加载中…',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.description_outlined, size: 54, color: gold),
          const SizedBox(height: 12),
          Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('此类型文件无法在应用内预览，请使用本地软件打开。'),
          const SizedBox(height: 16),
          FilledButton(onPressed: () => onOpen(), child: const Text('用本地软件打开')),
        ],
      ),
    );
  }
}
