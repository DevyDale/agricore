import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/responsive_body.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final u = auth.user;
    return ResponsiveBody(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          Center(
            child: Container(
              width: 92,
              height: 92,
              alignment: Alignment.center,
              decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.emeraldGrad),
              child: Text(u?.initials ?? '?',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 34, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(u?.username ?? '-',
                style: const TextStyle(
                    fontFamily: 'Fraunces',
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppColors.inkWarm)),
          ),
          Center(
            child: Text(u?.roleLabel ?? '',
                style: const TextStyle(fontFamily: 'Inter', color: AppColors.slate500)),
          ),
          const SizedBox(height: 28),
          _InfoTile(icon: Icons.mail_outline, label: 'Email', value: u?.email ?? '-'),
          _InfoTile(
              icon: Icons.phone_outlined,
              label: 'Phone',
              value: (u?.phone == null || u!.phone!.isEmpty) ? 'Not set' : u.phone!),
          _InfoTile(
              icon: Icons.verified_outlined,
              label: 'Verified',
              value: (u?.isVerified ?? false) ? 'Yes' : 'No'),
          const SizedBox(height: 28),
          GestureDetector(
            onTap: () => context.read<AuthProvider>().logout(),
            child: Container(
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5))),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.logout_rounded, color: Colors.redAccent, size: 20),
                  SizedBox(width: 8),
                  Text('Log out',
                      style: TextStyle(
                          fontFamily: 'Inter', color: Colors.redAccent, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoTile({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.line)),
      child: Row(
        children: [
          Icon(icon, color: AppColors.g700),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontFamily: 'Inter', color: AppColors.slate500, fontSize: 12.5)),
              const SizedBox(height: 2),
              Text(value,
                  style: const TextStyle(
                      fontFamily: 'Inter',
                      color: AppColors.inkWarm,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}
