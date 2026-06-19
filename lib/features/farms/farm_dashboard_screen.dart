import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/network/dio_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/json_utils.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/farmland_background.dart';
import '../../widgets/state_views.dart';
import 'farm_bits.dart';
import 'field_management_screen.dart';
import 'crops_management_screen.dart';
import 'livestock_management_screen.dart';

const Color _heroDark = Color(0xFF22432C);

class FarmDashboardScreen extends StatefulWidget {
  final Map<String, dynamic> farm;
  const FarmDashboardScreen({super.key, required this.farm});
  @override
  State<FarmDashboardScreen> createState() => _FarmDashboardScreenState();
}

class _FarmDashboardScreenState extends State<FarmDashboardScreen> {
  final _searchCtrl = TextEditingController();
  Map<String, dynamic> _summary = {};
  List<Map<String, dynamic>> _produce = [];
  bool _loading = true;
  String? _error;
  String _query = '';
  String _src = 'all';

  static const _srcTabs = [
    ['all', 'All'],
    ['crop', 'Crops'],
    ['livestock', 'Livestock'],
  ];

  int get _id => (pickNum(widget.farm, ['id']) ?? 0).toInt();

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

  List<Map<String, dynamic>> _asList(dynamic data) {
    if (data is List) return data.whereType<Map<String, dynamic>>().toList();
    if (data is Map && data['results'] is List) {
      return (data['results'] as List).whereType<Map<String, dynamic>>().toList();
    }
    return [];
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dio = context.read<DioClient>().dio;
      final base = '${Api.farms}$_id/produce-collections/';
      final results = await Future.wait([
        dio.get('${base}summary/'),
        dio.get(base),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = (results[0].data is Map) ? Map<String, dynamic>.from(results[0].data) : {};
        _produce = _asList(results[1].data);
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
    return _produce.where((p) {
      final name = (pickString(p, ['product_name']) ?? '').toLowerCase();
      final src = (pickString(p, ['source']) ?? '').toLowerCase();
      final okQ = _query.isEmpty || name.contains(_query.toLowerCase());
      final okS = _src == 'all' || src == _src;
      return okQ && okS;
    }).toList();
  }

  Future<void> _logProduce() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _LogProduceSheet(),
    );
    if (result == null) return;
    try {
      final dio = context.read<DioClient>().dio;
      await dio.post('${Api.farms}$_id/produce-collections/', data: result);
      if (!mounted) return;
      showToast(context, 'Produce logged');
      _load();
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), success: false);
    }
  }

  void _soon(String what) => showToast(context, '$what is coming to the mobile app soon.');

  @override
  Widget build(BuildContext context) {
    final f = widget.farm;
    final name = pickString(f, ['name', 'farm_name', 'title']) ?? 'Farm';
    final type = pickString(f, ['type', 'farm_type']);
    final loc = [pickString(f, ['city']), pickString(f, ['state']), pickString(f, ['country'])]
        .where((x) => x != null && x.isNotEmpty)
        .join(', ');
    final sizeTxt = farmAreaText(f);
    final eyebrow = [
      if (type != null && type.isNotEmpty) type[0].toUpperCase() + type.substring(1),
      if (loc.isNotEmpty) loc,
      sizeTxt,
    ].where((x) => x.isNotEmpty).join('  ·  ');

    return Scaffold(
      backgroundColor: AppColors.cream,
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: 188,
              backgroundColor: _heroDark,
              foregroundColor: Colors.white,
              elevation: 0,
              systemOverlayStyle: SystemUiOverlayStyle.light,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: const EdgeInsetsDirectional.only(start: 56, bottom: 14, end: 16),
                title: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontFamily: 'Fraunces', fontWeight: FontWeight.w900, fontSize: 19, color: Colors.white)),
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    FarmlandBackground(showPins: false, child: const SizedBox.expand()),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0xCC0E2018), Color(0x800E2018)]),
                      ),
                    ),
                    Positioned(
                      left: 18,
                      right: 18,
                      bottom: 52,
                      child: SafeArea(
                        bottom: false,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (eyebrow.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                                decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(color: Colors.white.withValues(alpha: 0.2))),
                                child: Text(eyebrow,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFBBF7D0))),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(child: _statGrid()),
            SliverToBoxAdapter(child: _manageRail()),
            SliverToBoxAdapter(child: _produceHeader()),
            if (_loading)
              const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.only(top: 40), child: LoadingView()))
            else if (_error != null)
              SliverToBoxAdapter(
                  child: Padding(padding: const EdgeInsets.only(top: 30), child: ErrorView(message: _error!, onRetry: _load)))
            else if (_view.isEmpty)
              const SliverToBoxAdapter(
                  child: Padding(
                      padding: EdgeInsets.only(top: 26),
                      child: EmptyView(text: 'No produce logged yet. Tap "Log produce" to start.', icon: Icons.inventory_2_outlined)))
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _Rise(index: i, child: _ProduceCard(record: _view[i])),
                    ),
                    childCount: _view.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _statGrid() {
    final ha = farmToHa(widget.farm);
    final collections = (pickNum(_summary, ['total_collections']) ?? 0).toDouble();
    final qty = (pickNum(_summary, ['total_quantity']) ?? 0).toDouble();
    final last = pickString(_summary, ['last_collection']);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        children: [
          Row(children: [
            Expanded(child: _StatCard(icon: Icons.inventory_2_rounded, value: collections, label: 'Collections', c1: const Color(0xFF10B981), c2: const Color(0xFF047857))),
            const SizedBox(width: 10),
            Expanded(child: _StatCard(icon: Icons.scale_rounded, value: qty, label: 'Total units', c1: const Color(0xFF0D9488), c2: const Color(0xFF0F766E))),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _StatCard(icon: Icons.event_available_rounded, text: (last == null || last.isEmpty) ? '—' : last, label: 'Last collection', c1: const Color(0xFFC39A48), c2: const Color(0xFFA9772E))),
            const SizedBox(width: 10),
            Expanded(child: _StatCard(icon: Icons.straighten_rounded, value: ha, decimals: ha > 0 && ha < 100 ? 1 : 0, suffix: ' ha', label: 'Land area', c1: const Color(0xFF7C8C42), c2: const Color(0xFF5C6B1F))),
          ]),
        ],
      ),
    );
  }

  Widget _manageRail() {
    final tiles = [
      [Icons.agriculture_rounded, 'Land Management', 'Fields, plots & assets', const Color(0xFF3F7A31)],
      [Icons.pets_rounded, 'Livestock', 'Animals & herds', const Color(0xFFC39A48)],
      [Icons.eco_rounded, 'Crops', 'Cycles, yields & health', const Color(0xFF6AA83A)],
      [Icons.payments_rounded, 'Expenses', 'Costs & spending', const Color(0xFF0D9488)],
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Manage this farm',
              style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.inkWarm)),
          const SizedBox(height: 10),
          ...tiles.map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ManageTile(
                  icon: t[0] as IconData,
                  title: t[1] as String,
                  sub: t[2] as String,
                  color: t[3] as Color,
                  onTap: () {
                    final f = widget.farm;
                    Widget? dest;
                    switch (t[1]) {
                      case 'Land Management':
                        dest = FieldManagementScreen(farm: f);
                        break;
                      case 'Crops':
                        dest = CropsManagementScreen(farm: f);
                        break;
                      case 'Livestock':
                        dest = LivestockManagementScreen(farm: f);
                        break;
                    }
                    if (dest != null) {
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => dest!));
                    } else {
                      _soon(t[1] as String);
                    }
                  },
                ),
              )),
        ],
      ),
    );
  }

  Widget _produceHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Produce history',
                    style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.inkWarm)),
              ),
              GestureDetector(
                onTap: _logProduce,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(gradient: AppColors.emeraldGrad, borderRadius: BorderRadius.circular(12)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.add_rounded, color: Colors.white, size: 16),
                    SizedBox(width: 5),
                    Text('Log produce', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 12.5, color: Colors.white)),
                  ]),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 44,
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                hintText: 'Search produce…',
                prefixIcon: const Icon(Icons.search, size: 20),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: const BorderSide(color: AppColors.line)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: const BorderSide(color: AppColors.line)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: const BorderSide(color: AppColors.green)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: _srcTabs.map((t) {
                final on = t[0] == _src;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _src = t[0]),
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
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
class _StatCard extends StatelessWidget {
  final IconData icon;
  final double? value;
  final String? text;
  final String label;
  final int decimals;
  final String suffix;
  final Color c1, c2;
  const _StatCard(
      {required this.icon,
      this.value,
      this.text,
      required this.label,
      this.decimals = 0,
      this.suffix = '',
      required this.c1,
      required this.c2});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.line),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 18, offset: const Offset(0, 8))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                gradient: LinearGradient(colors: [c1, c2], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(11)),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(height: 10),
          if (text != null)
            Text(text!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.inkWarm))
          else
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: value ?? 0),
              duration: const Duration(milliseconds: 850),
              curve: Curves.easeOutCubic,
              builder: (_, v, __) => Text(
                (decimals > 0 ? v.toStringAsFixed(decimals) : v.round().toString()) + suffix,
                style: const TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w900, fontSize: 22, color: AppColors.inkWarm),
              ),
            ),
          const SizedBox(height: 2),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.slate500)),
        ],
      ),
    );
  }
}

