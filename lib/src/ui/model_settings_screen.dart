import 'package:flutter/material.dart';
import 'settings_screen.dart' show ProvidersSection;

/// 独立的模型/接口设置页
class ModelSettingsScreen extends StatelessWidget {
  const ModelSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('模型设置')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: const [
          Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('接口与 Key', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          ),
          ProvidersSection(),
        ],
      ),
    );
  }
}
