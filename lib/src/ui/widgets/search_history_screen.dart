import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../chat_screen.dart';
import '../group_chat_screen.dart';
import 'avatars.dart';
import 'search_util.dart';

/// 查找聊天记录界面（角色或群聊通用）。
/// 顶部显示共多少条，结果横版排版：头像 + 姓名 + 命中消息（关键词主题色）。
/// 点击某条结果用 [_onJump] 跳转到对应消息。
class SearchHistoryScreen extends StatefulWidget {
  final String? characterId; // 单聊用
  final String? groupId; // 群聊用
  const SearchHistoryScreen({super.key, this.characterId, this.groupId});

  @override
  State<SearchHistoryScreen> createState() => _SearchHistoryScreenState();
}

class _SearchHistoryScreenState extends State<SearchHistoryScreen> {
  final TextEditingController _ctrl = TextEditingController();
  List<ChatMessage> _all = [];
  List<ChatMessage> _results = [];
  Character? _char;
  ChatGroup? _group;
  Map<String, Character> _members = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    if (widget.characterId != null) {
      _char = await state.getCharacter(widget.characterId!);
      final session = await state.getOrCreateSession(widget.characterId!);
      _all = await state.messagesFor(session.id);
    } else if (widget.groupId != null) {
      _group = await state.getGroup(widget.groupId!);
      _all = await state.groupMessages(widget.groupId!);
      if (_group != null) {
        for (final mid in _group!.memberIds) {
          final c = await state.getCharacter(mid);
          if (c != null) _members[mid] = c;
        }
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  void _search(String q) {
    setState(() => _results = SearchUtil.search(_all, q));
  }

  /// 打开聊天页并定位到该消息；查找页保留在栈中，返回键会回到查找结果页。
  void _openMessage(BuildContext context, ChatMessage m) {
    if (widget.characterId != null) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ChatScreen(characterId: widget.characterId!, initialSearchTargetId: m.id)),
      );
    } else if (widget.groupId != null) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => GroupChatScreen(groupId: widget.groupId!, initialSearchTargetId: m.id)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final scale = state.settings.fontSize;
    return Scaffold(
      appBar: AppBar(
        title: Text(_char != null ? '查找 ${_char!.name} 的聊天记录' : (_group != null ? '查找 ${_group!.name} 的聊天记录' : '查找聊天记录')),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              onChanged: _search,
              decoration: InputDecoration(
                hintText: '输入关键词搜索聊天记录…',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                isDense: true,
              ),
              onSubmitted: _search,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _results.isEmpty ? (_ctrl.text.trim().isEmpty ? '' : '未找到匹配的消息') : '共 ${_results.length} 条记录',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12 * scale),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _results.isEmpty
                    ? const Center(child: Text('输入关键词开始搜索', style: TextStyle(color: Colors.blueGrey)))
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        itemCount: _results.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (context, i) {
                          final m = _results[i];
                          final senderName = widget.characterId != null
                              ? (_char?.name ?? '角色')
                              : (m.role == 'user'
                                  ? (state.settings.personaName)
                                  : (_members[m.senderCharacterId]?.name ?? '?'));
                          final avatar = widget.characterId != null
                              ? (m.role == 'user'
                                  ? buildUserAvatar(context, state.settings, 36)
                                  : buildCharacterAvatar(context, _char!, 36))
                              : (m.role == 'user'
                                  ? buildUserAvatar(context, state.settings, 36)
                                  : (_members[m.senderCharacterId] != null
                                      ? buildCharacterAvatar(context, _members[m.senderCharacterId]!, 36)
                                      : const CircleAvatar(child: Icon(Icons.person))));
                          return _ResultCard(
                            message: m,
                            total: _results.length,
                            senderName: senderName,
                            avatar: avatar,
                            query: _ctrl.text.trim(),
                            hitColor: scheme.primary,
                            scale: scale,
                            onTap: () => _openMessage(context, m),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final ChatMessage message;
  final int total;
  final String senderName;
  final Widget avatar;
  final String query;
  final Color hitColor;
  final double scale;
  final VoidCallback onTap;
  const _ResultCard({
    required this.message,
    required this.total,
    required this.senderName,
    required this.avatar,
    required this.query,
    required this.hitColor,
    required this.scale,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = SearchUtil.ellipsizeAround(message.content, query);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              ClipOval(child: SizedBox(width: 36, height: 36, child: avatar)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(senderName,
                            style: TextStyle(fontSize: 13 * scale, color: scheme.primary, fontWeight: FontWeight.w600)),
                        const Spacer(),
                        Text(_time(message.createdAt), style: TextStyle(fontSize: 11 * scale, color: scheme.onSurfaceVariant)),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text.rich(
                      TextSpan(children: SearchUtil.highlight(shown, query, hitColor, scale, normalColor: scheme.onSurface)),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _time(int ms) {
    if (ms <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String p2(int v) => v.toString().padLeft(2, '0');
    return '${d.month}-${d.day} ${p2(d.hour)}:${p2(d.minute)}';
  }
}
