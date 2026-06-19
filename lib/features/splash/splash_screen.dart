import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/prefs_service.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/farmland_background.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final auth = context.read<AuthProvider>();
    await Future.wait<void>([
      auth.bootstrap(),
      Future<void>.delayed(const Duration(milliseconds: 1800)),
    ]);
    if (!mounted) return;
    if (auth.status == AuthStatus.authenticated) {
      context.go('/home');
    } else if (!await PrefsService.onboardingSeen()) {
      if (mounted) context.go('/onboarding');
    } else {
      if (mounted) context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FarmlandBackground(
        child: SafeArea(
          child: Stack(
            children: [
              Center(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 760),
                  curve: Curves.easeOut,
                  builder: (_, op, child) => Opacity(
                      opacity: op,
                      child: Transform.translate(offset: Offset(0, (1 - op) * 14), child: child)),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 86,
                        height: 86,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
                        ),
                        child: const Icon(Icons.eco_rounded, color: Colors.white, size: 46),
                      ),
                      const SizedBox(height: 20),
                      const Text('Agricore',
                          style: TextStyle(
                              fontFamily: 'Fraunces',
                              fontWeight: FontWeight.w900,
                              fontSize: 44,
                              letterSpacing: -1,
                              color: Colors.white)),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Text('Smart farming for African agriculture',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 14,
                                height: 1.5,
                                color: Colors.white.withValues(alpha: 0.85))),
                      ),
                      const SizedBox(height: 40),
                      SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.4, color: Colors.white.withValues(alpha: 0.9)),
                      ),
                    ],
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 30),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('POWERED BY',
                          style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 10,
                              letterSpacing: 3,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.6))),
                      const SizedBox(height: 4),
                      const Text('LUMORA',
                          style: TextStyle(
                              fontFamily: 'Fraunces',
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 4,
                              color: AppColors.gold)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
