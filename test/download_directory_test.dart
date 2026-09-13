import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zju_campus_agent/application/files.dart';
import 'package:zju_campus_agent/application/services.dart';
import 'package:zju_campus_agent/data/database.dart';

void main() {
  test('downloadDirectory 使用设置里选定的目录', () async {
    final db = AgentDatabase.memory();
    addTearDown(() => db.close());
    final support = Directory.systemTemp.createTempSync('dl_support_');
    addTearDown(() => support.deleteSync(recursive: true));
    final chosen = Directory.systemTemp.createTempSync('dl_chosen_');
    addTearDown(() => chosen.deleteSync(recursive: true));

    await db.put('settings', 'app', {'downloadDir': chosen.path});
    final resolved = await downloadDirectory(db, support);

    expect(resolved.path, chosen.path);
  });

  test('downloadDirectory 忽略空白配置并回落到默认目录', () async {
    final db = AgentDatabase.memory();
    addTearDown(() => db.close());
    final support = Directory.systemTemp.createTempSync('dl_support_');
    addTearDown(() => support.deleteSync(recursive: true));
    final chosen = Directory.systemTemp.createTempSync('dl_chosen_');
    addTearDown(() => chosen.deleteSync(recursive: true));

    await db.put('settings', 'app', {'downloadDir': '   '});
    final resolved = await downloadDirectory(db, support);

    expect(resolved.path.trim(), isNotEmpty);
    expect(resolved.path, isNot(chosen.path));
  });

  test('localFileExists 跟随传入的根目录 —— 换目录后旧记录即判定为已移除', () async {
    final first = Directory.systemTemp.createTempSync('dl_first_');
    addTearDown(() => first.deleteSync(recursive: true));
    final second = Directory.systemTemp.createTempSync('dl_second_');
    addTearDown(() => second.deleteSync(recursive: true));

    File('${first.path}/course/a.pdf')
      ..createSync(recursive: true)
      ..writeAsStringSync('x');

    expect(await localFileExists(first.path, 'course/a.pdf'), isTrue);
    // 同一条相对路径在另一个根目录下不存在：下载页据此显示「已被移除」。
    expect(await localFileExists(second.path, 'course/a.pdf'), isFalse);
    expect(await localFileExists(first.path, ''), isFalse);
    // 历史脏数据里的越界路径按不存在处理，不向上抛异常。
    expect(await localFileExists(first.path, '../escape'), isFalse);
  });
}
