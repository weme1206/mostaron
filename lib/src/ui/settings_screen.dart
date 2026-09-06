import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../state/app_state.dart';
import '../services/provider_presets.dart';
import 'worldbook_screen.dart';
import 'usage_help_screen.dart';
import 'theme.dart';
import '../utils/colors.dart';
import '../utils/file_utils.dart';
import 'widgets/color_picker.dart';
import 'avatar_crop_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: const [
          _Section('接口与 Key'),
          ProvidersSection(),
          Divider(),
          _Section('外观'),
          _ThemeSection(),
          Divider(),
          _Section('聊天气泡'),
          _BubbleSection(),
          Divider(),
          _Section('你的身份'),
          _PersonaSection(),
          _AvatarSection(),
          Divider(),
          _Section('对话与记忆'),
          _ChatSettingsSection(),
          Divider(),
          _Section('数据'),
          _DataSection(),
          Divider(),
          _HelpSection(),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  const _Section(this.title);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      );
}

// ---------------- Providers ----------------
class ProvidersSection extends StatefulWidget {
  const ProvidersSection({super.key});
  @override
  State<ProvidersSection> createState() => _ProvidersSectionState();
}

class _ProvidersSectionState extends State<ProvidersSection> {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (state.providers.isEmpty) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.key),
          title: const Text('尚未配置接口'),
          subtitle: const Text('添加一个 OpenAI 兼容接口（支持自定义 Base URL 和模型名）'),
          trailing: const Icon(Icons.add),
          onTap: () => _editProvider(context, null),
        ),
      );
    }
    return Column(
      children: [
        for (final p in state.providers)
          Card(
            child: ListTile(
              leading: Icon(p.isDefault ? Icons.star : Icons.dns, color: p.isDefault ? Colors.amber : null),
              title: Text(p.name),
              subtitle: Text('${p.baseUrl}\n${p.model}', maxLines: 2, overflow: TextOverflow.ellipsis),
              onTap: () => _manageModels(context, p),
              trailing: PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'edit') {
                    await _editProvider(context, p);
                  } else if (v == 'default') {
                    await context.read<AppState>().setDefaultProvider(p.id);
                  } else if (v == 'delete') {
                    await context.read<AppState>().deleteProvider(p.id);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'edit', child: Text('编辑接口')),
                  PopupMenuItem(value: 'default', child: Text(p.isDefault ? '已是默认' : '设为默认')),
                  const PopupMenuItem(value: 'delete', child: Text('删除')),
                ],
              ),
            ),
          ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.add),
            title: const Text('添加接口'),
            onTap: () => _editProvider(context, null),
          ),
        ),
      ],
    );
  }

  Future<void> _manageModels(BuildContext context, ProviderConfig p) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _ManageModelsSheet(provider: p),
    );
  }

  Future<void> _editProvider(BuildContext context, ProviderConfig? p) async {
    final name = TextEditingController(text: p?.name ?? '');
    final base = TextEditingController(text: p?.baseUrl ?? '');
    final key = TextEditingController(text: p?.apiKey ?? '');
    final model = TextEditingController(text: p?.model ?? '');
    List<String> fetchedModels = List.of(p?.models ?? []);
    final appState = context.read<AppState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setState) => AlertDialog(
          title: Text(p == null ? '添加接口' : '编辑接口'),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('快速选择预设：'),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: ProviderPresets.list
                        .map((pr) => ActionChip(
                              label: Text(pr.name, style: const TextStyle(fontSize: 12)),
                              onPressed: () => setState(() {
                                name.text = pr.name;
                                base.text = pr.baseUrl;
                                model.text = pr.model;
                              }),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 10),
                  TextField(controller: name, decoration: const InputDecoration(labelText: '名称')),
                  const SizedBox(height: 12),
                  TextField(controller: base, decoration: const InputDecoration(labelText: 'Base URL', hintText: 'https://api.openai.com/v1')),
                  const SizedBox(height: 12),
                  TextField(controller: key, obscureText: true, decoration: const InputDecoration(labelText: 'API Key')),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: model,
                          decoration: const InputDecoration(labelText: '模型名', hintText: 'gpt-4o / deepseek-chat'),
                        ),
                      ),
                      IconButton(
                        tooltip: '获取模型',
                        icon: const Icon(Icons.list),
                        onPressed: () async {
                          final b = base.text.trim().isEmpty ? 'https://api.openai.com/v1' : base.text.trim();
                          try {
                            final models = await ApiClient().getModels(
                                baseUrl: b, apiKey: key.text.trim());
                            if (models.isEmpty) {
                              ScaffoldMessenger.of(d).showSnackBar(const SnackBar(content: Text('未获取到模型')));
                              return;
                            }
                            final picked = await showModelPicker(d, models);
                            if (picked != null && picked.isNotEmpty) {
                              fetchedModels = picked;
                              if (model.text.trim().isEmpty) {
                                setState(() => model.text = picked.first);
                              }
                              // 编辑已有接口时，立即分组保存
                              if (p != null) {
                                await appState.updateProvider(p.copyWith(models: picked));
                              }
                            }
                          } catch (e) {
                            ScaffoldMessenger.of(d).showSnackBar(SnackBar(content: Text('获取失败: $e')));
                          }
                        },
                      ),
                    ],
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.wifi_tethering),
                    label: const Text('测试连接'),
                    onPressed: () async {
                      try {
                        await ApiClient().testConnection(
                            baseUrl: base.text.trim(), apiKey: key.text.trim());
                        ScaffoldMessenger.of(d).showSnackBar(const SnackBar(content: Text('连接成功')));
                      } catch (e) {
                        ScaffoldMessenger.of(d).showSnackBar(SnackBar(content: Text('连接失败: $e')));
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('取消')),
            TextButton(
              onPressed: () {
                if (base.text.trim().isEmpty) {
                  ScaffoldMessenger.of(d).showSnackBar(const SnackBar(content: Text('请填写 Base URL')));
                  return;
                }
                Navigator.pop(d, true);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      var b = base.text.trim();
      if (b.isNotEmpty && !b.startsWith('http')) b = 'https://$b';
      final cfg = ProviderConfig(
        id: p?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        name: name.text.trim().isEmpty ? b : name.text.trim(),
        baseUrl: b,
        apiKey: key.text.trim(),
        model: model.text.trim(),
        models: fetchedModels,
        isDefault: p?.isDefault ?? false,
      );
      if (p == null) {
        await context.read<AppState>().addProvider(cfg);
      } else {
        await context.read<AppState>().updateProvider(cfg);
      }
    }
  }
}

