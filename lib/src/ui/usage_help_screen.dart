import 'package:flutter/material.dart';

class UsageHelpScreen extends StatelessWidget {
  const UsageHelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('使用说明')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          _Mod('1. 接口与模型', [
            '设置 → 接口：添加你的 API Key（OpenAI 兼容，如 DeepSeek/Kimi/GLM/千问/Ollama 等），可自定义 Base URL 和模型名。',
            '点接口行进入"模型分组"，可拉取/添加多个模型并设默认；点"获取模型"可拉取该 Key 的可用模型（带搜索，可多选）。',
            '连接可测试，模型可随时在聊天里切换（输入框左侧按钮）。',
          ]),
          _Mod('2. 角色', [
            '创建/编辑角色：头像、人设、性格、语气、背景、场景、示例对话、开场白、聊天背景等。',
            '可用文字一键生成角色（含场景、示例对话等），可撤销。',
            '导入/导出 SillyTavern 角色卡（PNG / WebP / JSON，V1/V2）：主页右上角"+"导入，长按角色导出。',
            '导出 PNG 角色卡时，头像会自动转成 PNG；头像为空或无法转换会提示不支持，也可另选一张图片导出（自动转 PNG）。',
            '回复风格选"简短对话"会更简洁像日常对话。',
            '角色独立模型/Key、独立角色设置（上下文/记忆上限/感应现实等）。',
            '主页角色卡右上角显示最新消息时间（当日显示时间，其余显示日期）。',
          ]),
          _Mod('3. 聊天', [
            '发送消息后角色流式回复；支持（动作）+台词混合渲染。',
            '最新一轮消息下方（纯图标）：重新说 / 删除 / 编辑 / 继续说 / 生成我的回复。',
            '输入框左上角 AI 改写按钮：改写输入中的消息（改写时清空输入并显示"正在改写…"，可撤销 / 取消）。',
            '输入框左下角 ＋ 按钮：小面板可选 **切换模型 / 添加图片 / 选择文件**。',
            '上传的图片或文件会显示在**输入框上方**，不立即发送；与你输入的文字**合并成一条消息**一起发送，可逐个删除。',
            '**图片会直接显示在气泡里**（按原图宽高比缩放），点开可全屏查看、双指缩放、**右上角按钮保存到相册**；文件显示为文件名卡片。',
            '聊天列表按**条数**定位：查找跳转、翻历史都不会再"差一点"或"突然跳到底"。上滑自动加载更早，下滑自动加载更晚。',
            '打字机输出时，消息左上角显示"思考中"；输出完成后可点"思考"展开查看。',
            '输入框：回车换行，点发送键发送。',
            '顶部菜单：角色设置、聊天窗口设置、查找聊天记录、长期记忆、选择世界书、删除对话。',
            '查找聊天记录：点结果会**滑动到对应消息并居中高亮**，返回键可回到查找结果页。',
          ]),
          _Mod('4. 群聊', [
            '点"创建群聊"先选**记忆模式**（整体/独立/同步），再进入创建页；建好后不可改。',
            '可创建群聊：选成员、设头像/背景/回复模式（全员/指定/自然聊天）。',
            '成员互相可见，可长按成员编辑角色，可从角色长按"创建群聊"。',
            '群聊也有模型切换、聊天窗口设置、查找聊天记录、世界书、长记忆、简短对话模式。',
            '可克隆群聊（含聊天与记忆 / 全新，或改记忆模式克隆）；无论哪种克隆，名字都会加"副本"。',
          ]),
          _Mod('5. 记忆', [
            '长期记忆页可手动添加/删除/置顶；**置顶的记忆显示在最上方**，并写入 AGENTS.md 长期生效。',
            '开启"记忆注入"后，置顶规则 + 最近记忆都会进入系统提示。',
            '"AI 生成记忆"会让 AI 从对话**提炼一份记忆条目**（不是续写对话）。',
            '开启记忆后，角色每回复满设定条数（默认 6）会**自动生成**一次长记忆；群聊三种记忆模式都支持。',
            '感应现实：让角色知道当前日期时间。',
            '**记忆达上限自动压缩**：达到上限时，取最老的「压缩数量比」那部分，按「压缩比例」合并成更少的条目（默认上限 100、压缩数量比 20%、压缩比例 50%：100 条 → 压缩最老 20 条 → 合并成 10 条，总数变 90）。压缩比例 100% 时直接删除这批旧记忆。**置顶记忆永不参与压缩**。',
            '三个参数都在 设置 → 记忆 里调整：上限 10–999、压缩数量比 10%–100%、压缩比例 10%–100%。',
            '压缩需要调用你的模型接口；未配置接口时会退化为直接删除这批旧记忆。',
          ]),
          _Mod('6. 世界书', [
            '世界书全局管理："设置 → 世界书"里新增/编辑/删除。',
            '每个角色/群可在编辑里"选择世界书"，勾选要启用的条目（默认全不启用）。',
            '命中关键词的条目会作为背景注入，增强沉浸。',
          ]),
          _Mod('7. 外观与主题', [
            '主题色、亮/暗/跟随系统、夜间自动切暗色（可设起止时间）。',
            '自定义主题背景：上传图片，聊天/群聊/主页都会透出。',
            '聊天气泡：可分别设置我的/角色气泡颜色与透明度（调色盘选择，可保存删除）。',
          ]),
          _Mod('8. 数据', [
            '一键导出/导入全部数据（含角色、聊天、记忆、世界书、接口配置）。',
            '导出会**内嵌角色头像 / 聊天背景 / 聊天里的图片**，换机导入后图片不丢失；旧版本备份也能正常导入。',
            '导出角色卡时可选择**是否包含聊天记录**（写在卡片扩展字段里，其他前端会忽略）；导入带聊天记录的卡会自动恢复对话。',
            '导入为合并模式：不会覆盖已存在的数据。',
            '全部数据本地存储（SQLite），不上传任何内容。',
          ]),
          _Mod('项目仓库', [
            '源码与 Release APK：https://github.com/weme1206/mostaron',
            '数据全在本地，尤其注意保管你自己的 API Key。',
          ]),
        ],
      ),
    );
  }
}

class _Mod extends StatelessWidget {
  final String title;
  final List<String> body;
  const _Mod(this.title, this.body);

  /// 极简 Markdown：只处理 **加粗**，其余原样。
  static List<TextSpan> _spans(String text, TextStyle base) {
    final out = <TextSpan>[];
    final parts = text.split('**');
    for (var i = 0; i < parts.length; i++) {
      if (parts[i].isEmpty) continue;
      out.add(TextSpan(
        text: parts[i],
        style: i.isOdd
            ? base.copyWith(fontWeight: FontWeight.bold)
            : base,
      ));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(height: 1.5, color: Theme.of(context).colorScheme.onSurface);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 6),
          for (final line in body)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text.rich(TextSpan(children: [
                TextSpan(text: '• ', style: base),
                ..._spans(line, base),
              ])),
            ),
        ],
      ),
    );
  }
}
