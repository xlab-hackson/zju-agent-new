import 'dart:convert';

import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../application/services.dart';

import '../application/llm.dart';
import '../domain/models.dart';
import '../platform/save_file.dart';
import '../platform/operation_error.dart';
import 'avatar.dart';
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
      persona = TextEditingController(),
      providerName = TextEditingController();
  final base = TextEditingController(text: 'https://api.openai.com'),
      key = TextEditingController(),
      model = TextEditingController(text: 'gpt-4.1-mini');
  String protocol = 'openai', message = '';
  bool busy = false, loaded = false;
  bool campusCredentialSaved = false;
  Json app = {};
  List<Json> providers = [];
  List<String> availableModels = [];
  int selected = 0;
  String operationStage = '操作';
  final modelClient = ModelClient();
  bool? modelAvailable;
  String availabilityMessage = '', modelListMessage = '';
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final settings = await widget.services.db.get('settings', 'app') ?? {},
          campus = await widget.services.secrets.read('campus'),
          saved = await widget.services.secrets.read('providers');
      if (!mounted) return;
      setState(() {
        app = settings;
        nickname.text = text(app, 'nickname');
        persona.text = text(app, 'personaPrompt');
        username.text = text(campus ?? {}, 'username');
        campusCredentialSaved = campus != null;
        providers = rows(saved?['items'] ?? []);
        if (providers.isNotEmpty) selectProvider(0);
        loaded = true;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          loaded = true;
          message = operationError(e, '读取设置');
        });
      }
    }
  }

  void selectProvider(int index) {
    selected = index;
    final p = providers[index];
    providerName.text = providerLabel(p, index);
    base.text = text(p, 'baseUrl');
    model.text = text(p, 'model');
    protocol = text(p, 'protocol', 'openai');
    key.clear();
    availableModels = [];
    modelAvailable = null;
    availabilityMessage = '';
    modelListMessage = '';
  }

  String providerLabel(Json provider, int index) {
    final name = text(provider, 'name').trim(),
        modelName = text(provider, 'model').trim();
    if (name.isEmpty || name == modelName) return '模型 ${index + 1}';
    return name;
  }

  @override
  void dispose() {
    for (final c in [
      username,
      password,
      nickname,
      persona,
      providerName,
      base,
      key,
      model,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> saveCampus() async {
    operationStage = '读取已保存的校园凭据';
    final old = await widget.services.secrets.read('campus');
    final pass = password.text.isEmpty
        ? text(old ?? {}, 'password')
        : password.text;
    if (username.text.trim().isEmpty || pass.isEmpty) {
      throw const AppError('INVALID_INPUT', '请输入学号与密码。');
    }
    operationStage = '清理旧登录会话与缓存';
    await widget.services.logout();
    operationStage = '安全保存校园凭据';
    await widget.services.secrets.write('campus', {
      'username': username.text.trim(),
      'password': pass,
    });
    campusCredentialSaved = true;
    operationStage = '连接统一身份认证';
    await widget.services.campus.session.ensure('cas');
    username.clear();
    password.clear();
  }

  Future<void> logoutCampus() async {
    await widget.services.logout();
    campusCredentialSaved = false;
    username.clear();
    password.clear();
  }

  Future<void> changeAvatar() async {
    final picked = await FilePicker.pickFile(type: FileType.image);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: 256,
      targetHeight: 256,
    );
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    codec.dispose();
    if (data == null) {
      throw const AppError('INVALID_INPUT', '无法读取所选图片。');
    }
    final avatarDataUrl =
        'data:image/png;base64,${base64Encode(data.buffer.asUint8List())}';
    app = {...app, 'avatarDataUrl': avatarDataUrl};
    await widget.services.db.put('settings', 'app', app);
    if (mounted) setState(() {});
  }

  Json providerDraft() {
    final old = providers.isEmpty ? <String, dynamic>{} : providers[selected];
    return {
      'baseUrl': base.text.trim(),
      'model': model.text.trim(),
      'apiKey': key.text.trim().isEmpty ? text(old, 'apiKey') : key.text.trim(),
      'protocol': protocol,
    };
  }

  void clearModelChecks() {
    availableModels = [];
    modelAvailable = null;
    availabilityMessage = '';
    modelListMessage = '';
  }

  Future<void> loadModels() async {
    operationStage = '读取 API 地址的可用模型';
    if (mounted) {
      setState(() {
        modelListMessage = '正在读取 API 地址的模型列表…';
        modelAvailable = null;
        availabilityMessage = '';
      });
    }
    try {
      final found = await modelClient.listModels(providerDraft());
      if (!mounted) return;
      setState(() {
        availableModels = found;
        modelListMessage = '已从 API 地址读取 ${found.length} 个可用模型。';
        if (model.text.trim().isEmpty) model.text = found.first;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          availableModels = [];
          modelListMessage = operationError(e, '读取可用模型');
        });
      }
      rethrow;
    }
  }

  Future<void> checkProvider() async {
    if (mounted) {
      setState(() {
        modelAvailable = null;
        availabilityMessage = '正在检测 API 地址、密钥和模型…';
      });
    }
    try {
      await modelClient.checkAvailability(providerDraft());
      if (mounted) {
        setState(() {
          modelAvailable = true;
          availabilityMessage = '模型可用，API 地址、密钥和模型均已通过检测。';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          modelAvailable = false;
          availabilityMessage = operationError(e, '检测可用性');
        });
      }
      rethrow;
    }
  }

  Future<void> saveProvider() async {
    modelEndpoint(base.text.trim(), protocol);
    final old = providers.isEmpty ? <String, dynamic>{} : providers[selected];
    final apiKey = key.text.trim().isEmpty
        ? text(old, 'apiKey')
        : key.text.trim();
    final label = providerName.text.trim();
    if (apiKey.isEmpty || model.text.trim().isEmpty) {
      throw const AppError('INVALID_INPUT', '请输入模型名称和 API Key。');
    }
    if (label.length > 32) {
      throw const AppError('INVALID_INPUT', '来源备注名最多32字。');
    }
    final value = {
      'id': old['id'] ?? DateTime.now().microsecondsSinceEpoch.toString(),
      'name': label.isEmpty ? '模型 ${selected + 1}' : label,
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
    await widget.services.secrets.write('providers', {'items': providers});
    key.clear();
    if (mounted) setState(() => providerName.text = text(value, 'name'));
  }

  Future<void> perform(Future<void> Function() action) async {
    setState(() {
      busy = true;
      message = '';
      operationStage = '操作';
    });
    try {
      await action();
      if (mounted) setState(() => message = '已完成。');
    } catch (e) {
      if (mounted) {
        setState(() => message = operationError(e, operationStage));
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
    ValueChanged<String>? onChanged,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextField(
      controller: c,
      obscureText: secret,
      maxLines: lines,
      onChanged: onChanged,
      decoration: InputDecoration(labelText: label),
    ),
  );

  Widget modelStatus({required String message, bool? ok}) {
    final color = ok == true
        ? const Color(0xff2e7d32)
        : ok == false
        ? seal
        : blue;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .07),
          border: Border.all(color: color.withValues(alpha: .35)),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              ok == true
                  ? Icons.check_circle_outline
                  : ok == false
                  ? Icons.error_outline
                  : Icons.info_outline,
              size: 18,
              color: color,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(fontSize: 12, color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) return const Center(child: CircularProgressIndicator());
    final campusConnected =
        widget.services.campus.session.authStatus == 'connected';
    final hasCampusCredential = campusCredentialSaved;
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
              if (campusConnected)
                Row(
                  children: [
                    const Expanded(
                      child: Row(
                        children: [
                          Icon(Icons.check_circle, color: Color(0xff2e7d32)),
                          SizedBox(width: 8),
                          Text(
                            '已连接统一身份认证',
                            style: TextStyle(
                              color: Color(0xff2e7d32),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton(
                      onPressed: busy ? null : () => perform(logoutCampus),
                      child: const Text('退出登录'),
                    ),
                  ],
                )
              else ...[
                field('浙大学号', username),
                field('密码（留空保留已有密码）', password, secret: true),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      onPressed: busy ? null : () => perform(saveCampus),
                      child: Text(hasCampusCredential ? '重新验证' : '保存并验证'),
                    ),
                    if (hasCampusCredential)
                      OutlinedButton(
                        onPressed: busy ? null : () => perform(logoutCampus),
                        child: const Text('退出登录'),
                      ),
                  ],
                ),
              ],
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
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: DropdownButtonFormField<int>(
                    initialValue: selected,
                    decoration: const InputDecoration(labelText: '当前来源'),
                    isExpanded: true,
                    items: [
                      for (var i = 0; i < providers.length; i++)
                        DropdownMenuItem(
                          value: i,
                          child: Text(
                            providerLabel(providers[i], i),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: busy
                        ? null
                        : (v) => setState(() => selectProvider(v!)),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: DropdownButtonFormField<String>(
                  initialValue: protocol,
                  decoration: const InputDecoration(labelText: '协议'),
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(
                      value: 'openai',
                      child: Text('OpenAI 兼容协议'),
                    ),
                    DropdownMenuItem(
                      value: 'anthropic',
                      child: Text('Anthropic Messages'),
                    ),
                  ],
                  onChanged: busy
                      ? null
                      : (v) => setState(() {
                          protocol = v!;
                          clearModelChecks();
                        }),
                ),
              ),
              field('来源备注名', providerName),
              field(
                'API 地址',
                base,
                onChanged: (_) => setState(clearModelChecks),
              ),
              field(
                '模型名称',
                model,
                onChanged: (_) => setState(() {
                  modelAvailable = null;
                  availabilityMessage = '';
                }),
              ),
              if (availableModels.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: DropdownButtonFormField<String>(
                    initialValue: availableModels.contains(model.text)
                        ? model.text
                        : null,
                    decoration: const InputDecoration(
                      labelText: '从 API 地址选择模型',
                    ),
                    isExpanded: true,
                    items: [
                      for (final item in availableModels)
                        DropdownMenuItem(
                          value: item,
                          child: Text(
                            item,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: busy
                        ? null
                        : (v) {
                            if (v != null) setState(() => model.text = v);
                          },
                  ),
                ),
              field('API Key（留空保留）', key, secret: true),
              if (modelListMessage.isNotEmpty)
                modelStatus(message: modelListMessage),
              if (availabilityMessage.isNotEmpty)
                modelStatus(message: availabilityMessage, ok: modelAvailable),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  FilledButton(
                    onPressed: busy ? null : () => perform(saveProvider),
                    child: const Text('保存来源'),
                  ),
                  OutlinedButton(
                    onPressed: busy ? null : () => perform(loadModels),
                    child: const Text('读取可用模型'),
                  ),
                  OutlinedButton(
                    onPressed: busy ? null : () => perform(checkProvider),
                    child: const Text('检测可用性'),
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
                                providerName.clear();
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
              Center(
                child: UserAvatar(
                  dataUrl: text(app, 'avatarDataUrl'),
                  radius: 44,
                  onTap: busy ? null : () => perform(changeAvatar),
                ),
              ),
              const SizedBox(height: 8),
              const Center(
                child: Text(
                  '点击头像更换',
                  style: TextStyle(fontSize: 11, color: gold),
                ),
              ),
              const SizedBox(height: 16),
              field('昵称', nickname),
              field('默认提示词 / 年级、专业与偏好', persona, lines: 4),
              Wrap(
                spacing: 10,
                children: [
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
                            await saveBytes(
                              'zju-agent-backup.zip',
                              Uint8List.fromList(bytes),
                            );
                          }),
                    child: const Text('导出备份（含文件）'),
                  ),
                  OutlinedButton(
                    onPressed: busy
                        ? null
                        : () => perform(() async {
                            final picked = await FilePicker.pickFile(
                              type: FileType.custom,
                              allowedExtensions: ['zip'],
                            );
                            if (picked != null) {
                              await widget.services.backups.restore(
                                await picked.readAsBytes(),
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
