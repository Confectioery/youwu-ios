import 'package:flutter/material.dart';
import 'ui/main_scaffold.dart';
import 'ui/login/welcome_screen.dart';
import 'data/local/settings_store.dart';

class YouwuApp extends StatelessWidget {
  const YouwuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '有梧',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2D6A4F),
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2D6A4F),
          brightness: Brightness.dark,
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
        ),
      ),
      themeMode: ThemeMode.system,
      home: const _RootScreen(),
    );
  }
}

/// 根屏幕：判断是否完成初次设置
class _RootScreen extends StatefulWidget {
  const _RootScreen();

  @override
  State<_RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<_RootScreen> {
  final SettingsStore _settings = SettingsStore();
  bool _checked = false;
  bool _hasAccount = false;

  @override
  void initState() {
    super.initState();
    _checkSetup();
  }

  Future<void> _checkSetup() async {
    final account = await _settings.account;
    setState(() {
      _hasAccount = account.isNotEmpty;
      _checked = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_hasAccount) {
      return WelcomeScreen(onComplete: () {
        setState(() => _hasAccount = true);
      });
    }
    return const MainScaffold();
  }
}
