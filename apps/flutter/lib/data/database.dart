import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import '../domain/models.dart';

class AgentDatabase extends GeneratedDatabase {
  AgentDatabase(File file) : super(NativeDatabase.createInBackground(file));
  AgentDatabase.memory() : super(NativeDatabase.memory());
  @override
  int get schemaVersion => 1;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await customStatement(
        'CREATE TABLE records (collection TEXT NOT NULL, id TEXT NOT NULL, value TEXT NOT NULL, updated_at TEXT NOT NULL, PRIMARY KEY(collection,id))',
      );
    },
  );
  Future<Json?> get(String collection, String id) async {
    final row = await customSelect(
      'SELECT value FROM records WHERE collection = ? AND id = ?',
      variables: [Variable(collection), Variable(id)],
    ).getSingleOrNull();
    return row == null ? null : object(jsonDecode(row.read<String>('value')));
  }

  Future<List<Json>> list(String collection) async => (await customSelect(
    'SELECT value FROM records WHERE collection = ? ORDER BY updated_at DESC',
    variables: [Variable(collection)],
  ).get()).map((r) => object(jsonDecode(r.read<String>('value')))).toList();
  Future<void> put(String collection, String id, Json value) => customStatement(
    'INSERT INTO records(collection,id,value,updated_at) VALUES(?,?,?,?) ON CONFLICT(collection,id) DO UPDATE SET value=excluded.value, updated_at=excluded.updated_at',
    [
      collection,
      id,
      jsonEncode(value),
      DateTime.now().toUtc().toIso8601String(),
    ],
  );
  Future<void> remove(String collection, [String? id]) => customStatement(
    'DELETE FROM records WHERE collection = ?${id == null ? '' : ' AND id = ?'}',
    [collection, ?id],
  );
  Future<List<Json>> dump() async => (await customSelect(
    'SELECT * FROM records',
  ).get()).map((e) => e.data).toList();
}
