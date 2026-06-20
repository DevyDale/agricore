import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/i18n/locale_provider.dart';
import '../../providers/auth_provider.dart';
import '../marketplace/marketplace_screen.dart';
import '../farms/farms_screen.dart';
import '../stores/stores_screen.dart';
import '../chats/conversations_screen.dart';
import '../workforce/workforce_screen.dart';
import '../profile/profile_screen.dart';
import '../wallet/wallet_screen.dart';
import '../dale_ai/dale_chat.dart';
import '../dale_ai/dale_models.dart';
import '../../widgets/animated_bottom_nav.dart';

class _Section {
  final String label;
  final IconData icon;
  const _Section(this.label, this.icon);
}

class DashboardShell extends StatefulWidget {
  const DashboardShell({super.key});
  @override
  State<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends State<DashboardShell> {
  int _index = 0;

  // Web-style page keys Dale uses to tailor its answers per section.
  static const _pageKeys = [
    'marketplace',
    'farms',
    'digital_store',
    'chats',
    'workforce',
    'wallet',
    'profile',
  ];

  String _pageKeyAt(int i) => (i >= 0 && i < _pageKeys.length) ? _pageKeys[i] : 'dashboard';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final dale = context.read<DaleController>();
      dale.onSelectTab = (i) {
        if (mounted) setState(() => _index = i);
      };
      dale.setPage(_pageKeyAt(_index));
    });
  }

  // First 4 also appear in the phone bottom bar. Dale is the floating orb.
  static const _sections = <_Section>[
    _Section('Market', Icons.storefront_rounded),
    _Section('Farms', Icons.agriculture_rounded),
    _Section('Stores', Icons.store_rounded),
    _Section('Chats', Icons.chat_bubble_rounded),
    _Section('Workforce', Icons.work_rounded),
    _Section('Wallet', Icons.account_balance_wallet_rounded),
    _Section('Profile', Icons.person_rounded),
  ];

  static const _profileIndex = 6;

  void _go(int i) {
    setState(() => _index = i);
    Navigator.of(context).maybePop();
  }

  Widget _pageAt(int i) {
    switch (i) {
      case 0:
        return const MarketplaceScreen();
      case 1:
        return const FarmsScreen();
      case 2:
        return const StoresScreen();
      case 3:
        return const ConversationsScreen();
      case 4:
        return const WorkforceScreen();
      case 5:
        return const WalletScreen();
      case 6:
        return const ProfileScreen();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _pageStack() => IndexedStack(
        index: _index,
        sizing: StackFit.expand,
        children: List.generate(_sections.length, _pageAt),
      );

  @override
  Widget build(BuildContext context) {
    final wide = Responsive.isWide(context);
    final auth = context.watch<AuthProvider>();
    context.read<DaleController>().setPage(_pageKeyAt(_index));

    return Scaffold(
      appBar: _index <= 3 ? null : AppBar(
        title: Text(context.tr(_sections[_index].label)),
        actions: [
          IconButton(
            tooltip: 'Profile',
            onPressed: () => setState(() => _index = _profileIndex),
            icon: CircleAvatar(
              radius: 15,
              backgroundColor: AppColors.green,
              child: Text(auth.user?.initials ?? '?',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: wide ? null : _Drawer(sections: _sections, current: _index, onTap: _go),
      floatingActionButton: const DaleOrb(),
      body: wide
          ? Row(
              children: [
                NavigationRail(
                  extended: MediaQuery.sizeOf(context).width >= 1024,
                  selectedIndex: _index,
                  onDestinationSelected: (i) => setState(() => _index = i),
                  labelType: MediaQuery.sizeOf(context).width >= 1024
                      ? NavigationRailLabelType.none
                      : NavigationRailLabelType.all,
                  destinations: _sections
                      .map((s) => NavigationRailDestination(
                          icon: Icon(s.icon), label: Text(context.tr(s.label))))
                      .toList(),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: _pageStack()),
              ],
            )
          : _pageStack(),
      bottomNavigationBar: wide
          ? null
          : AnimatedBottomNav(
              items: _sections
                  .take(4)
                  .map((s) => AnimatedNavItem(s.icon, context.tr(s.label)))
                  .toList(),
              index: _index < 4 ? _index : 0,
              onTap: (i) => setState(() => _index = i),
            ),
    );
  }
}

class _Drawer extends StatelessWidget {
  final List<_Section> sections;
  final int current;
  final void Function(int) onTap;
  const _Drawer({required this.sections, required this.current, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Drawer(
      backgroundColor: AppColors.cream,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: const BoxDecoration(gradient: AppColors.emeraldGrad),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: Colors.white,
                    child: Text(auth.user?.initials ?? '?',
                        style: const TextStyle(
                            color: AppColors.g700, fontWeight: FontWeight.bold, fontSize: 20)),
                  ),
                  const SizedBox(height: 12),
                  Text(auth.user?.username ?? 'Welcome',
                      style: const TextStyle(
                          fontFamily: 'Fraunces',
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700)),
                  Text(auth.user?.roleLabel ?? '',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  for (var i = 0; i < sections.length; i++)
                    ListTile(
                      leading: Icon(sections[i].icon,
                          color: current == i ? AppColors.g700 : AppColors.slate500),
                      title: Text(context.tr(sections[i].label),
                          style: TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: current == i ? FontWeight.w700 : FontWeight.w500,
                              color: current == i ? AppColors.g700 : AppColors.inkWarm)),
                      selected: current == i,
                      selectedTileColor: const Color(0xFFE7F4EC),
                      onTap: () => onTap(i),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout_rounded, color: Colors.redAccent),
              title: Text(context.tr('Log out'), style: const TextStyle(fontFamily: 'Inter')),
              onTap: () => context.read<AuthProvider>().logout(),
            ),
          ],
        ),
      ),
    );
  }
}
