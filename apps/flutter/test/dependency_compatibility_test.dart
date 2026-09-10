import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zju_campus_agent/platform/save_file.dart';
import 'package:zju_campus_agent/ui/theme.dart';

class _SavingPicker extends FilePickerPlatform {
  Uri? result;
  int saves = 0;
  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    expect(fileName, '课表.png');
    expect(bytes, [1, 2, 3]);
    saves++;
    return result;
  }
}

void main() {
  test(
    'save handles a document-provider URI and cancellation without a second write',
    () async {
      final old = FilePickerPlatform.instance, picker = _SavingPicker();
      FilePickerPlatform.instance = picker;
      addTearDown(() => FilePickerPlatform.instance = old);
      picker.result = Uri.parse('content://documents/test.png');
      await saveBytes('课表.png', Uint8List.fromList([1, 2, 3]));
      picker.result = null;
      await saveBytes('课表.png', Uint8List.fromList([1, 2, 3]));
      expect(picker.saves, 2);
    },
  );

  testWidgets('Markdown links navigate under the existing Material theme', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: MarkdownBody(
              data:
                  '## 校园助手\n\n| 课程 | 地点 |\n| --- | --- |\n| 数学 | 紫金港 |\n\n[查看课程](/courses)',
              onTapLink: (_, href, _) {
                if (href != null) context.go(href);
              },
            ),
          ),
        ),
        GoRoute(
          path: '/courses',
          builder: (_, _) => const Scaffold(body: Text('课程页面')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(theme: paperTheme(), routerConfig: router),
    );
    await tester.pumpAndSettle();
    expect(find.text('紫金港', findRichText: true), findsOneWidget);
    await tester.tap(find.text('查看课程', findRichText: true));
    await tester.pumpAndSettle();
    expect(find.text('课程页面'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
