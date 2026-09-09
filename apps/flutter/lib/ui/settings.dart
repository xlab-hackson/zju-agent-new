import 'dart:convert';

import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../application/services.dart';

import '../application/llm.dart';
import '../domain/models.dart';
import '../platform/save_file.dart';
import 'theme.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.services, this.setup = false});
  final AppServices services;
  final bool setup;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final username = TextEditingController(),
      password = TextEditingController(),
      nickname = TextEditingController(),
      persona = TextEditingController();
  final base = TextEditingController(text: 'https://api.openai.com'),
      key = TextEditingController(),
      model = TextEditingController(text: 'gpt-4.1-mini');
  String protocol = 'openai', message = '';
  bool busy = false, loaded = false;
  Json app = {};
  List<Json> providers = [];
  int selected = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final settings = await widget.services.db.get('settings', 'app') ?? {},
        campus = await widget.services.secrets.read('campus'),
        saved = await widget.services.secrets.read('providers');
    if (!mounted) return;
    setState(() {
      app = settings;
      nickname.text = text(app, 'nickname');
      persona.text = text(app, 'personaPrompt');
      username.text = text(campus ?? {}, 'username');
      providers = rows(saved?['items'] ?? []);
      if (providers.isNotEmpty) selectProvider(0);
      loaded = true;
    });
  }

  void selectProvider(int index) {
    selected = index;
    final p = providers[index];
    base.text = text(p, 'baseUrl');
    model.text = text(p, 'model');
    protocol = text(p, 'protocol', 'openai');
    key.clear();
  }

  @override
  void dispose() {
    for (final c in [username, password, nickname, persona, base, key, model]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> perform(Future<void> Function() action) async {
    setState(() {
      busy = true;
      message = '';
    });
    try {
      await action();
      if (mounted) setState(() => message = '已完成。');
    } catch (e) {
      if (mounted) {
        setState(() => message = e is AppError ? e.message : '操作失败，请检查文件或配置。');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget field(
    String label,
    TextEditingController c, {
    bool secret = false,
    int lines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextField(
      controller: c,
      obscureText: secret,
      maxLines: lines,
      decoration: InputDecoration(labelText: label),
    ),
  );
  @override
  Widget build(BuildContext context) {
    if (!loaded) return const Center(child: CircularProgressIndicator());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.setup ? '初次相逢 · 配置向导' : '设置',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 8),
        const Text('数据保存在设备本地。校园服务与模型由客户端直接连接。'),
        const SizedBox(height: 24),
        if (busy) const LinearProgressIndicator(),
        if (message.isNotEmpty)
          Padding(padding: const EdgeInsets.all(12), child: Text(message)),
        Paper(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('壹 · 统一身份认证', style: TextStyle(fontSize: 20)),
              const SizedBox(height: 18),
              field('浙大学号', username),
              field('密码（留空保留已有密码）', password, secret: true),
              Wrap(
                spacing: 10,
                children: [
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () => perform(() async {
                            final old = await widget.services.secrets.read(
                              'campus',
                            );
                            final pass = password.text.isEmpty
                                ? text(old ?? {}, 'password')
                                : password.text;
                            if (username.text.trim().isEmpty || pass.isEmpty) {
                              throw const AppError(
                                'INVALID_INPUT',
                                '请输入学号与密码。',
                              );
                            }
                            await widget.services.logout();
                            await widget.services.secrets.write('campus', {
                              'username': username.text.trim(),
                              'password': pass,
                            });
                            password.clear();
                            await widget.services.campus.session.ensure('cas');
                          }),
                    child: const Text('保存并验证'),
                  ),
                  OutlinedButton(
                    onPressed: busy
                        ? null
                        : () => perform(() async {
                            await widget.services.logout();
                            password.clear();
                          }),
                    child: const Text('退出校园账号'),
                  ),
                ],
              ),
            ],
          ),
        ),
        Paper(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('贰 · 模型来源', style: TextStyle(fontSize: 20)),
              const SizedBox(height: 18),
              if (providers.isNotEmpty)
                DropdownButton<int>(
                  value: selected,
                  items: [
                    for (var i = 0; i < providers.length; i++)
                      DropdownMenuItem(
                        value: i,
                        child: Text(text(providers[i], 'name', '模型 ${i + 1}')),
                      ),
                  ],
                  onChanged: busy
                      ? null
                      : (v) => setState(() => selectProvider(v!)),
                ),
              DropdownButton<String>(
                value: protocol,
                items: const [
                  DropdownMenuItem(value: 'openai', child: Text('OpenAI 兼容协议')),
                  DropdownMenuItem(
                    value: 'anthropic',
                    child: Text('Anthropic Messages'),
                  ),
                ],
                onChanged: (v) => setState(() => protocol = v!),
              ),
              field('API 地址', base),
              field('模型名称', model),
              field('API Key（留空保留）', key, secret: true),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () => perform(() async {
                            modelEndpoint(base.text.trim(), protocol);
                            final old = providers.isEmpty
                                ? <String, dynamic>{}
                                : providers[selected];
                            final apiKey = key.text.trim().isEmpty
                                ? text(old, 'apiKey')
                                : key.text.trim();
                            if (apiKey.isEmpty || model.text.trim().isEmpty) {
                              throw const AppError(
                                'INVALID_INPUT',
                                '请输入模型名称和 API Key。',
                              );
                            }
                            final value = {
                              'id':
                                  old['id'] ??
                                  DateTime.now().microsecondsSinceEpoch
                                      .toString(),
                              'name': model.text.trim(),
                              'baseUrl': base.text.trim(),
                              'model': model.text.trim(),
                              'apiKey': apiKey,
                              'protocol': protocol,
                              'enabled': old['enabled'] ?? true,
                            };
                            if (providers.isEmpty) {
                              providers.add(value);
                            } else {
                              providers[selected] = value;
                            }
                            await widget.services.secrets.write('providers', {
                              'items': providers,
                            });
                            key.clear();
                          }),
                    child: const Text('保存来源'),
                  ),
                  OutlinedButton(
                    onPressed: busy
                        ? null
                        : () => setState(() {
                            providers.add({
                              'name': '新来源',
                              'protocol': 'openai',
                              'baseUrl': 'https://api.openai.com',
                              'model': '',
                              'enabled': true,
                            });
                            selectProvider(providers.length - 1);
                          }),
                    child: const Text('新增来源'),
                  ),
                  if (providers.isNotEmpty)
                    OutlinedButton(
                      onPressed: busy
                          ? null
                          : () => perform(() async {
                              final p = providers.removeAt(selected);
                              providers.insert(0, p);
                              selected = 0;
                              await widget.services.secrets.write('providers', {
                                'items': providers,
                              });
                            }),
                      child: const Text('设为首选'),
                    ),
                  if (providers.isNotEmpty)
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => perform(() async {
                              providers.removeAt(selected);
                              selected = 0;
                              await widget.services.secrets.write('providers', {
                                'items': providers,
                              });
                              if (providers.isNotEmpty) {
                                selectProvider(0);
                              } else {
                                key.clear();
                                model.clear();
                              }
                            }),
                      child: const Text('删除来源'),
                    ),
                ],
              ),
            ],
          ),
        ),
        Paper(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('叁 · 个性化', style: TextStyle(fontSize: 20)),
              const SizedBox(height: 18),
              field('昵称', nickname),
              field('默认提示词 / 年级、专业与偏好', persona, lines: 4),
              Wrap(
                spacing: 10,
                children: [
                  OutlinedButton(
                    onPressed: busy
                        ? null
                        : () => perform(() async {
                            final picked = await FilePicker.platform.pickFiles(
                              type: FileType.image,
                              withData: true,
                            );
                            if (picked == null) return;
                            final bytes = picked.files.single.bytes;
                            if (bytes == null) return;
                            final codec = await ui.instantiateImageCodec(
                              bytes,
                              targetWidth: 256,
                              targetHeight: 256,
                            );
                            final frame = await codec.getNextFrame();
                            final data = await frame.image.toByteData(
                              format: ui.ImageByteFormat.png,
                            );
                            frame.image.dispose();
                            codec.dispose();
                            app['avatarDataUrl'] =
                                'data:image/png;base64,${base64Encode(data!.buffer.asUint8List())}';
                            await widget.services.db.put(
                              'settings',
                              'app',
                              app,
                            );
                          }),
                    child: const Text('更换头像'),
                  ),
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () => perform(() async {
                            if (nickname.text.length > 24 ||
                                persona.text.length > 2000) {
                              throw const AppError(
                                'INVALID_INPUT',
                                '昵称最多24字，提示词最多2000字。',
                              );
                            }
                            app = {
                              ...app,
                              'nickname': nickname.text.trim(),
                              'personaPrompt': persona.text.trim(),
                            };
                            await widget.services.db.put(
                              'settings',
                              'app',
                              app,
                            );
                          }),
                    child: const Text('保存个性化'),
                  ),
                ],
              ),
            ],
          ),
        ),
        Paper(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('肆 · 本地数据', style: TextStyle(fontSize: 20)),
              const SizedBox(height: 12),
              const Text(
                '备份不含密码、API Key、Cookie 和待确认操作。可用于 Windows 与 Android 之间迁移数据。',
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () => perform(() async {
                            final bytes = await widget.services.backups
                                .export();
                            await saveBytes('zju-agent-backup.zip',Uint8List.fromList(bytes));
                          }),
                    child: const Text('导出备份（含文件）'),
                  ),
                  OutlinedButton(
                    onPressed: busy
                        ? null
                        : () => perform(() async {
                            final picked = await FilePicker.platform.pickFiles(
                              type: FileType.custom,
                              allowedExtensions: ['zip'],
                              withData: true,
                            );
                            if (picked != null) {
                              await widget.services.backups.restore(
                                picked.files.single.bytes!,
                              );
                              await load();
                            }
                          }),
                    child: const Text('导入备份'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
