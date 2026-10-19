import 'package:flutter/material.dart';
import 'api.dart';
import 'common.dart';
import 'screens/login.dart';
import 'screens/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.i.load();
  runApp(const AdminApp());
}

class AdminApp extends StatefulWidget {
  const AdminApp({super.key});
  @override
  State<AdminApp> createState() => _AdminAppState();
}

class _AdminAppState extends State<AdminApp> {
  @override
  void initState() {
    super.initState();
    Api.i.onUnauthorized = () async {
      await Api.i.logout();
      if (mounted) setState(() {});
    };
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Krutarth PMAY - Admin',
        debugShowCheckedModeBanner: false,
        theme: appTheme(),
        home: Api.i.loggedIn
            ? AdminShell(onLogout: () async {
                await Api.i.logout();
                setState(() {});
              })
            : LoginScreen(onDone: () => setState(() {})),
      );
}
