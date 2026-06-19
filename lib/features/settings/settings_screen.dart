import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/app_toast.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _push = true;
  bool _email = false;
  bool _orderUpdates = true;

  @override
  Widget build(BuildContext context) {
    final u = context.watch<AuthProvider>().user;
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.cream,
        foregroundColor: AppColors.inkWarm,
        elevation: 0,
        title: const Text('Settings',
            style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 22)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          // ---- account card ----
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.line)),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.emeraldGrad),
                  child: Text(u?.initials ?? '?',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(u?.username ?? 'Guest',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontFamily: 'Fraunces',
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                              color: AppColors.inkWarm)),
                      const SizedBox(height: 2),
                      Text(u?.email ?? u?.roleLabel ?? 'Agricore member',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppColors.slate500)),
                    ],
                  ),
                ),
                if (u?.isVerified ?? false)
                  const Icon(Icons.verified_rounded, color: Color(0xFF0EA5E9), size: 22),
              ],
            ),
          ),
          const SizedBox(height: 22),

          _sectionLabel('Notifications'),
          _group([
            _switchTile(Icons.notifications_active_rounded, 'green', 'Push notifications',
                'Alerts on this device', _push, (v) => setState(() => _push = v)),
            _divider(),
            _switchTile(Icons.mark_email_unread_rounded, 'gold', 'Email updates',
                'News and offers by email', _email, (v) => setState(() => _email = v)),
            _divider(),
            _switchTile(Icons.local_shipping_rounded, 'sky', 'Order updates',
                'Escrow and delivery status', _orderUpdates, (v) => setState(() => _orderUpdates = v)),
          ]),
          const SizedBox(height: 22),

          _sectionLabel('Preferences'),
          _group([
            _navTile(Icons.language_rounded, 'sky', 'Language', 'English'),
            _divider(),
            _navTile(Icons.payments_rounded, 'green', 'Currency', 'UGX — Ugandan Shilling'),
            _divider(),
            _navTile(Icons.dark_mode_rounded, 'plum', 'Appearance', 'Light'),
          ]),
          const SizedBox(height: 22),

          _sectionLabel('Account & security'),
          _group([
            _navTile(Icons.lock_rounded, 'green', 'Password', 'Change your password'),
            _divider(),
            _navTile(Icons.shield_rounded, 'gold', 'Privacy', 'Data and permissions'),
            _divider(),
            _navTile(Icons.account_balance_wallet_rounded, 'sky', 'Payout details', 'Bank and mobile money'),
          ]),
          const SizedBox(height: 22),

          _sectionLabel('About'),
          _group([
            _navTile(Icons.help_outline_rounded, 'sky', 'Help center', 'Guides and support'),
            _divider(),
            _navTile(Icons.description_rounded, 'gold', 'Terms & policies', 'Legal and privacy'),
            _divider(),
            _navTile(Icons.info_outline_rounded, 'green', 'About Agricore', 'Version 1.0.0'),
          ]),
          const SizedBox(height: 24),

          GestureDetector(
            onTap: () => context.read<AuthProvider>().logout(),
            child: Container(
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: Colors.white,
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
          const SizedBox(height: 18),
          const Center(
            child: Text('Powered by LUMORA',
                style: TextStyle(
                    fontFamily: 'Inter', fontSize: 11.5, letterSpacing: 1.2, color: AppColors.slate500)),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String t) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(t.toUpperCase(),
            style: const TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                fontSize: 11.5,
                letterSpacing: 1.4,
                color: AppColors.g600)),
      );

  Widget _group(List<Widget> children) => Container(
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.line)),
        child: Column(children: children),
      );

  Widget _divider() => const Divider(height: 1, indent: 60, color: AppColors.line);

  Widget _iconChip(IconData icon, String tone) {
    const map = {
      'green': [Color(0xFFE7F4EC), Color(0xFF0F7A4B)],
      'gold': [Color(0xFFF7EED6), Color(0xFFA9791D)],
      'sky': [Color(0xFFE4EEF6), Color(0xFF2F6F9E)],
      'plum': [Color(0xFFEFE7F4), Color(0xFF7C4FA0)],
    };
    final c = map[tone] ?? map['green']!;
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(color: c[0], borderRadius: BorderRadius.circular(11)),
      child: Icon(icon, color: c[1], size: 19),
    );
  }

  Widget _switchTile(IconData icon, String tone, String title, String sub, bool value,
      ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(
        children: [
          _iconChip(icon, tone),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 14.5, color: AppColors.inkWarm)),
                Text(sub,
                    style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppColors.slate500)),
              ],
            ),
          ),
          Switch(value: value, activeColor: AppColors.green, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _navTile(IconData icon, String tone, String title, String sub) {
    return InkWell(
      onTap: () => showToast(context, '$title settings are coming soon.'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
        child: Row(
          children: [
            _iconChip(icon, tone),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 14.5, color: AppColors.inkWarm)),
                  Text(sub,
                      style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppColors.slate500)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.slate500),
          ],
        ),
      ),
    );
  }
}
