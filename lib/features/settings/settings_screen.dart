import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/i18n/app_translations.dart';
import '../../core/i18n/locale_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/app_toast.dart';
import '../../core/responsive/responsive.dart';

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
    final loc = context.watch<LocaleProvider>();
    final langName =
        kLanguages.firstWhere((l) => l.code == loc.language, orElse: () => kLanguages.first).name;
    final curr = currencyFor(loc.currency);
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.cream,
        foregroundColor: AppColors.inkWarm,
        elevation: 0,
        title: Text(context.tr('Settings'),
            style: const TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 22)),
      ),
      body: MaxWidthBody(
        child: ListView(
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
            _navTile(Icons.language_rounded, 'sky', context.tr('Language'), langName,
                onTap: _pickLanguage),
            _divider(),
            _navTile(Icons.payments_rounded, 'green', context.tr('Currency'),
                '${curr.code} — ${curr.name}',
                onTap: _pickCurrency),
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
      ),
    );
  }

  Future<void> _pickLanguage() async {
    final loc = context.read<LocaleProvider>();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ChoiceSheet(
        title: context.tr('Language'),
        options: [
          for (final l in kLanguages) (value: l.code, label: l.name, trailing: l.code.toUpperCase()),
        ],
        selected: loc.language,
        onSelect: (code) => loc.setLanguage(code),
      ),
    );
  }

  Future<void> _pickCurrency() async {
    final loc = context.read<LocaleProvider>();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ChoiceSheet(
        title: context.tr('Currency'),
        options: [
          for (final c in kCurrencies) (value: c.code, label: '${c.code} — ${c.name}', trailing: c.symbol),
        ],
        selected: loc.currency,
        onSelect: (code) => loc.setCurrency(code),
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
          Switch(value: value, activeThumbColor: AppColors.green, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _navTile(IconData icon, String tone, String title, String sub, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap ?? () => showToast(context, '$title settings are coming soon.'),
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

typedef _Choice = ({String value, String label, String trailing});

class _ChoiceSheet extends StatelessWidget {
  final String title;
  final List<_Choice> options;
  final String selected;
  final ValueChanged<String> onSelect;
  const _ChoiceSheet(
      {required this.title,
      required this.options,
      required this.selected,
      required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
          color: AppColors.cream,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
                child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                        color: AppColors.line, borderRadius: BorderRadius.circular(99)))),
            const SizedBox(height: 14),
            Text(title,
                style: const TextStyle(
                    fontFamily: 'Fraunces',
                    fontWeight: FontWeight.w800,
                    fontSize: 19,
                    color: AppColors.inkWarm)),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: options.length,
                separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.line),
                itemBuilder: (_, i) {
                  final o = options[i];
                  final on = o.value == selected;
                  return ListTile(
                    onTap: () {
                      onSelect(o.value);
                      Navigator.pop(context);
                    },
                    leading: Container(
                      width: 40,
                      alignment: Alignment.center,
                      child: Text(o.trailing,
                          style: const TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: AppColors.g700)),
                    ),
                    title: Text(o.label,
                        style: TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                            fontSize: 14.5,
                            color: AppColors.inkWarm)),
                    trailing: on
                        ? const Icon(Icons.check_circle_rounded, color: AppColors.green)
                        : null,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
