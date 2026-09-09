import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';

import 'package:path/path.dart' as p;

import 'package:uuid/uuid.dart';
import '../domain/models.dart';
import '../data/database.dart';
import 'campus.dart';

String safeName(String name) {
  final clean = name
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
      .replaceAll(RegExp(r'[. ]+$'), '')
      .trim();
  if (clean.isEmpty ||
      RegExp(
        r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)',
        caseSensitive: false,
      ).hasMatch(clean)) {
    return 'file_$clean';
  }
  return clean.length > 160 ? clean.substring(0, 160) : clean;
}

String confinedPath(String root, String relative) {
  if (p.isAbsolute(relative) ||
      relative.contains('\\') ||
      relative.split('/').any((e) => e == '..' || e.isEmpty) ||
      relative.contains(':')) {
    throw const AppError('INVALID_INPUT', '文件路径非法。');
  }
  final result = p.normalize(p.join(root, relative));
  if (!p.isWithin(p.normalize(p.absolute(root)), p.absolute(result))) {
    throw const AppError('INVALID_INPUT', '文件路径超出目录。');
  }
  return result;
}

class FileService {
  FileService(this.campus, this.root);
  final CampusService campus;
  final Directory root;
  AgentDatabase get db => campus.db;
  Future<Json> download(Json input) async {
    for (final key in ['fileId', 'fileName', 'courseId']) {
      if (text(input, key).isEmpty) {
        throw const AppError('TOOL_INPUT_INVALID', '缺少文件参数。');
      }
    }
    final id = const Uuid().v4(), pdf = input['officePdf'] == true;
    var url =
        '${CampusService.coursesBase}/api/uploads/${Uri.encodeComponent(text(input, 'fileId'))}/blob';
    if (pdf) {
      final meta = await campus.session.json(
        'courses',
        '${CampusService.coursesBase}/api/uploads/document/${Uri.encodeComponent(text(input, 'fileId'))}/url?preview=true',
      );
      url = text(meta, 'url');
    }
    final name = pdf
        ? '${p.basenameWithoutExtension(safeName(text(input, 'fileName')))}.pdf'
        : safeName(text(input, 'fileName'));
    final relative = '$id/$name',
        target = File(confinedPath(root.path, relative));
    final record = <String, dynamic>{
      'id': id,
      'fileName': name,
      'relativePath': relative,
      'status': 'downloading',
      'courseId': input['courseId'],
      'fileId': input['fileId'],
    };
    await db.put('downloads', id, record);
    try {
      final response = await campus.session.request(
        'courses',
        url,
        bytes: true,
      );
      final bytes = List<int>.from(response.data as List);
      if (bytes.length > 512 * 1024 * 1024) {
        throw const AppError('FILE_DOWNLOAD_FAILED', '文件超过 512 MB，请使用学校页面下载。');
      }
      await target.parent.create(recursive: true);
      final temp = File('${target.path}.part');
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(target.path);
      record.addAll({
        'status': 'completed',
        'size': bytes.length,
        'mimeType': response.headers.value('content-type'),
      });
      await db.put('downloads', id, record);
      return record;
    } catch (_) {
      record['status'] = 'failed';
      await db.put('downloads', id, record);
      rethrow;
    }
  }

  Future<File> file(Json record) async {
    final candidate = File(
      confinedPath(root.path, text(record, 'relativePath')),
    );
    if (!await candidate.exists()) {
      throw const AppError('FILE_NOT_FOUND', '文件已被移除。');
    }
    final real = await candidate.resolveSymbolicLinks();
    if (!p.isWithin(await root.resolveSymbolicLinks(), real)) {
      throw const AppError('FILE_NOT_FOUND', '文件路径非法。');
    }
    return candidate;
  }

  Future<void> delete(Json record, {bool purge = false}) async {
    if (purge) {
      try {
        await (await file(record)).delete();
      } on AppError catch (e) {
        if (e.code != 'FILE_NOT_FOUND') rethrow;
      }
    }
    await db.remove('downloads', text(record, 'id'));
  }
}

const portableCollections = {
  'conversations',
  'messages',
  'settings',
  'downloads',
  'audit',
};
Json portableSettings(Json source) => {
  for (final key in [
    'nickname',
    'avatarDataUrl',
    'personaPrompt',
    'confirmSingleDownload',
    'courseReminderLeadMinutes',
  ])
    if (source.containsKey(key)) key: source[key],
};

class BackupService {
  BackupService(this.db, this.files);
  final AgentDatabase db;
  final FileService files;
  Future<List<int>> export({bool includeFiles = true}) async {
    final archive = Archive(), records = <Json>[];
    for (final row in await db.dump()) {
      final collection = text(row, 'collection');
      if (!portableCollections.contains(collection)) continue;
      var value = object(jsonDecode(text(row, 'value')));
      if (collection == 'settings') {
        if (row['id'] != 'app') continue;
        value = portableSettings(value);
      }
      records.add({'collection': collection, 'id': row['id'], 'value': value});
      if (collection == 'downloads' && includeFiles) {
        try {
          final f = await files.file(value), bytes = await f.readAsBytes();
          archive.addFile(
            ArchiveFile('files/${value['relativePath']}', bytes.length, bytes),
          );
        } on AppError {
          /* Keep missing download record. */
        }
      }
    }
    final manifest = utf8.encode(
      jsonEncode({'version': 1, 'records': records}),
    );
    archive.addFile(ArchiveFile('manifest.json', manifest.length, manifest));
    return ZipEncoder().encode(archive)!;
  }

  Future<void> restore(List<int> bytes) async {
    if (bytes.length > 512 * 1024 * 1024) {
      throw const AppError('INVALID_INPUT', '备份文件过大。');
    }
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    var total = 0;
    for (final f in archive) {
      total += f.size;
      if (total > 1024 * 1024 * 1024 || f.isSymbolicLink) {
        throw const AppError('INVALID_INPUT', '备份内容不安全或过大。');
      }
      confinedPath(files.root.path, f.name);
    }
    final manifest = archive.findFile('manifest.json');
    if (manifest == null) throw const AppError('INVALID_INPUT', '备份缺少清单。');
    final data = object(jsonDecode(utf8.decode(manifest.content as List<int>)));
    if (data['version'] != 1) {
      throw const AppError('INVALID_INPUT', '不支持的备份版本。');
    }
    final records = rows(data['records']);
    for (final r in records) {
      if (!portableCollections.contains(r['collection'])) {
        throw const AppError('INVALID_INPUT', '备份含不支持的数据类型。');
      }
      final value = object(r['value']);
      if (r['collection'] == 'downloads') {
        confinedPath(files.root.path, text(value, 'relativePath'));
      }
    }
    await db.transaction(() async {
      for (final r in records) {
        final collection = text(r, 'collection'), id = text(r, 'id');
        if (await db.get(collection, id) != null) continue;
        var value = object(r['value']);
        if (collection == 'settings') {
          if (id != 'app') continue;
          value = portableSettings(value);
        }
        if (collection == 'downloads') {
          final relative = text(value, 'relativePath'),
              asset = archive.findFile('files/$relative');
          final target = File(confinedPath(files.root.path, relative));
          if (asset != null && !await target.exists()) {
            await target.parent.create(recursive: true);
            await target.writeAsBytes(asset.content as List<int>, flush: true);
          }
          if (!await target.exists()) value = {...value, 'status': 'missing'};
        }
        await db.put(collection, id, value);
      }
    });
  }
}
