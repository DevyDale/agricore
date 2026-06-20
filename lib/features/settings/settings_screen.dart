import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_controller.dart';
import '../../core/i18n/app_translations.dart';
import '../../core/i18n/locale_provider.dart';
import '../../core/network/dio_client.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/app_toast.dart';
import '../../core/responsive/responsive.dart';
import '../wallet/wallet_screen.dart';
import 'info_screens.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _kPush = 'notif_push';
  static const _kEmail = 'notif_email';
  static const _kOrders = 'notif_orders';

  bool _push = true;
  bool _email = false;
  bool _orderUpdates = true;

  @override
  void initState() {
    super.initState();
    _loadNotificationPrefs();
  }

  Future<void> _loadNotificationPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _push = prefs.getBool(_kPush) ?? true;
      _email = prefs.getBool(_kEmail) ?? false;
      _orderUpdates = prefs.getBool(_kOrders) ?? true;
    });
  }

  Future<void> _setNotifPref(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  @override
  Widget build(BuildContext context) {
    final u = context.watch<AuthProvider>().user;
    final loc = context.watch<LocaleProvider>();
    final langName =
        kLanguages.firstWhere((l) => l.code == loc.language, orElse: () => kLanguages.first).name;
    final curr = currencyFor(loc.currency);
    return Scaffold(
      backgroundColor: context.palette.surface,
      appBar: AppBar(
        backgroundColor: context.palette.surface,
        foregroundColor: context.palette.ink,
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
                color: context.palette.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: context.palette.line)),
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
                          style: TextStyle(
                              fontFamily: 'Fraunces',
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                              color: context.palette.ink)),
                      const SizedBox(height: 2),
                      Text(u?.email ?? u?.roleLabel ?? 'Agricore member',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: context.palette.muted)),
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
                'Alerts on this device', _push, (v) {
              setState(() => _push = v);
              _setNotifPref(_kPush, v);
            }),
            _divider(),
            _switchTile(Icons.mark_email_unread_rounded, 'gold', 'Email updates',
                'News and offers by email', _email, (v) {
              setState(() => _email = v);
              _setNotifPref(_kEmail, v);
            }),
            _divider(),
            _switchTile(Icons.local_shipping_rounded, 'sky', 'Order updates',
                'Escrow and delivery status', _orderUpdates, (v) {
              setState(() => _orderUpdates = v);
              _setNotifPref(_kOrders, v);
            }),
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
            _navTile(Icons.dark_mode_rounded, 'plum', 'Appearance',
                context.watch<ThemeController>().label,
                onTap: _pickAppearance),
          ]),
          const SizedBox(height: 22),

          _sectionLabel('Account & security'),
          _group([
            _navTile(Icons.lock_rounded, 'green', 'Password', 'Change your password',
                onTap: _changePassword),
            _divider(),
            _navTile(Icons.shield_rounded, 'gold', 'Privacy', 'Data and permissions',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute<void>(builder: (_) => const PrivacyScreen()))),
            _divider(),
            _navTile(Icons.account_balance_wallet_rounded, 'sky', 'Payout details',
                'Balance, payouts & activity',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute<void>(builder: (_) => const WalletScreen()))),
          ]),
          const SizedBox(height: 22),

          _sectionLabel('About'),
          _group([
            _navTile(Icons.help_outline_rounded, 'sky', 'Help center', 'Guides and support',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute<void>(builder: (_) => const HelpCenterScreen()))),
            _divider(),
            _navTile(Icons.description_rounded, 'gold', 'Terms & policies', 'Legal and privacy',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute<void>(builder: (_) => const TermsScreen()))),
            _divider(),
            _navTile(Icons.info_outline_rounded, 'green', 'About Agricore', 'Version 1.0.0',
                onTap: _showAbout),
          ]),
          const SizedBox(height: 24),

          GestureDetector(
            onTap: () => context.read<AuthProvider>().logout(),
            child: Container(
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: context.palette.card,
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
          Center(
            child: Text('Powered by LUMORA',
                style: TextStyle(
                    fontFamily: 'Inter', fontSize: 11.5, letterSpacing: 1.2, color: context.palette.muted)),
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

  Future<void> _pickAppearance() async {
    final theme = context.read<ThemeController>();
    final current = theme.mode == ThemeMode.dark
        ? 'dark'
        : theme.mode == ThemeMode.system
            ? 'system'
            : 'light';
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ChoiceSheet(
        title: 'Appearance',
        options: const [
          (value: 'light', label: 'Light', trailing: '☀'),
          (value: 'dark', label: 'Dark', trailing: '☾'),
          (value: 'system', label: 'System default', trailing: '⚙'),
        ],
        selected: current,
        onSelect: (v) => theme.setMode(switch (v) {
          'dark' => ThemeMode.dark,
          'system' => ThemeMode.system,
          _ => ThemeMode.light,
        }),
      ),
    );
  }

  Future<void> _changePassword() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ChangePasswordSheet(),
    );
  }

  void _showAbout() {
    showAboutDialog(
      context: context,
      applicationName: 'AgriCore',
      applicationVersion: '1.0.0',
      applicationIcon: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
            shape: BoxShape.circle, gradient: AppColors.emeraldGrad),
        child: const Icon(Icons.eco_rounded, color: Colors.white),
      ),
      children: const [
        SizedBox(height: 8),
        Text(
          'AgriCore connects farmers, buyers and transporters with secure escrow '
          'trade, farm management and digital storefronts.',
          style: TextStyle(fontFamily: 'Inter', fontSize: 13, height: 1.5),
        ),
      ],
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
            color: context.palette.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: context.palette.line)),
        child: Column(children: children),
      );

  Widget _divider() => Divider(height: 1, indent: 60, color: context.palette.line);

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
                    style: TextStyle(
                        fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 14.5, color: context.palette.ink)),
                Text(sub,
                    style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: context.palette.muted)),
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
                      style: TextStyle(
                          fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 14.5, color: context.palette.ink)),
                  Text(sub,
                      style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: context.palette.muted)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: context.palette.muted),
          ],
        ),
      ),
    );
  }
}

