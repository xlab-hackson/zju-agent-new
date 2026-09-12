import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../../domain/formatters.dart';
import '../../domain/models.dart';
import '../assignments/assignment_detail_sheet.dart';
import '../downloads/preview_sheet.dart';
import '../theme.dart';
import 'campus_page.dart';

mixin FileActions<T extends CampusDataPage> on CampusPageState<T> {
  Future<void> assignmentDetail(Json assignment) =>
      showAssignmentDetail(context, assignment, onDownload: downloadFile);
  Future<void> downloadFile(Json f) async {
    await act(() async {
      await s.files.download({
        'courseId': text(f, 'courseId'),
        'fileId': text(f, 'id', text(f, 'fileId')),
        'fileName': text(f, 'name', text(f, 'fileName')),
        'courseName': text(f, 'courseName'),
        'officePdf': false,
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('文件已保存，可在下载页打开。')));
      }
    });
  }

  Future<void> previewFile(Json f) async {
    await act(() async {
      final name = text(f, 'name', text(f, 'fileName'));
      final record = await s.files.download({
        'courseId': text(f, 'courseId'),
        'fileId': text(f, 'id', text(f, 'fileId')),
        'fileName': name,
        'courseName': text(f, 'courseName'),
        'officePdf': isOfficeDocument(name),
      });
      final file = await s.files.file(record);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: paperCard,
        builder: (ctx) => PreviewSheet(
          file: file,
          name: text(record, 'fileName', name),
          kind: fileKind(text(record, 'fileName', name)),
          onOpen: () => act(() => openLocalFile(file)),
        ),
      );
    });
  }

  Future<void> openLocalFile(File file) async {
    final result = await OpenFilex.open(file.path);
    if (result.type != ResultType.done) {
      throw AppError('FILE_OPEN_FAILED', result.message);
    }
  }
}
