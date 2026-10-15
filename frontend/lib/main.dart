import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/shell.dart';
import 'screens/welcome.dart';
import 'push.dart';
import 'splash.dart';
import 'state.dart';
import 'theme.dart';

void main() => runApp(ChangeNotifierProvider(create: (_) => AppState()..init(), child: const PmayApp()));

/// Keep the splash visible for at least this long, even if init finishes sooner.
const _minSplash = Duration(milliseconds: 1800);

class PmayApp extends StatefulWidget {
  const PmayApp({super.key});
  @override
  State<PmayApp> createState() => _PmayAppState();
}

class _PmayAppState extends State<PmayApp> {
  bool _minTimeDone = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(_minSplash, () {
      if (mounted) setState(() => _minTimeDone = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return MaterialApp(
      title: 'Krutarth - PMAY',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: messengerKey,
      theme: appTheme(),
      home: !(s.ready && _minTimeDone)
          ? const SplashScreen()
          : s.inApp
              ? const MainShell()
              : const WelcomeScreen(),
    );
  }
}