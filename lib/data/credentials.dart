import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../domain/models.dart';

abstract interface class SecretStore {
  Future<Json?> read(String key);
  Future<void> write(String key, Json value);
  Future<void> delete(String key);
}

class SecureSecrets implements SecretStore {
  final FlutterSecureStorage storage = const FlutterSecureStorage();
  @override
  Future<Json?> read(String key) async {
    final raw = await storage.read(key: 'zju_agent_$key');
    return raw == null ? null : object(jsonDecode(raw));
  }

  @override
  Future<void> write(String key, Json value) =>
      storage.write(key: 'zju_agent_$key', value: jsonEncode(value));
  @override
  Future<void> delete(String key) => storage.delete(key: 'zju_agent_$key');
}
