import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});
  @override
  Widget build(BuildContext context) => const Center(
        child: SizedBox(
            width: 30,
            height: 30,
            child: CircularProgressIndicator(strokeWidth: 2.6, color: AppColors.g600)),
      );
}

class ErrorView extends StatelessWidget {
  final String message;
  final Future<void> Function()? onRetry;
  const ErrorView({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                  color: const Color(0xFFF6E6DF), borderRadius: BorderRadius.circular(20)),
              child: const Icon(Icons.cloud_off_rounded, size: 30, color: Color(0xFFB15A36)),
            ),
            const SizedBox(height: 16),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'Inter', color: AppColors.slate600, height: 1.5)),
            if (onRetry != null) ...[
              const SizedBox(height: 18),
              GestureDetector(
                onTap: () => onRetry!(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                  decoration: BoxDecoration(
                      gradient: AppColors.emeraldGrad, borderRadius: BorderRadius.circular(999)),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.refresh, size: 17, color: Colors.white),
                      SizedBox(width: 8),
                      Text('Retry',
                          style: TextStyle(
                              fontFamily: 'Inter', fontWeight: FontWeight.w700, color: Colors.white)),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  final String text;
  final IconData icon;
  const EmptyView({super.key, required this.text, this.icon = Icons.inbox_rounded});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                  color: const Color(0xFFE7F4EC), borderRadius: BorderRadius.circular(22)),
              child: Icon(icon, size: 34, color: const Color(0xFF0F7A4B)),
            ),
            const SizedBox(height: 16),
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'Inter', color: AppColors.slate600, height: 1.5)),
          ],
        ),
      ),
    );
  }
}