class _ChangePasswordSheet extends StatefulWidget {
  const _ChangePasswordSheet();
  @override
  State<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<_ChangePasswordSheet> {
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final current = _current.text.trim();
    final next = _new.text;
    final confirm = _confirm.text;
    if (current.isEmpty || next.isEmpty) {
      showToast(context, 'Please fill in all fields.');
      return;
    }
    if (next.length < 8) {
      showToast(context, 'New password must be at least 8 characters.');
      return;
    }
    if (next != confirm) {
      showToast(context, 'New password and confirmation do not match.');
      return;
    }
    setState(() => _busy = true);
    try {
      final dio = context.read<DioClient>().dio;
      final res = await dio.post<dynamic>(
        '/users/change-password/',
        data: {'current_password': current, 'new_password': next},
      );
      final detail = (res.data is Map)
          ? (res.data['detail']?.toString() ?? 'Password updated successfully.')
          : 'Password updated successfully.';
      if (!mounted) return;
      Navigator.pop(context);
      showToast(context, detail, success: true);
    } on DioException catch (e) {
      final data = e.response?.data;
      final detail = (data is Map && data['detail'] != null)
          ? data['detail'].toString()
          : 'Could not change password. Please try again.';
      if (!mounted) return;
      showToast(context, detail);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
            color: context.palette.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
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
                          color: context.palette.line,
                          borderRadius: BorderRadius.circular(99)))),
              const SizedBox(height: 14),
              Text('Change password',
                  style: TextStyle(
                      fontFamily: 'Fraunces',
                      fontWeight: FontWeight.w800,
                      fontSize: 19,
                      color: context.palette.ink)),
              const SizedBox(height: 16),
              _field(_current, 'Current password'),
              const SizedBox(height: 12),
              _field(_new, 'New password'),
              const SizedBox(height: 12),
              _field(_confirm, 'Confirm new password'),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.green,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14))),
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Update password',
                          style: TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w700,
                              color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String hint) => TextField(
        controller: c,
        obscureText: true,
        enableSuggestions: false,
        autocorrect: false,
        decoration: InputDecoration(hintText: hint),
      );
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
      decoration: BoxDecoration(
          color: context.palette.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
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
                        color: context.palette.line, borderRadius: BorderRadius.circular(99)))),
            const SizedBox(height: 14),
            Text(title,
                style: TextStyle(
                    fontFamily: 'Fraunces',
                    fontWeight: FontWeight.w800,
                    fontSize: 19,
                    color: context.palette.ink)),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: options.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: context.palette.line),
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
                            color: context.palette.ink)),
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
