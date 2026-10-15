import 'package:flutter/material.dart';

/// Shown while the app boots, same look as the native splash.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Image(
            image: AssetImage('assets/images/splash.png'),
            width: 280,
            height: 280,
            filterQuality: FilterQuality.high,
          ),
        ),
      );
}