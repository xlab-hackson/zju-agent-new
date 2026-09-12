import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:dio/dio.dart';

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

/// 相对 [root] 的 [relative] 是否指向一个真实存在的文件。
///
/// 下载记录只存相对路径，换过下载根目录后旧记录会落到 false，下载页据此
/// 显示「已被移除」。历史脏数据里的非法相对路径同样按 false 处理。
Future<bool> localFileExists(String root, String relative) async {
  if (relative.isEmpty) return false;
  try {
    return await File(confinedPath(root, relative)).exists();
  } on AppError {
    return false;
  }
}

class FileService {
  FileService(this.campus, this.root);
  final CampusService campus;

  /// 下载根目录。可由设置页切换，因此不是 final。
  Directory root;
  final _activeDownloadsByKey = <String, _ActiveDownload>{};
  final _activeDownloadsById = <String, _ActiveDownload>{};
  final _reservedPaths = <String>{};
  AgentDatabase get db => campus.db;

  /// 切换下载根目录。
  ///
  /// 下载记录存的是相对旧根目录的路径，不会随目录一起搬家；切换后它们会
  /// 因为文件不存在而在下载页显示为「已被移除」。这里只清掉同名占位缓存，
  /// 让新目录重新计算可用文件名。
  Future<void> moveRoot(Directory next) async {
    await next.create(recursive: true);
    root = next;
    _reservedPaths.clear();
  }

  Future<Json> download(Json input) {
    for (final key in ['fileId', 'fileName', 'courseId']) {
      if (text(input, key).isEmpty) {
        throw const AppError('TOOL_INPUT_INVALID', '缺少文件参数。');
      }
    }
    final key = _downloadKey(input);
    final existing = _activeDownloadsByKey[key];
    if (existing != null) return existing.future;

    final id = const Uuid().v4();
    final task = _ActiveDownload(key, id, CancelToken());
    final raw = _download(input, task);
    final managed = _track(task, raw);
    task.future = managed;
    _activeDownloadsByKey[key] = task;
    _activeDownloadsById[id] = task;
    return managed;
  }

  Future<Json> _download(Json input, _ActiveDownload task) async {
    final id = task.id, pdf = input['officePdf'] == true;
    final courseId = text(input, 'courseId');
    final courseName = await _courseName(input, courseId);
    final courseFolder = safeName(
      courseName.isEmpty ? '课程-$courseId' : courseName,
    );
    var url =
        '${CampusService.coursesBase}/api/uploads/${Uri.encodeComponent(text(input, 'fileId'))}/blob';
    if (pdf) {
      final meta = await campus.session.json(
        'courses',
        '${CampusService.coursesBase}/api/uploads/document/${Uri.encodeComponent(text(input, 'fileId'))}/url?preview=true',
        cancelToken: task.cancelToken,
      );
      url = text(meta, 'url');
    }
    final name = pdf
        ? '${p.basenameWithoutExtension(safeName(text(input, 'fileName')))}.pdf'
        : safeName(text(input, 'fileName'));
    final relative = await _reserveDownloadPath(courseFolder, name);
    final target = File(confinedPath(root.path, relative));
    final temp = File('${target.path}.$id.part');
    final record = <String, dynamic>{
      'id': id,
      'fileName': name,
      'relativePath': relative,
      'status': 'downloading',
      'courseId': courseId,
      'courseName': courseName,
      'courseFolder': courseFolder,
      'fileId': input['fileId'],
      'officePdf': pdf,
    };
    try {
      await db.put('downloads', id, record);
      final transfer = await campus.session.downloadToFile(
        'courses',
        url,
        temp,
        cancelToken: task.cancelToken,
      );
      await temp.rename(target.path);
      record.addAll({
        'status': 'completed',
        'size': transfer.size,
        'mimeType': transfer.mimeType,
      });
      await db.put('downloads', id, record);
      return record;
    } catch (_) {
      try {
        if (await temp.exists()) await temp.delete();
      } catch (_) {
        // A failed cleanup must not hide the original download error.
      }
      record['status'] = 'failed';
      await db.put('downloads', id, record);
      rethrow;
    } finally {
      _reservedPaths.remove(relative);
    }
  }

  Future<Json> _track(_ActiveDownload task, Future<Json> future) async {
    try {
      return await future;
    } finally {
      if (identical(_activeDownloadsByKey[task.key], task)) {
        _activeDownloadsByKey.remove(task.key);
      }
      if (identical(_activeDownloadsById[task.id], task)) {
        _activeDownloadsById.remove(task.id);
      }
    }
  }

  String _downloadKey(Json input) => [
    text(input, 'courseId'),
    text(input, 'fileId'),
    input['officePdf'] == true ? 'pdf' : 'raw',
  ].join('\u0000');

  Future<String> _reserveDownloadPath(
    String courseFolder,
    String fileName,
  ) async {
    final extension = p.extension(fileName);
    final stem = p.basenameWithoutExtension(fileName);
    for (var index = 0; ; index++) {
      final candidate = index == 0 ? fileName : '$stem ($index)$extension';
      final relative = '$courseFolder/$candidate';
      if (_reservedPaths.contains(relative)) continue;
      if (!await File(confinedPath(root.path, relative)).exists()) {
        _reservedPaths.add(relative);
        return relative;
      }
    }
  }

  /// Material responses do not always carry the course name. Read only the
  /// local cache so UI, agent and batch downloads use the same course directory
  /// without adding another network/login wait to the download button.
  Future<String> _courseName(Json input, String courseId) async {
    final supplied = text(input, 'courseName').trim();
    if (supplied.isNotEmpty) return supplied;
    return campus.cachedCourseName(courseId);
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
    final id = text(record, 'id');
    final active = _activeDownloadsById[id];
    if (active != null) {
      active.cancelToken.cancel('用户删除了下载');
      try {
        await active.future;
      } catch (_) {
        // The canceled download has already recorded its failed state.
      }
    }
    if (purge) {
      try {
        await (await file(record)).delete();
      } on AppError catch (e) {
        if (e.code != 'FILE_NOT_FOUND') rethrow;
      }
    }
    await db.remove('downloads', id);
  }
}

class _ActiveDownload {
  _ActiveDownload(this.key, this.id, this.cancelToken);
  final String key, id;
  final CancelToken cancelToken;
  late Future<Json> future;
}

Future<String> availableDownloadPath(
  String root,
  String courseFolder,
  String fileName,
) async {
  final extension = p.extension(fileName);
  final stem = p.basenameWithoutExtension(fileName);
  for (var index = 0; ; index++) {
    final candidate = index == 0 ? fileName : '$stem ($index)$extension';
    final relative = '$courseFolder/$candidate';
    if (!await File(confinedPath(root, relative)).exists()) return relative;
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