class _ManageTile extends StatelessWidget {
  final IconData icon;
  final String title, sub;
  final Color color;
  final VoidCallback onTap;
  const _ManageTile({required this.icon, required this.title, required this.sub, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(13)),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.inkWarm)),
                    const SizedBox(height: 1),
                    Text(sub, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppColors.slate500)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.slate500),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProduceCard extends StatelessWidget {
  final Map<String, dynamic> record;
  const _ProduceCard({required this.record});

  @override
  Widget build(BuildContext context) {
    final p = record;
    final src = (pickString(p, ['source']) ?? '').toLowerCase();
    final isCrop = src == 'crop';
    final name = pickString(p, ['product_name']) ?? 'Produce';
    final qty = pickNum(p, ['quantity']);
    final unit = pickString(p, ['unit']) ?? '';
    final date = pickString(p, ['collection_date']) ?? '';
    final linked = (p['linked_products'] is List) ? (p['linked_products'] as List) : const [];

    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.line),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 14, offset: const Offset(0, 6))]),
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                    color: isCrop ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(999)),
                child: Text(isCrop ? 'Crops' : (src == 'livestock' ? 'Livestock' : (pickString(p, ['source_display']) ?? '—')),
                    style: TextStyle(
                        fontFamily: 'Inter', fontSize: 9.5, fontWeight: FontWeight.w800, color: isCrop ? const Color(0xFF166534) : const Color(0xFF92400E))),
              ),
              const Spacer(),
              Text(date, style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppColors.slate500)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.inkWarm)),
              ),
              Text('${qty == null ? '—' : (qty % 1 == 0 ? qty.toInt().toString() : qty.toString())} $unit',
                  style: const TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w900, fontSize: 15, color: AppColors.g600)),
            ],
          ),
          if (linked.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: linked.map<Widget>((lp) {
                final m = (lp is Map) ? lp : const {};
                final store = (m['store_name'] ?? m['store'] ?? 'store').toString();
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: const Color(0xFFEAF7EC), borderRadius: BorderRadius.circular(999), border: Border.all(color: const Color(0xFFBFE3CD))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.storefront_rounded, size: 11, color: Color(0xFF0F7A4B)),
                    const SizedBox(width: 4),
                    Text(store, style: const TextStyle(fontFamily: 'Inter', fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF0F7A4B))),
                  ]),
                );
              }).toList(),
            ),
          ],
        ],
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

