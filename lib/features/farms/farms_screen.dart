import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/network/api_service.dart';
import '../../core/network/dio_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/json_utils.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/farmland_background.dart';
import '../../widgets/state_views.dart';
import 'farm_bits.dart';
import 'farm_dashboard_screen.dart';
import 'farm_form_sheet.dart';
import '../settings/settings_screen.dart';

const Color _heroDark = Color(0xFF22432C);

class FarmsScreen extends StatefulWidget {
  const FarmsScreen({super.key});
  @override
  State<FarmsScreen> createState() => _FarmsScreenState();
}

class _FarmsScreenState extends State<FarmsScreen> {
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _all = [];
  bool _loading = true;
  String? _error;
  String _query = '';
  String _type = 'all';

  static const _types = [
    ['all', 'All'],
    ['crops', 'Crops'],
    ['livestock', 'Livestock'],
    ['mixed', 'Mixed'],
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ApiService(context.read<DioClient>().dio);
      final data = await api.list(Api.farms);
      if (!mounted) return;
      setState(() {
        _all = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _view {
    return _all.where((f) {
      final hay = [
        pickString(f, ['name', 'farm_name', 'title']),
        pickString(f, ['city']),
        pickString(f, ['state', 'province']),
        pickString(f, ['country']),
      ].whereType<String>().join(' ').toLowerCase();
      final okQ = _query.isEmpty || hay.contains(_query.toLowerCase());
      final okT = _type == 'all' || farmTypeKey(pickString(f, ['type', 'farm_type'])) == _type;
      return okQ && okT;
    }).toList();
  }

  double get _totalHa => _all.fold(0.0, (s, f) => s + farmToHa(f));
  int get _activeTypes => _all.map((f) => farmTypeKey(pickString(f, ['type', 'farm_type']))).toSet().length;

  Future<void> _openForm({Map<String, dynamic>? farm}) async {
    final saved = await showFarmForm(context, farm: farm);
    if (saved == true) _load();
  }

  Future<void> _openDetail(Map<String, dynamic> farm) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => FarmDashboardScreen(farm: farm)),
    );
    if (!mounted) return;
    _load();
  }