// ---------------- Theme ----------------
class _ThemeSection extends StatefulWidget {
  const _ThemeSection();
  @override
  State<_ThemeSection> createState() => _ThemeSectionState();
}

class _ThemeSectionState extends State<_ThemeSection> {
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>().settings;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('主题色', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                ...AppTheme.accents.keys
                    .map((k) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () =>
                                context.read<AppState>().updateSettings(s.copyWith(themeAccent: k)),
                            child: CircleAvatar(
                              radius: 18,
                              backgroundColor: AppTheme.accent(k),
                              child: s.themeAccent == k
                                  ? const Icon(Icons.check, color: Colors.white, size: 20)
                                  : null,
                            ),
                          ),
                        )),
              ],
            ),
            const SizedBox(height: 12),
            for (final e in const [
              ['system', '跟随系统'],
              ['light', '亮色'],
              ['dark', '暗色'],
            ])
              RadioListTile<String>(
                dense: true,
                title: Text(e[1]),
                value: e[0],
                groupValue: s.themeMode,
                onChanged: (v) => context.read<AppState>().updateSettings(s.copyWith(themeMode: v!)),
              ),
            SwitchListTile(
              dense: true,
              title: const Text('夜间自动切暗色'),
              value: s.nightAutoDark,
              onChanged: (v) => context.read<AppState>().updateSettings(s.copyWith(nightAutoDark: v)),
            ),
            if (s.nightAutoDark) ...[
              Row(
                children: [
                  const Text('夜晚开始'),
                  Expanded(
                    child: Slider(
                      value: s.nightStartHour.toDouble().clamp(17, 23),
                      min: 17, max: 23, divisions: 6,
                      label: '${s.nightStartHour}:00',
                      onChanged: (v) => context.read<AppState>()
                          .updateSettings(s.copyWith(nightStartHour: v.round())),
                    ),
                  ),
                  Text('${s.nightStartHour}:00'),
                ],
              ),
              Row(
                children: [
                  const Text('夜晚结束'),
                  Expanded(
                    child: Slider(
                      value: s.nightEndHour.toDouble().clamp(0, 11),
                      min: 0, max: 11, divisions: 11,
                      label: '${s.nightEndHour}:00',
                      onChanged: (v) => context.read<AppState>()
                          .updateSettings(s.copyWith(nightEndHour: v.round())),
                    ),
                  ),
                  Text('${s.nightEndHour}:00'),
                ],
              ),
            ],
            ListTile(
              leading: s.chatBackground.isEmpty
                  ? const Icon(Icons.image)
                  : CircleAvatar(backgroundImage: FileImage(File(s.chatBackground))),
              title: const Text('自定义主题背景'),
              subtitle: Text(s.chatBackground.isEmpty ? '未设置' : '已设置'),
              trailing: s.chatBackground.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: '恢复默认',
                      onPressed: () =>
                          context.read<AppState>().updateSettings(s.copyWith(chatBackground: '')),
                    )
                  : null,
              onTap: () async {
                final r = await FilePicker.platform.pickFiles(type: FileType.image);
                if (r != null && r.files.isNotEmpty) {
                  await context.read<AppState>()
                      .updateSettings(s.copyWith(chatBackground: r.files.first.path ?? ''));
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- Persona ----------------
class _PersonaSection extends StatefulWidget {
  const _PersonaSection();
  @override
  State<_PersonaSection> createState() => _PersonaSectionState();
}

class _PersonaSectionState extends State<_PersonaSection> {
  late TextEditingController _name;
  late TextEditingController _gender;
  late TextEditingController _relation;
  late TextEditingController _bg;
  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>().settings;
    _name = TextEditingController(text: s.personaName);
    _gender = TextEditingController(text: s.personaGender);
    _relation = TextEditingController(text: s.personaRelation);
    _bg = TextEditingController(text: s.personaBackground);
  }
  @override
  void dispose() {
    _name.dispose();
    _gender.dispose();
    _relation.dispose();
    _bg.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            TextField(controller: _name, decoration: const InputDecoration(labelText: '你的名字', prefixIcon: Icon(Icons.person))),
            const SizedBox(height: 8),
            TextField(controller: _gender, decoration: const InputDecoration(labelText: '你的性别', prefixIcon: Icon(Icons.wc))),
            const SizedBox(height: 8),
            TextField(controller: _relation, decoration: const InputDecoration(labelText: '与角色的关系', prefixIcon: Icon(Icons.favorite))),
            const SizedBox(height: 8),
            TextField(controller: _bg, maxLines: 2, decoration: const InputDecoration(labelText: '你的身份背景', prefixIcon: Icon(Icons.badge))),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () async {
                  await context.read<AppState>().updateSettings(
                        context.read<AppState>().settings.copyWith(
                              personaName: _name.text.trim(),
                              personaGender: _gender.text.trim(),
                              personaRelation: _relation.text.trim(),
                              personaBackground: _bg.text.trim(),
                            ),
                      );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存')));
                  }
                },
                child: const Text('保存'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- Avatar ----------------
class _AvatarSection extends StatefulWidget {
  const _AvatarSection();
  @override
  State<_AvatarSection> createState() => _AvatarSectionState();
}

class _AvatarSectionState extends State<_AvatarSection> {
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>().settings;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          radius: 22,
          backgroundImage: s.userAvatar.isNotEmpty ? FileImage(File(s.userAvatar)) : null,
          child: s.userAvatar.isEmpty ? const Icon(Icons.person) : null,
        ),
        title: const Text('我的头像'),
        subtitle: Text(s.userAvatar.isEmpty ? '未设置' : '已设置'),
        onTap: () async {
          final r = await FilePicker.platform.pickFiles(type: FileType.image);
          if (r != null && r.files.isNotEmpty) {
            final path = r.files.first.path ?? '';
            if (path.isEmpty) return;
            final cropped = await Navigator.push<String>(context,
                MaterialPageRoute(builder: (_) => AvatarCropScreen(imagePath: path)));
            if (cropped != null) {
              await context.read<AppState>().updateSettings(s.copyWith(userAvatar: cropped));
            }
          }
        },
      ),
    );
  }
}

