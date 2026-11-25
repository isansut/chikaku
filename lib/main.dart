import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/pairing_screen.dart';
import 'screens/permission_screen.dart';
import 'services/chikaku_controller.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ChikakuApp());
}

class ChikakuApp extends StatefulWidget {
  const ChikakuApp({super.key});

  @override
  State<ChikakuApp> createState() => _ChikakuAppState();
}

class _ChikakuAppState extends State<ChikakuApp> {
  final ChikakuController _controller = ChikakuController();

  @override
  void initState() {
    super.initState();
    _controller.init();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chikaku',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          if (!_controller.isInitialized) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            );
          }
          if (!_controller.isPaired) {
            return PermissionGateScreen(
              child: PairingScreen(controller: _controller),
            );
          }
          return PermissionGateScreen(
            child: HomeScreen(controller: _controller),
          );
        },
      ),
    );
  }
}