// ---------------------------------------------------------------------------
class _LogProduceSheet extends StatefulWidget {
  const _LogProduceSheet();
  @override
  State<_LogProduceSheet> createState() => _LogProduceSheetState();
}

class _LogProduceSheetState extends State<_LogProduceSheet> {
  final _name = TextEditingController();
  final _qty = TextEditingController();
  final _notes = TextEditingController();
  String _source = '';
  String _unit = '';
  String? _err;

  static const _units = ['kg', 'liters', 'crates', 'bags', 'tons', 'pieces'];

  @override
  void dispose() {
    _name.dispose();
    _qty.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    final qty = double.tryParse(_qty.text.trim());
    if (_source.isEmpty || name.isEmpty || qty == null || _unit.isEmpty) {
      setState(() => _err = 'Fill source, product, quantity and unit.');
      return;
    }
    final today = DateTime.now().toIso8601String().split('T').first;
    Navigator.pop(context, {
      'source': _source,
      'product_name': name,
      'quantity': qty,
      'unit': _unit,
      'collection_date': today,
      if (_notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: const BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 42, height: 4, decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(99)))),
            const SizedBox(height: 14),
            const Text('Log produce collection',
                style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 19, color: AppColors.inkWarm)),
            const SizedBox(height: 14),
            if (_err != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFFCA5A5))),
                child: Text(_err!, style: const TextStyle(fontFamily: 'Inter', fontSize: 12.5, color: Color(0xFFDC2626))),
              ),
              const SizedBox(height: 12),
            ],
            Row(children: [
              Expanded(child: _seg('crop', 'Crop harvest')),
              const SizedBox(width: 10),
              Expanded(child: _seg('animal', 'Animal product')),
            ]),
            const SizedBox(height: 12),
            _field(_name, 'Product name'),
            const SizedBox(height: 10),
            _field(_qty, 'Quantity', number: true),
            const SizedBox(height: 10),
            _unitChips(),
            const SizedBox(height: 10),
            _field(_notes, 'Notes (optional)', lines: 2),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: _submit,
              child: Container(
                height: 50,
                alignment: Alignment.center,
                decoration: BoxDecoration(gradient: AppColors.emeraldGrad, borderRadius: BorderRadius.circular(13)),
                child: const Text('Save collection',
                    style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, color: Colors.white, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _seg(String value, String label) {
    final on = _source == value;
    return GestureDetector(
      onTap: () => setState(() => _source = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? const Color(0xFFEAF7EC) : Colors.white,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: on ? AppColors.g600 : AppColors.line, width: on ? 1.5 : 1),
        ),
        child: Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 12.5, color: on ? AppColors.g700 : AppColors.slate600)),
      ),
    );
  }

  Widget _field(TextEditingController c, String hint, {bool number = false, int lines = 1}) {
    return TextField(
      controller: c,
      maxLines: lines,
      keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: AppColors.line)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: AppColors.line)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: AppColors.green)),
      ),
    );
  }

  Widget _unitChips() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 2, bottom: 6),
          child: Text('Unit',
              style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 12.5, color: AppColors.slate700)),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _units.map((u) {
            final on = _unit == u;
            return GestureDetector(
              onTap: () => setState(() => _unit = u),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: on ? AppColors.g600 : Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: on ? AppColors.g600 : AppColors.line),
                ),
                child: Text(u,
                    style: TextStyle(
                        fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 12.5, color: on ? Colors.white : AppColors.slate700)),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