class _ShowAvatarSection extends StatefulWidget {
  const _ShowAvatarSection();
  @override
  State<_ShowAvatarSection> createState() => _ShowAvatarSectionState();
}

class _ShowAvatarSectionState extends State<_ShowAvatarSection> {
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>().settings;
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            dense: true,
            title: const Text('展示角色头像'),
            value: s.showCharAvatar,
            onChanged: (v) => context.read<AppState>().updateSettings(s.copyWith(showCharAvatar: v)),
          ),
          SwitchListTile(
            dense: true,
            title: const Text('展示我的头像'),
            value: s.showUserAvatar,
            onChanged: (v) => context.read<AppState>().updateSettings(s.copyWith(showUserAvatar: v)),
          ),
        ],
      ),
    );
  }
}

// ---------------- Chat & memory ----------------
class _ChatSettingsSection extends StatefulWidget {
  const _ChatSettingsSection();
  @override
  State<_ChatSettingsSection> createState() => _ChatSettingsSectionState();
}

class _ChatSettingsSectionState extends State<_ChatSettingsSection> {
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>().settings;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                const Text('上下文轮数'),
                const Spacer(),
                SizedBox(
                  width: 160,
                  child: Slider(
                    value: s.contextTurns.toDouble().clamp(4, 60),
                    min: 4,
                    max: 60,
                    divisions: 56,
                    label: '${s.contextTurns}',
                    onChanged: (v) => context.read<AppState>()
                        .updateSettings(s.copyWith(contextTurns: v.round())),
                  ),
                ),
                Text('${s.contextTurns}'),
              ],
            ),
            SwitchListTile(
              dense: true,
              title: const Text('记忆注入 (AGENTS.md)'),
              value: s.memoryEnabled,
              onChanged: (v) => context.read<AppState>().updateSettings(s.copyWith(memoryEnabled: v)),
            ),
            SwitchListTile(
              dense: true,
              title: const Text('感应现实(自动记录日期时间)'),
              value: s.realSense,
              onChanged: (v) => context.read<AppState>().updateSettings(s.copyWith(realSense: v)),
            ),
            SwitchListTile(
              dense: true,
              title: const Text('记忆达上限自动删除'),
              value: s.memoryAutoPrune,
              onChanged: (v) => context.read<AppState>().updateSettings(s.copyWith(memoryAutoPrune: v)),
            ),
            if (s.memoryAutoPrune)
              Row(
                children: [
                  const Text('记忆上限'),
                  const Spacer(),
                  SizedBox(
                    width: 160,
                    child: Slider(
                      value: s.memoryLimit.toDouble().clamp(50, 2000),
                      min: 50,
                      max: 2000,
                      divisions: 39,
                      label: '${s.memoryLimit}',
                      onChanged: (v) => context.read<AppState>()
                          .updateSettings(s.copyWith(memoryLimit: v.round())),
                    ),
                  ),
                  Text('${s.memoryLimit}'),
                ],
              ),
            Row(
              children: [
                const Text('自动记忆间隔'),
                const Spacer(),
                SizedBox(
                  width: 140,
                  child: Slider(
                    value: s.autoMemoryEvery.toDouble().clamp(2, 20),
                    min: 2, max: 20, divisions: 18,
                    label: '${s.autoMemoryEvery}',
                    onChanged: (v) => context.read<AppState>()
                        .updateSettings(s.copyWith(autoMemoryEvery: v.round())),
                  ),
                ),
                Text('${s.autoMemoryEvery}条'),
              ],
            ),
            SwitchListTile(
              dense: true,
              title: const Text('输出思考内容'),
              value: s.outputThinking,
              onChanged: (v) => context.read<AppState>().updateSettings(s.copyWith(outputThinking: v)),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- Data ----------------
class _DataSection extends StatefulWidget {
  const _DataSection();
  @override
  State<_DataSection> createState() => _DataSectionState();
}

class _DataSectionState extends State<_DataSection> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.upload_file),
            title: const Text('导出全部数据'),
            subtitle: const Text('含角色、聊天、记忆、世界书'),
            onTap: _busy ? null : () async {
              setState(() => _busy = true);
              final ok = await context.read<AppState>().exportToFile('mostaron_backup.json');
              setState(() => _busy = false);
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(ok ? '导出成功' : '导出失败')));
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text('导入全部数据'),
            subtitle: const Text('从 JSON 备份恢复（覆盖当前数据）'),
            onTap: _busy ? null : () async {
              setState(() => _busy = true);
              final ok = await context.read<AppState>().importFromFile();
              setState(() => _busy = false);
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(ok ? '导入成功' : '导入失败')));
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.menu_book),
            title: const Text('世界书'),
            subtitle: const Text('添加/删除全局世界书，在角色/群聊里勾选启用'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WorldbookScreen())),
          ),
        ],
      ),
    );
  }
}

