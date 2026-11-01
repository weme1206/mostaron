import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'src/state/app_state.dart';
import 'src/ui/theme.dart';
import 'src/ui/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 沉浸式系统栏：导航栏背景与分隔线完全透明，页面内容延伸到屏幕底部。
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
  ));
  runApp(const MostaronApp());
}

class MostaronApp extends StatelessWidget {
  const MostaronApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState()..init(),
      child: Consumer<AppState>(
        builder: (context, state, _) {
          final accent = state.settings.themeAccent;
          return MaterialApp(
            title: 'mostaron',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(accent),
            darkTheme: AppTheme.dark(accent),
            themeMode: _themeMode(state),
            home: const HomeScreen(),
          );
        },
      ),
    );
  }

  ThemeMode _themeMode(state) {
    final s = state.settings;
    // 夜间自动切暗色
    if (s.nightAutoDark && _isNight(s.nightStartHour, s.nightEndHour)) {
      return ThemeMode.dark;
    }
    if (s.themeMode == 'light') return ThemeMode.light;
    if (s.themeMode == 'dark') return ThemeMode.dark;
    return ThemeMode.system;
  }

  bool _isNight(int startHour, int endHour) {
    final h = DateTime.now().hour;
    if (startHour < endHour) return h >= startHour && h < endHour;
    // 跨天（如 22:00 -> 06:00）
    return h >= startHour || h < endHour;
  }
}