  Future<void> _confirmDelete(Map<String, dynamic> farm) async {
    final name = pickString(farm, ['name', 'farm_name', 'title']) ?? 'this farm';
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete farm?'),
        content: Text('Delete "$name"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: Color(0xFFDC2626)))),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;
    try {
      await context.read<DioClient>().dio.delete('${Api.farms}${farm['id']}/');
      if (!mounted) return;
      showToast(context, 'Farm deleted');
      _load();
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = context.watch<AuthProvider>().user?.username ?? 'farmer';
    final view = _view;

    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: 190,
              toolbarHeight: 56,
              backgroundColor: _heroDark,
              foregroundColor: Colors.white,
              elevation: 0,
              automaticallyImplyLeading: false,
              systemOverlayStyle: SystemUiOverlayStyle.light,
              leading: IconButton(
                tooltip: 'Settings',
                icon: const Icon(Icons.settings_rounded, color: Colors.white),
                onPressed: _openSettings,
              ),
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    FarmlandBackground(showPins: false, child: const SizedBox.expand()),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                            begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xCC0E2018), Color(0x800E2018)]),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 56, bottom: 56),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text.rich(
                              const TextSpan(
                                style: TextStyle(
                                    fontFamily: 'Fraunces', fontWeight: FontWeight.w900, fontSize: 28, height: 1.05, color: Colors.white),
                                children: [
                                  TextSpan(text: 'Your '),
                                  TextSpan(
                                      text: 'Farms',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w600, fontStyle: FontStyle.italic, color: AppColors.gold)),
                                ],
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 4),
                            Text('Welcome back, $name',
                                style: TextStyle(
                                    fontFamily: 'Inter', fontSize: 12.5, letterSpacing: 0.3, color: Colors.white.withValues(alpha: 0.9))),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              bottom: PreferredSize(preferredSize: const Size.fromHeight(56), child: _searchRow()),
            ),
            SliverToBoxAdapter(child: _metrics()),
            if (_loading)
              const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.only(top: 50), child: LoadingView()))
            else if (_error != null)
              SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.only(top: 40), child: ErrorView(message: _error!, onRetry: _load)))
            else if (_all.isEmpty)
              const SliverToBoxAdapter(
                  child: Padding(
                      padding: EdgeInsets.only(top: 30),
                      child: EmptyView(text: 'No farms yet. Tap "Add farm" to create your first one.', icon: Icons.agriculture_outlined)))
            else ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                  child: Text('Showing ${view.length} of ${_all.length} farm${_all.length == 1 ? '' : 's'}',
                      style: const TextStyle(fontFamily: 'Inter', fontSize: 12.5, color: AppColors.slate500)),
                ),
              ),
              SliverToBoxAdapter(child: _chipsRow()),
              if (view.isEmpty)
                const SliverToBoxAdapter(
                    child: Padding(
                        padding: EdgeInsets.only(top: 30),
                        child: EmptyView(text: 'No farms match your search.', icon: Icons.search_off_rounded)))
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 96),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: _Rise(
                          index: i,
                          child: _FarmCard(
                            farm: view[i],
                            totalHa: _totalHa,
                            onManage: () => _openDetail(view[i]),
                            onEdit: () => _openForm(farm: view[i]),
                            onDelete: () => _confirmDelete(view[i]),
                          ),
                        ),
                      ),
                      childCount: view.length,
                    ),
                  ),
                ),
            ],
          ],
        ),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  // ---- + Add (leading) + search, inside the dark bar ----
  Widget _searchRow() {
    return Container(
      color: _heroDark,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _openForm(),
            child: Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
              ),
              child: const Icon(Icons.add_rounded, color: Colors.white, size: 22),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 46,
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white,
                  hintText: 'Search farms by name or place…',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          }),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: BorderSide.none),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: BorderSide.none),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- type chips, now just BELOW the "Showing X of Y" count line ----
  Widget _chipsRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 0, 6),
      child: SizedBox(
        height: 36,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: _types.map((t) {
            final on = t[0] == _type;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _type = t[0]),
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: on ? AppColors.g600 : Colors.white,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: on ? AppColors.g600 : AppColors.line),
                  ),
                  child: Text(t[1],
                      style: TextStyle(
                          fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13, color: on ? Colors.white : AppColors.slate700)),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _metrics() {
    final m = [
      [Icons.agriculture_rounded, _all.length.toDouble(), 'Total farms', const Color(0xFF10B981), const Color(0xFF047857), 0],
      [Icons.straighten_rounded, _totalHa, 'Total land (ha)', const Color(0xFFC39A48), const Color(0xFFA9772E), (_totalHa > 0 && _totalHa < 100) ? 1 : 0],
      [Icons.eco_rounded, _activeTypes.toDouble(), 'Active types', const Color(0xFF7C8C42), const Color(0xFF5C6B1F), 0],
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 2),
      child: Row(
        children: m
            .map((e) => Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: e == m.last ? 0 : 10),
                    child: _MetricCard(
                      icon: e[0] as IconData,
                      value: e[1] as double,
                      label: e[2] as String,
                      c1: e[3] as Color,
                      c2: e[4] as Color,
                      decimals: e[5] as int,
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final double value;
  final String label;
  final Color c1, c2;
  final int decimals;
  const _MetricCard(
      {required this.icon, required this.value, required this.label, required this.c1, required this.c2, required this.decimals});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                gradient: LinearGradient(colors: [c1, c2], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(11)),
            child: Icon(icon, color: Colors.white, size: 17),
          ),
          const SizedBox(height: 8),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value),
            duration: const Duration(milliseconds: 850),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => Text(
              decimals > 0 ? v.toStringAsFixed(decimals) : v.round().toString(),
              style: const TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w900, fontSize: 21, color: AppColors.inkWarm),
            ),
          ),
          Text(label,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'Inter', fontSize: 10.5, fontWeight: FontWeight.w600, color: AppColors.slate500)),
        ],
      ),
    );
  }
}