class _HelpSection extends StatelessWidget {
  const _HelpSection();
  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.help_outline),
        title: const Text('使用说明'),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UsageHelpScreen())),
      ),
    );
  }
}

/// 带搜索框的模型分组选择器（每行"添加"按钮 + 底部"确定"）
Future<List<String>?> showModelPicker(BuildContext context, List<String> models) {
  final selected = <String>{};
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      String query = '';
      return StatefulBuilder(
        builder: (ctx, setState) {
          final filtered = models
              .where((m) => query.isEmpty || m.toLowerCase().contains(query.toLowerCase()))
              .toList();
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.7,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text('选择模型（点"添加"加入分组）',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: TextField(
                      decoration: const InputDecoration(hintText: '搜索模型名…', prefixIcon: Icon(Icons.search)),
                      onChanged: (v) => setState(() => query = v),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final m = filtered[i];
                        final added = selected.contains(m);
                        return ListTile(
                          dense: true,
                          title: Text(m, style: const TextStyle(fontSize: 14)),
                          trailing: TextButton.icon(
                            icon: Icon(added ? Icons.check : Icons.add, size: 16),
                            label: Text(added ? '已添加' : '添加'),
                            onPressed: () => setState(() => added ? selected.remove(m) : selected.add(m)),
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx, selected.toList()),
                        child: Text('确定（已添加 ${selected.length} 个模型）'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

class _ManageModelsSheet extends StatefulWidget {
  final ProviderConfig provider;
  const _ManageModelsSheet({required this.provider});
  @override
  State<_ManageModelsSheet> createState() => _ManageModelsSheetState();
}

class _ManageModelsSheetState extends State<_ManageModelsSheet> {
  late List<String> _models;
  late String _defaultModel;
  bool _fetching = false;

  @override
  void initState() {
    super.initState();
    _models = List.of(widget.provider.models);
    _defaultModel = widget.provider.model;
  }

  Future<void> _add() async {
    setState(() => _fetching = true);
    try {
      final fetched =
          await ApiClient().getModels(baseUrl: widget.provider.baseUrl, apiKey: widget.provider.apiKey);
      final picked = await showModelPicker(context, fetched);
      if (picked != null) {
        for (final m in picked) {
          if (!_models.contains(m)) _models.add(m);
        }
        if (_defaultModel.isEmpty && _models.isNotEmpty) _defaultModel = _models.first;
        await _save();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('获取失败: $e')));
    } finally {
      setState(() => _fetching = false);
    }
  }

  Future<void> _save() async {
    await context
        .read<AppState>()
        .updateProvider(widget.provider.copyWith(models: _models, model: _defaultModel));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('模型分组（${widget.provider.name}）',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            Expanded(
              child: _models.isEmpty
                  ? const Center(child: Text('暂无模型，点下方"添加模型"'))
                  : ListView.builder(
                      itemCount: _models.length,
                      itemBuilder: (context, i) => RadioListTile<String>(
                        dense: true,
                        title: Text(_models[i], style: const TextStyle(fontSize: 14)),
                        value: _models[i],
                        groupValue: _defaultModel,
                        onChanged: (v) {
                          setState(() => _defaultModel = v!);
                          _save();
                        },
                        secondary: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () {
                            setState(() => _models.removeAt(i));
                            _save();
                          },
                        ),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      icon: _fetching
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.add),
                      label: const Text('添加模型'),
                      onPressed: _fetching ? null : _add,
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('完成')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BubbleSection extends StatefulWidget {
  const _BubbleSection();
  @override
  State<_BubbleSection> createState() => _BubbleSectionState();
}

class _BubbleSectionState extends State<_BubbleSection> {
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>().settings;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('我的气泡颜色', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            _colorRow(s.bubbleSelfColor, (hex) => context.read<AppState>()
                .updateSettings(s.copyWith(bubbleSelfColor: hex))),
            const SizedBox(height: 12),
            const Text('角色气泡颜色', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            _colorRow(s.bubbleCharColor, (hex) => context.read<AppState>()
                .updateSettings(s.copyWith(bubbleCharColor: hex))),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('气泡透明度'),
                Expanded(
                  child: Slider(
                    value: s.bubbleOpacity.clamp(0.0, 1.0),
                    min: 0,
                    max: 1,
                    divisions: 100,
                    onChanged: (v) => context.read<AppState>()
                        .updateSettings(s.copyWith(bubbleOpacity: v)),
                  ),
                ),
                Text('${(s.bubbleOpacity * 100).round()}%'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _colorRow(String current, void Function(String hex) onPick) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _chip(null, '默认', current.isEmpty, () => onPick('')),
        for (final c in bubbleColorChoices)
          _chip(colorToHex(c), '', current == colorToHex(c), () => onPick(colorToHex(c))),
        _chip(
          _currentCustom(current),
          '调色盘',
          false,
          () async {
            final c = await showColorPicker(context, initial: parseHexColor(current) ?? const Color(0xFF1E88E5));
            if (c != null) onPick(colorToHex(c));
          },
        ),
      ],
    );
  }

  String _currentCustom(String current) {
    for (final c in bubbleColorChoices) {
      if (colorToHex(c) == current) return '';
    }
    return current;
  }

  Widget _chip(String? hex, String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: hex == null ? Theme.of(context).colorScheme.surfaceContainerHighest : parseHexColor(hex),
          shape: BoxShape.circle,
          border: Border.all(color: selected ? Theme.of(context).colorScheme.primary : Colors.transparent, width: 2),
        ),
        alignment: Alignment.center,
        child: hex == null
            ? Text('默', style: const TextStyle(fontSize: 11))
            : selected
                ? const Icon(Icons.check, color: Colors.white, size: 18)
                : null,
      ),
    );
  }
}
