class ProviderPreset {
  final String name;
  final String baseUrl;
  final String model;
  const ProviderPreset(this.name, this.baseUrl, this.model);
}

class ProviderPresets {
  static const List<ProviderPreset> list = [
    ProviderPreset('OpenAI', 'https://api.openai.com/v1', 'gpt-4o'),
    ProviderPreset('DeepSeek', 'https://api.deepseek.com/v1', 'deepseek-chat'),
    ProviderPreset('Moonshot/Kimi', 'https://api.moonshot.cn/v1', 'moonshot-v1-8k'),
    ProviderPreset('智谱 GLM', 'https://open.bigmodel.cn/api/paas/v4', 'glm-4-flash'),
    ProviderPreset('阿里千问', 'https://dashscope.aliyuncs.com/compatible-mode/v1', 'qwen-plus'),
    ProviderPreset('Ollama(本地)', 'http://localhost:11434/v1', 'llama3.1'),
  ];

  static ProviderPreset? find(String url) {
    for (final p in list) {
      if (p.baseUrl.trim() == url.trim()) return p;
    }
    return null;
  }
}
