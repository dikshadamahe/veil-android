import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pstream_android/config/app_theme.dart';

/// First paint after cold start; hands off to the main shell.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  static const Duration displayDuration = Duration(milliseconds: 1800);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(SplashScreen.displayDuration, () {
      if (!mounted) {
        return;
      }
      context.replace('/');
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double logoWidth = MediaQuery.sizeOf(context).shortestSide * 0.38;

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              AppColors.blackC75,
              AppColors.purpleC900,
              AppColors.blackC100,
            ],
            stops: <double>[0, 0.42, 1],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                RepaintBoundary(
                  child: Image.asset(
                    'logo.png',
                    width: logoWidth,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                    errorBuilder:
                        (BuildContext context, Object error, StackTrace? st) {
                      return Text(
                        'Veil',
                        style: Theme.of(context).textTheme.displayMedium?.copyWith(
                              color: AppColors.typeLogo,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1.2,
                            ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: AppSpacing.x5),
                Text(
                  'Browse. Resume. Watch.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppColors.typeSecondary,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
