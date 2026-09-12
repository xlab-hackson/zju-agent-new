import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:excel/excel.dart';
import '../platform/save_file.dart';
import 'package:flutter/material.dart' hide Border;
import 'package:flutter/rendering.dart';
import '../domain/models.dart';
import '../domain/schedule.dart';

const courseColors = [
  0xffdce8f3,
  0xffe9e4cf,
  0xffe4ebdb,
  0xfff0ded9,
  0xffe6e0ec,
  0xffd8e9e6,
];
Future<void> exportPng(GlobalKey key, String semester) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 2);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await saveBytes('课表-$semester.png', data!.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}

List<int> timetableWorkbook(List<TimetableEntry> entries, String semester) {
  final excel = Excel.createExcel(), sheetName = '课程表';
  final sheet = excel[sheetName];
  excel.delete('Sheet1');
  excel.setDefaultSheet(sheetName);
  sheet.merge(
    CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
    CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: 0),
  );
  sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).value =
      TextCellValue('浙江大学课程表（$semester）');
  sheet.appendRow(
    [
      '节次',
      '周一',
      '周二',
      '周三',
      '周四',
      '周五',
      '周六',
      '周日',
    ].map(TextCellValue.new).toList(),
  );
  for (var section = 1; section <= 13; section++) {
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: section + 1))
        .value = TextCellValue(
      '$section\n${sessionTimes[section].join('-')}',
    );
  }
  final groups = <String, List<TimetableEntry>>{};
  for (final e in mergeTimetable(entries)) {
    groups
        .putIfAbsent('${e.weekday}:${e.startSection}:${e.endSection}', () => [])
        .add(e);
  }
  var color = 0;
  for (final group in groups.values) {
    final e = group.first,
        start = CellIndex.indexByColumnRow(
          columnIndex: e.weekday,
          rowIndex: e.startSection + 1,
        ),
        end = CellIndex.indexByColumnRow(
          columnIndex: e.weekday,
          rowIndex: e.endSection + 1,
        );
    if (e.endSection > e.startSection) sheet.merge(start, end);
    sheet.cell(start).value = TextCellValue(
      group
          .map(
            (e) =>
                '${e.courseName}\n${e.location} ${e.teacher}\n${e.subSemester} ${e.weeks.join(',')}',
          )
          .join('\n'),
    );
    sheet.cell(start).cellStyle = CellStyle(
      backgroundColorHex: ExcelColor.fromHexString(
        courseColors[color++ % courseColors.length].toRadixString(16),
      ),
      textWrapping: TextWrapping.WrapText,
      verticalAlign: VerticalAlign.Center,
    );
  }
  for (var c = 0; c < 8; c++) {
    sheet.setColumnWidth(c, c == 0 ? 18 : 26);
  }
  for (var r = 2; r < 15; r++) {
    sheet.setRowHeight(r, 42);
  }
  return excel.encode()!;
}

Future<void> exportXlsx(List<TimetableEntry> entries, String semester) async {
  await saveBytes(
    '课表-$semester.xlsx',
    Uint8List.fromList(timetableWorkbook(entries, semester)),
  );
}