class _FarmCard extends StatelessWidget {
  final Map<String, dynamic> farm;
  final double totalHa;
  final VoidCallback onManage, onEdit, onDelete;
  const _FarmCard({required this.farm, required this.totalHa, required this.onManage, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final key = farmTypeKey(pickString(farm, ['type', 'farm_type']));
    final name = pickString(farm, ['name', 'farm_name', 'title']) ?? 'Untitled';
    final loc = [pickString(farm, ['city']), pickString(farm, ['country'])].where((x) => x != null && x.isNotEmpty).join(', ');
    final ha = farmToHa(farm);
    final share = totalHa > 0 ? ha / totalHa : 0.0;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onManage,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.line)),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                    child: FarmBanner(typeKey: key),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.inkWarm)),
                        const SizedBox(height: 3),
                        Row(children: [
                          const Icon(Icons.location_on_rounded, size: 13, color: AppColors.g600),
                          const SizedBox(width: 4),
                          Expanded(
                              child: Text(loc.isEmpty ? 'Location not set' : loc,
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppColors.slate500))),
                        ]),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(child: _stat(Icons.straighten_rounded, 'Area', farmAreaText(farm))),
                          const SizedBox(width: 10),
                          Expanded(child: _stat(Icons.pie_chart_rounded, 'Share', totalHa > 0 ? '${(share * 100).round()}%' : '—')),
                        ]),
                        const SizedBox(height: 12),
                        ShareBar(pct: share, typeKey: key),
                        const SizedBox(height: 6),
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          const Text('Share of your land',
                              style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppColors.slate500)),
                          Text(farmAreaText(farm),
                              style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppColors.slate500)),
                        ]),
                        const SizedBox(height: 14),
                        Row(children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: onManage,
                              child: Container(
                                height: 40,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(gradient: AppColors.emeraldGrad, borderRadius: BorderRadius.circular(12)),
                                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                  Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 16),
                                  SizedBox(width: 6),
                                  Text('Manage',
                                      style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 13.5, color: Colors.white)),
                                ]),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _iconBtn(Icons.edit_rounded, onEdit),
                          const SizedBox(width: 8),
                          _iconBtn(Icons.delete_outline_rounded, onDelete, danger: true),
                        ]),
                      ],
                    ),
                  ),
                ],
              ),
              Positioned(right: 14, top: 88 - 22, child: FarmEmblem(typeKey: key)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(IconData icon, String k, String v) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: const Color(0xFFFAF7EF), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 11, color: AppColors.slate500),
            const SizedBox(width: 4),
            Text(k.toUpperCase(),
                style: const TextStyle(fontFamily: 'Inter', fontSize: 8.5, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: AppColors.slate500)),
          ]),
          const SizedBox(height: 3),
          Text(v, style: const TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.inkWarm)),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap, {bool danger = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: danger ? const Color(0xFFFEF2F2) : const Color(0xFFFAF7EF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: danger ? const Color(0xFFFCA5A5) : AppColors.line)),
        child: Icon(icon, size: 17, color: danger ? const Color(0xFFDC2626) : AppColors.slate600),
      ),
    );
  }
}

class _Rise extends StatefulWidget {
  final int index;
  final Widget child;
  const _Rise({required this.index, required this.child});
  @override
  State<_Rise> createState() => _RiseState();
}

class _RiseState extends State<_Rise> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  late final Animation<double> _a = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: (widget.index.clamp(0, 8)) * 55), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _a,
      builder: (_, child) => Opacity(
        opacity: _a.value,
        child: Transform.translate(offset: Offset(0, (1 - _a.value) * 14), child: child),
      ),
      child: widget.child,
    );
  }
}