import 'package:flutter/material.dart';

/// Shown while the app boots. Uses the same image and size as the
/// Android 12 system splash so the handoff looks seamless.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Image(
            image: AssetImage('assets/images/splash_android12.png'),
            width: 288,
            height: 288,
            filterQuality: FilterQuality.high,
          ),
        ),
      );
}
