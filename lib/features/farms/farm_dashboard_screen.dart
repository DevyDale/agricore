import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/network/dio_client.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/json_utils.dart';
import '../../core/utils/log.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/farmland_background.dart';
import '../../widgets/state_views.dart';
import 'farm_bits.dart';
import 'field_management_screen.dart';
import 'crops_management_screen.dart';
import 'livestock_management_screen.dart';
import 'expenses_management_screen.dart';
import '../stores/store_detail_sheet.dart';

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
    if (!mounted) return;
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

  Future<void> _openTransfer(Map<String, dynamic> record) async {
    final r = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TransferSheet(record: record, farmId: _id),
    );
    if (r == null) return;
    if (!mounted) return;
    try {
      final dio = context.read<DioClient>().dio;
      final payload = <String, dynamic>{
        'store': r['store'],
        'title': r['title'],
        'description': r['description'],
        'category': 'Produce',
        'price': r['price'],
        'stock_quantity': r['quantity'],
        'unit': r['unit'],
        'source_produce': r['produce_id'],
        'is_dropshippable': r['dropship'],
      };
      if (r['expiration'] != null) payload['expiration_date'] = r['expiration'];
      await dio.post(Api.products, data: payload);
      try {
        await dio.patch('${Api.stores}${r['store']}/', data: {'farm': _id});
      } catch (e) {
        logSwallowed('FarmDashboard.linkStoreToFarm', e);
      }
      await _reduceProduce(dio, r['produce_id'], (r['available'] as double) - (r['quantity'] as double));
      if (!mounted) return;
      showToast(context, 'Produce transferred');
      _load();
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), success: false);
    }
  }

  Future<void> _openLink(Map<String, dynamic> record) async {
    final r = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LinkSheet(record: record),
    );
    if (r == null) return;
    if (!mounted) return;
    try {
      final dio = context.read<DioClient>().dio;
      final qty = r['quantity'] as double;
      final payload = <String, dynamic>{
        'store': r['store'],
        'title': r['title'],
        'description': r['description'],
        'category': r['category'],
        'price': r['price'],
        'stock_quantity': qty > 0 ? qty : 0,
        'unit': r['unit'],
        'source_produce': r['produce_id'],
        'expiration_date': r['expiration'],
        'is_dropshippable': r['dropship'],
      };
      await dio.post(Api.products, data: payload);
      try {
        await dio.patch('${Api.stores}${r['store']}/', data: {'farm': _id});
      } catch (e) {
        logSwallowed('FarmDashboard.linkStoreToFarm', e);
      }
      if (r['reduce'] == true && qty > 0) {
        await _reduceProduce(dio, r['produce_id'], (r['available'] as double) - qty);
      }
      if (!mounted) return;
      showToast(context, 'Produce linked');
      _load();
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), success: false);
    }
  }

  Future<void> _reduceProduce(dynamic dio, dynamic produceId, double newQty) async {
    final base = '${Api.farms}$_id/produce-collections/$produceId/';
    if (newQty <= 0) {
      await dio.delete(base);
    } else {
      await dio.patch(base, data: {'quantity': newQty});
    }
  }

  Future<void> _openLinkedStores() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LinkedStoresSheet(farmId: _id),
    );
  }

  Future<void> _openConnectStore() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ConnectStoreSheet(farmId: _id),
    );
    if (ok == true && mounted) showToast(context, 'Store linked to this farm');
  }

  Widget _storeActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Row(children: [
        Expanded(child: _storeActionBtn(Icons.storefront_rounded, 'Linked stores', _openLinkedStores)),
        const SizedBox(width: 10),
        Expanded(child: _storeActionBtn(Icons.add_business_rounded, 'Link a store', _openConnectStore)),
      ]),
    );
  }

  Widget _storeActionBtn(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: context.palette.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: context.palette.line)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 17, color: AppColors.g700),
          const SizedBox(width: 7),
          Text(label, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 13, color: context.palette.ink)),
        ]),
      ),
    );
  }

  void _soon(String what) => showToast(context, '$what is coming to the mobile app soon.');

  void _openManage(String key) {
    final f = widget.farm;
    Widget? dest;
    switch (key) {
      case 'land':
        dest = FieldManagementScreen(farm: f);
        break;
      case 'crops':
        dest = CropsManagementScreen(farm: f);
        break;
      case 'expenses':
        dest = ExpensesManagementScreen(farm: f);
        break;
      case 'livestock':
        dest = LivestockManagementScreen(farm: f);
        break;
    }
    if (dest != null) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => dest!));
    } else {
      _soon(key);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.farm;
    final name = pickString(f, ['name', 'farm_name', 'title']) ?? 'Farm';
    final type = pickString(f, ['type', 'farm_type']);
    final loc = [pickString(f, ['city']), pickString(f, ['state']), pickString(f, ['country'])]
        .where((x) => x != null && x.isNotEmpty)
        .join(', ');
    final sizeTxt = farmAreaText(f);

    return Scaffold(
      backgroundColor: context.palette.surface,
      body: MaxWidthBody(
        child: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: 178,
              backgroundColor: _heroDark,
              foregroundColor: Colors.white,
              elevation: 0,
              systemOverlayStyle: SystemUiOverlayStyle.light,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              flexibleSpace: Stack(
                fit: StackFit.expand,
                children: [
                  // static layers — built once, isolated from per-frame collapse rebuilds
                  RepaintBoundary(child: FarmlandBackground(showPins: false, child: const SizedBox.expand())),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x330E2018), Color(0xE60E2018)]),
                    ),
                  ),
                  // only the collapse-dependent layers rebuild as you scroll
                  LayoutBuilder(
                    builder: (context, c) {
                      final top = MediaQuery.of(context).padding.top;
                      final maxH = 178.0 + top;
                      final minH = kToolbarHeight + top;
                      // t = 1 fully expanded -> 0 fully collapsed
                      final t = ((c.maxHeight - minH) / (maxH - minH)).clamp(0.0, 1.0);
                      // collapsed title only fades in over the last stretch of the collapse
                      final titleOpacity = ((0.45 - t) / 0.45).clamp(0.0, 1.0);
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          // solid bar fades in as it collapses, for a clean compact app bar
                          Positioned.fill(
                            child: IgnorePointer(child: Opacity(opacity: titleOpacity, child: const ColoredBox(color: _heroDark))),
                          ),
                          // expanded hero content, fades out on collapse
                          Positioned(
                            left: 18,
                            right: 18,
                            bottom: 18,
                            child: SafeArea(
                              bottom: false,
                              child: Opacity(opacity: t, child: _heroContent(name, type, loc, sizeTxt)),
                            ),
                          ),
                          // collapsed title (farm name) pinned in the toolbar, next to the back arrow
                          Positioned(
                            top: top,
                            left: 56,
                            right: 16,
                            height: kToolbarHeight,
                            child: IgnorePointer(
                              child: Opacity(
                                opacity: titleOpacity,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 18, color: Colors.white),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            SliverToBoxAdapter(child: _storeActions()),
            SliverToBoxAdapter(child: _manageGrid()),
            SliverToBoxAdapter(child: _statStrip()),
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
                      child: _Rise(index: i, child: _ProduceCard(record: _view[i], onTransfer: () => _openTransfer(_view[i]), onLink: () => _openLink(_view[i]))),
                    ),
                    childCount: _view.length,
                  ),
                ),
              ),
          ],
        ),
      ),
      ),
    );
  }

  // ---- redesigned hero content: type chip + big name + location/size meta ----
  Widget _heroContent(String name, String? type, String loc, String sizeTxt) {
    final tl = (type ?? '').toLowerCase();
    final typeLabel = (type == null || type.isEmpty) ? 'Farm' : (type[0].toUpperCase() + type.substring(1));
    IconData typeIcon;
    if (tl.contains('crop')) {
      typeIcon = Icons.eco_rounded;
    } else if (tl.contains('live') || tl.contains('animal')) {
      typeIcon = Icons.pets_rounded;
    } else if (tl.contains('mix')) {
      typeIcon = Icons.spa_rounded;
    } else {
      typeIcon = Icons.agriculture_rounded;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(typeIcon, size: 13, color: const Color(0xFFBBF7D0)),
            const SizedBox(width: 5),
            Text(typeLabel,
                style: const TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFBBF7D0))),
          ]),
        ),
        const SizedBox(height: 9),
        Text(name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontFamily: 'Fraunces', fontWeight: FontWeight.w900, fontSize: 26, height: 1.0, color: Colors.white)),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(Icons.location_on_rounded, size: 13, color: Colors.white70),
            const SizedBox(width: 4),
            Flexible(
              child: Text(loc.isEmpty ? 'Location not set' : loc,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontFamily: 'Inter', fontSize: 12.5, fontWeight: FontWeight.w500, color: Colors.white.withValues(alpha: 0.92))),
            ),
            if (sizeTxt.isNotEmpty) ...[
              Text('   ·   ', style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.5))),
              const Icon(Icons.straighten_rounded, size: 13, color: Colors.white70),
              const SizedBox(width: 4),
              Text(sizeTxt,
                  style: TextStyle(
                      fontFamily: 'Inter', fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.92))),
            ],
          ],
        ),
      ],
    );
  }

  // ---- 2x2 management grid, directly under the hero ----
  Widget _manageGrid() {
    const tiles = [
      ['land', Icons.agriculture_rounded, 'Land', 'Fields, plots & assets', Color(0xFF3F7A31)],
      ['livestock', Icons.pets_rounded, 'Livestock', 'Animals & herds', Color(0xFFC39A48)],
      ['crops', Icons.eco_rounded, 'Crops', 'Cycles, yields & health', Color(0xFF6AA83A)],
      ['expenses', Icons.payments_rounded, 'Expenses', 'Costs & spending', Color(0xFF0D9488)],
    ];

    Widget card(List t) => _ManageCard(
          icon: t[1] as IconData,
          title: t[2] as String,
          sub: t[3] as String,
          color: t[4] as Color,
          onTap: () => _openManage(t[0] as String),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Manage this farm',
              style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 17, color: context.palette.ink)),
          const SizedBox(height: 10),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: card(tiles[0])),
                const SizedBox(width: 10),
                Expanded(child: card(tiles[1])),
              ],
            ),
          ),
          const SizedBox(height: 10),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: card(tiles[2])),
                const SizedBox(width: 10),
                Expanded(child: card(tiles[3])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---- slim stats strip below the manage grid ----
  Widget _statStrip() {
    final ha = farmToHa(widget.farm);
    final collections = (pickNum(_summary, ['total_collections']) ?? 0).toDouble();
    final qty = (pickNum(_summary, ['total_quantity']) ?? 0).toDouble();
    final last = pickString(_summary, ['last_collection']);
    String n(double v, {int d = 0}) => d > 0 ? v.toStringAsFixed(d) : v.round().toString();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Container(
        decoration: BoxDecoration(color: context.palette.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: context.palette.line)),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          children: [
            _statCell(n(collections), 'Collections'),
            _statDivider(),
            _statCell(n(qty), 'Units'),
            _statDivider(),
            _statCell(n(ha, d: ha > 0 && ha < 100 ? 1 : 0), 'Land · ha'),
            _statDivider(),
            _statCell((last == null || last.isEmpty) ? '—' : last, 'Last', size: 12.5),
          ],
        ),
      ),
    );
  }

  Widget _statCell(String value, String label, {double size = 17}) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w900, fontSize: size, color: context.palette.ink)),
          const SizedBox(height: 2),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w600, color: context.palette.muted)),
        ],
      ),
    );
  }

  Widget _statDivider() => Container(width: 0.5, height: 30, color: context.palette.line);

  Widget _produceHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Produce history',
                    style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 17, color: context.palette.ink)),
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
                fillColor: context.palette.card,
                hintText: 'Search produce…',
                prefixIcon: const Icon(Icons.search, size: 20),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: BorderSide(color: context.palette.line)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: BorderSide(color: context.palette.line)),
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
                        color: on ? AppColors.g600 : context.palette.card,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: on ? AppColors.g600 : context.palette.line),
                      ),
                      child: Text(t[1],
                          style: TextStyle(
                              fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13, color: on ? Colors.white : context.palette.muted3)),
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
class _ManageCard extends StatelessWidget {
  final IconData icon;
  final String title, sub;
  final Color color;
  final VoidCallback onTap;
  const _ManageCard({required this.icon, required this.title, required this.sub, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.palette.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: context.palette.line)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: Colors.white, size: 21),
              ),
              const SizedBox(height: 10),
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 14.5, color: context.palette.ink)),
              const SizedBox(height: 1),
              Text(sub,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'Inter', fontSize: 11.5, color: context.palette.muted)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProduceCard extends StatelessWidget {
  final Map<String, dynamic> record;
  final VoidCallback onTransfer, onLink;
  const _ProduceCard({required this.record, required this.onTransfer, required this.onLink});

  Widget _action(IconData icon, String label, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: const Color(0xFFFAF7EF), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.line)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 15, color: AppColors.slate600),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 12.5, color: AppColors.slate600)),
          ]),
        ),
      ),
    );
  }

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
          color: context.palette.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.palette.line),
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
              Text(date, style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: context.palette.muted)),
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
                    style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 16, color: context.palette.ink)),
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
                      color: context.palette.chipBg, borderRadius: BorderRadius.circular(999), border: Border.all(color: const Color(0xFFBFE3CD))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.storefront_rounded, size: 11, color: Color(0xFF0F7A4B)),
                    const SizedBox(width: 4),
                    Text(store, style: const TextStyle(fontFamily: 'Inter', fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF0F7A4B))),
                  ]),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 12),
          Row(children: [
            _action(Icons.swap_horiz_rounded, 'Transfer', onTransfer),
            const SizedBox(width: 8),
            _action(Icons.link_rounded, 'Link', onLink),
          ]),
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
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
  late final Animation<double> _a = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: (widget.index.clamp(0, 5)) * 18), () {
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
  DateTime _date = DateTime.now();
  String _grade = '';

  static const _units = ['kg', 'liters', 'crates', 'bags', 'tons', 'pieces'];
  static const _grades = [
    ['A', 'Grade A'],
    ['B', 'Grade B'],
    ['C', 'Grade C'],
    ['Organic', 'Organic'],
    ['Rejected', 'Rejected'],
  ];

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
    final dateStr =
        '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';
    final notes = _notes.text.trim();
    Navigator.pop(context, {
      'source': _source,
      'product_name': name,
      'quantity': qty,
      'unit': _unit,
      'collection_date': dateStr,
      'quality_grade': _grade.isEmpty ? null : _grade,
      'notes': notes.isEmpty ? null : notes,
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: BoxDecoration(color: context.palette.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 42, height: 4, decoration: BoxDecoration(color: context.palette.line, borderRadius: BorderRadius.circular(99)))),
            const SizedBox(height: 14),
            Text('Log produce collection',
                style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 19, color: context.palette.ink)),
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
            _dateField(),
            const SizedBox(height: 10),
            _gradeChips(),
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
          color: on ? context.palette.chipBg : context.palette.card,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: on ? AppColors.g600 : context.palette.line, width: on ? 1.5 : 1),
        ),
        child: Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 12.5, color: on ? AppColors.g700 : context.palette.muted2)),
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
        fillColor: context.palette.card,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: BorderSide(color: context.palette.line)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: BorderSide(color: context.palette.line)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: AppColors.green)),
      ),
    );
  }

  Widget _dateField() {
    final d = _date;
    final label = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 6),
          child: Text('Collection date',
              style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 12.5, color: context.palette.muted3)),
        ),
        GestureDetector(
          onTap: _pickDate,
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(color: context.palette.card, borderRadius: BorderRadius.circular(11), border: Border.all(color: context.palette.line)),
            child: Row(
              children: [
                Icon(Icons.event_rounded, size: 18, color: context.palette.muted),
                const SizedBox(width: 10),
                Text(label, style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: context.palette.ink)),
                const Spacer(),
                Icon(Icons.expand_more_rounded, size: 18, color: context.palette.muted),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _gradeChips() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 6),
          child: Text('Quality grade (optional)',
              style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 12.5, color: context.palette.muted3)),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _grades.map((g) {
            final on = _grade == g[0];
            return GestureDetector(
              onTap: () => setState(() => _grade = on ? '' : g[0]),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: on ? AppColors.g600 : context.palette.card,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: on ? AppColors.g600 : context.palette.line),
                ),
                child: Text(g[1],
                    style: TextStyle(
                        fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 12.5, color: on ? Colors.white : context.palette.muted3)),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _unitChips() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 6),
          child: Text('Unit',
              style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 12.5, color: context.palette.muted3)),
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
                  color: on ? AppColors.g600 : context.palette.card,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: on ? AppColors.g600 : context.palette.line),
                ),
                child: Text(u,
                    style: TextStyle(
                        fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 12.5, color: on ? Colors.white : context.palette.muted3)),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared bottom-sheet helpers + Transfer / Link produce sheets

String _isoDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

List<Map<String, dynamic>> _listOf(dynamic d) {
  if (d is List) return d.whereType<Map<String, dynamic>>().toList();
  if (d is Map && d['results'] is List) return (d['results'] as List).whereType<Map<String, dynamic>>().toList();
  return [];
}
// in-memory cache for the full stores list, shared across the produce/store sheets
List<Map<String, dynamic>>? _storesCache;
DateTime? _storesCacheAt;
Future<List<Map<String, dynamic>>> _loadStoresCached(dynamic dio) async {
  final fresh = _storesCacheAt != null && DateTime.now().difference(_storesCacheAt!).inSeconds < 60;
  if (_storesCache != null && fresh) return _storesCache!;
  final res = await dio.get(Api.stores);
  _storesCache = _listOf(res.data);
  _storesCacheAt = DateTime.now();
  return _storesCache!;
}
void _invalidateStoresCache() {
  _storesCache = null;
  _storesCacheAt = null;
}

Widget _sheetLabel(String t) => Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 6),
      child: Text(t, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 12.5, color: AppColors.slate700)),
    );

Widget _sheetField(TextEditingController c, String hint, {bool number = false, int lines = 1}) {
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

Widget _sheetReadonly(String value) => Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(color: const Color(0xFFF3EFE6), borderRadius: BorderRadius.circular(11), border: Border.all(color: AppColors.line)),
      child: Text(value.isEmpty ? '—' : value, style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppColors.slate600)),
    );

Widget _sheetCheck(String label, bool value, VoidCallback onTap) {
  return GestureDetector(
    onTap: onTap,
    child: Row(children: [
      Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: value ? AppColors.g600 : Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: value ? AppColors.g600 : AppColors.line, width: 1.5),
        ),
        child: value ? const Icon(Icons.check, size: 15, color: Colors.white) : null,
      ),
      const SizedBox(width: 10),
      Expanded(child: Text(label, style: const TextStyle(fontFamily: 'Inter', fontSize: 13.5, color: AppColors.slate700))),
    ]),
  );
}

Widget _sheetSaveButton(String label, VoidCallback onTap) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      height: 50,
      alignment: Alignment.center,
      decoration: BoxDecoration(gradient: AppColors.emeraldGrad, borderRadius: BorderRadius.circular(13)),
      child: Text(label, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, color: Colors.white, fontSize: 15)),
    ),
  );
}

Widget _sheetError(String msg) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFFCA5A5))),
      child: Text(msg, style: const TextStyle(fontFamily: 'Inter', fontSize: 12.5, color: Color(0xFFDC2626))),
    );

Widget _storeDropdown({
  required bool loading,
  required List<Map<String, dynamic>> stores,
  required int? value,
  required ValueChanged<int?> onChanged,
  required String emptyText,
}) {
  if (loading) return _sheetReadonly('Loading stores…');
  if (stores.isEmpty) return _sheetReadonly(emptyText);
  return Container(
    height: 48,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(11), border: Border.all(color: AppColors.line)),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<int>(
        isExpanded: true,
        value: value,
        hint: const Text('Select store', style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppColors.slate500)),
        items: stores.map((s) {
          final id = (pickNum(s, ['id']) ?? 0).toInt();
          final name = pickString(s, ['name']) ?? 'Store';
          return DropdownMenuItem<int>(
              value: id, child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppColors.inkWarm)));
        }).toList(),
        onChanged: onChanged,
      ),
    ),
  );
}

Widget _sheetExpiry(DateTime? expiry, VoidCallback onPick, VoidCallback onClear) {
  return GestureDetector(
    onTap: onPick,
    child: Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(11), border: Border.all(color: AppColors.line)),
      child: Row(children: [
        const Icon(Icons.event_rounded, size: 18, color: AppColors.slate500),
        const SizedBox(width: 10),
        Text(expiry == null ? 'No expiry' : _isoDate(expiry),
            style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: expiry == null ? AppColors.slate500 : AppColors.inkWarm)),
        const Spacer(),
        if (expiry != null)
          GestureDetector(onTap: onClear, child: const Icon(Icons.close_rounded, size: 18, color: AppColors.slate500))
        else
          const Icon(Icons.expand_more_rounded, size: 18, color: AppColors.slate500),
      ]),
    ),
  );
}

// ----- Transfer produce -> digital store -----------------------------------
class _TransferSheet extends StatefulWidget {
  final Map<String, dynamic> record;
  final int farmId;
  const _TransferSheet({required this.record, required this.farmId});
  @override
  State<_TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends State<_TransferSheet> {
  final _title = TextEditingController();
  final _price = TextEditingController();
  final _qty = TextEditingController();
  final _desc = TextEditingController();
  List<Map<String, dynamic>> _stores = [];
  bool _loading = true;
  int? _store;
  DateTime? _expiry;
  bool _dropship = false;
  String? _err;

  double get _available => (pickNum(widget.record, ['quantity']) ?? 0).toDouble();
  String get _unit => pickString(widget.record, ['unit']) ?? '';
  String _qtyStr(double v) => v % 1 == 0 ? v.toInt().toString() : v.toString();

  @override
  void initState() {
    super.initState();
    _title.text = pickString(widget.record, ['product_name']) ?? '';
    _qty.text = _available > 0 ? _qtyStr(_available) : '';
    _desc.text = pickString(widget.record, ['notes']) ?? '';
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStores());
  }

  @override
  void dispose() {
    _title.dispose();
    _price.dispose();
    _qty.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _loadStores() async {
    try {
      final res = await context.read<DioClient>().dio.get('${Api.stores}?farm=${widget.farmId}');
      final list = _listOf(res.data);
      if (!mounted) return;
      setState(() {
        _stores = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _stores = [];
        _loading = false;
      });
    }
  }

  Future<void> _pickExpiry() async {
    final d = await showDatePicker(
        context: context, initialDate: _expiry ?? DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime(2100));
    if (d != null) setState(() => _expiry = d);
  }

  void _submit() {
    final title = _title.text.trim();
    final price = double.tryParse(_price.text.trim());
    final qty = double.tryParse(_qty.text.trim());
    if (_store == null || title.isEmpty || price == null || qty == null || qty <= 0) {
      setState(() => _err = 'Select a store and fill title, price and a transfer quantity.');
      return;
    }
    if (qty > _available) {
      setState(() => _err = 'Transfer quantity cannot exceed available (${_qtyStr(_available)}).');
      return;
    }
    Navigator.pop(context, {
      'store': _store,
      'title': title,
      'price': price,
      'quantity': qty,
      'unit': _unit,
      'expiration': _expiry == null ? null : _isoDate(_expiry!),
      'dropship': _dropship,
      'description': _desc.text.trim(),
      'available': _available,
      'produce_id': (pickNum(widget.record, ['id']) ?? 0).toInt(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: BoxDecoration(color: context.palette.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 42, height: 4, decoration: BoxDecoration(color: context.palette.line, borderRadius: BorderRadius.circular(99)))),
              const SizedBox(height: 14),
              Text('Transfer produce to a store',
                  style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 19, color: context.palette.ink)),
              const SizedBox(height: 4),
              Text('Available: ${_qtyStr(_available)} $_unit',
                  style: TextStyle(fontFamily: 'Inter', fontSize: 12.5, color: context.palette.muted)),
              const SizedBox(height: 14),
              if (_err != null) _sheetError(_err!),
              _sheetLabel('Store'),
              _storeDropdown(
                  loading: _loading,
                  stores: _stores,
                  value: _store,
                  onChanged: (v) => setState(() => _store = v),
                  emptyText: 'No stores linked to this farm yet'),
              const SizedBox(height: 12),
              _sheetLabel('Product title'),
              _sheetField(_title, 'Title'),
              const SizedBox(height: 12),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_sheetLabel('Price / unit'), _sheetField(_price, '0.00', number: true)])),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_sheetLabel('Quantity'), _sheetField(_qty, '0', number: true)])),
              ]),
              const SizedBox(height: 12),
              _sheetLabel('Unit'),
              _sheetReadonly(_unit),
              const SizedBox(height: 12),
              _sheetLabel('Expiry date (optional)'),
              _sheetExpiry(_expiry, _pickExpiry, () => setState(() => _expiry = null)),
              const SizedBox(height: 14),
              _sheetCheck('Dropshippable', _dropship, () => setState(() => _dropship = !_dropship)),
              const SizedBox(height: 12),
              _sheetLabel('Description (optional)'),
              _sheetField(_desc, 'Description', lines: 2),
              const SizedBox(height: 16),
              _sheetSaveButton('Transfer', _submit),
            ],
          ),
        ),
      ),
    );
  }
}

// ----- Link produce -> digital store ---------------------------------------
class _LinkSheet extends StatefulWidget {
  final Map<String, dynamic> record;
  const _LinkSheet({required this.record});
  @override
  State<_LinkSheet> createState() => _LinkSheetState();
}

class _LinkSheetState extends State<_LinkSheet> {
  final _title = TextEditingController();
  final _price = TextEditingController();
  final _qty = TextEditingController();
  final _category = TextEditingController(text: 'Produce');
  final _desc = TextEditingController();
  List<Map<String, dynamic>> _stores = [];
  bool _loading = true;
  int? _store;
  DateTime? _expiry;
  bool _dropship = false;
  bool _reduce = false;
  String? _err;

  double get _available => (pickNum(widget.record, ['quantity']) ?? 0).toDouble();
  String get _unit => pickString(widget.record, ['unit']) ?? '';
  String _qtyStr(double v) => v % 1 == 0 ? v.toInt().toString() : v.toString();

  @override
  void initState() {
    super.initState();
    _title.text = pickString(widget.record, ['product_name']) ?? '';
    _desc.text = pickString(widget.record, ['notes']) ?? '';
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStores());
  }

  @override
  void dispose() {
    _title.dispose();
    _price.dispose();
    _qty.dispose();
    _category.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _loadStores() async {
    try {
      final list = await _loadStoresCached(context.read<DioClient>().dio);
      if (!mounted) return;
      setState(() {
        _stores = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _stores = [];
        _loading = false;
      });
    }
  }

  Future<void> _pickExpiry() async {
    final d = await showDatePicker(
        context: context, initialDate: _expiry ?? DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime(2100));
    if (d != null) setState(() => _expiry = d);
  }

  void _submit() {
    final title = _title.text.trim();
    final price = double.tryParse(_price.text.trim()) ?? 0.0;
    final qty = double.tryParse(_qty.text.trim()) ?? 0.0;
    if (_store == null || title.isEmpty) {
      setState(() => _err = 'Select a store and enter a title.');
      return;
    }
    if (_reduce && qty <= 0) {
      setState(() => _err = 'Enter a quantity to reduce farm stock by.');
      return;
    }
    if (qty > _available) {
      setState(() => _err = 'Quantity cannot exceed available (${_qtyStr(_available)}).');
      return;
    }
    Navigator.pop(context, {
      'store': _store,
      'title': title,
      'price': price,
      'quantity': qty,
      'unit': _unit,
      'category': _category.text.trim().isEmpty ? 'Produce' : _category.text.trim(),
      'expiration': _expiry == null ? null : _isoDate(_expiry!),
      'dropship': _dropship,
      'reduce': _reduce,
      'description': _desc.text.trim(),
      'available': _available,
      'produce_id': (pickNum(widget.record, ['id']) ?? 0).toInt(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: BoxDecoration(color: context.palette.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 42, height: 4, decoration: BoxDecoration(color: context.palette.line, borderRadius: BorderRadius.circular(99)))),
              const SizedBox(height: 14),
              Text('Link produce to a store',
                  style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 19, color: context.palette.ink)),
              const SizedBox(height: 4),
              Text('Available: ${_qtyStr(_available)} $_unit',
                  style: TextStyle(fontFamily: 'Inter', fontSize: 12.5, color: context.palette.muted)),
              const SizedBox(height: 14),
              if (_err != null) _sheetError(_err!),
              _sheetLabel('Store'),
              _storeDropdown(
                  loading: _loading,
                  stores: _stores,
                  value: _store,
                  onChanged: (v) => setState(() => _store = v),
                  emptyText: 'No stores yet — create one on the web first'),
              const SizedBox(height: 12),
              _sheetLabel('Product title'),
              _sheetField(_title, 'Title'),
              const SizedBox(height: 12),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_sheetLabel('Price / unit'), _sheetField(_price, '0.00', number: true)])),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_sheetLabel('Qty on store'), _sheetField(_qty, '0', number: true)])),
              ]),
              const SizedBox(height: 12),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_sheetLabel('Unit'), _sheetReadonly(_unit)])),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_sheetLabel('Category'), _sheetField(_category, 'Produce')])),
              ]),
              const SizedBox(height: 12),
              _sheetLabel('Expiry date (optional)'),
              _sheetExpiry(_expiry, _pickExpiry, () => setState(() => _expiry = null)),
              const SizedBox(height: 14),
              _sheetCheck('Dropshippable', _dropship, () => setState(() => _dropship = !_dropship)),
              const SizedBox(height: 12),
              _sheetCheck('Also reduce farm stock by the linked quantity', _reduce, () => setState(() => _reduce = !_reduce)),
              const SizedBox(height: 12),
              _sheetLabel('Description (optional)'),
              _sheetField(_desc, 'Description', lines: 2),
              const SizedBox(height: 16),
              _sheetSaveButton('Link', _submit),
            ],
          ),
        ),
      ),
    );
  }
}

// ----- Linked stores list (manage / unlink) --------------------------------
class _LinkedStoresSheet extends StatefulWidget {
  final int farmId;
  const _LinkedStoresSheet({required this.farmId});
  @override
  State<_LinkedStoresSheet> createState() => _LinkedStoresSheetState();
}

class _LinkedStoresSheetState extends State<_LinkedStoresSheet> {
  List<Map<String, dynamic>> _stores = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final res = await context.read<DioClient>().dio.get('${Api.stores}?farm=${widget.farmId}');
      if (!mounted) return;
      setState(() {
        _stores = _listOf(res.data);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _stores = [];
        _loading = false;
      });
    }
  }

  Future<void> _unlink(Map<String, dynamic> s) async {
    final id = pickNum(s, ['id']);
    try {
      await context.read<DioClient>().dio.patch('${Api.stores}$id/', data: {'farm': null});
      if (!mounted) return;
      showToast(context, 'Store unlinked');
      _load();
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), success: false);
    }
  }

  Widget _miniBtn(IconData icon, String label, VoidCallback onTap, {bool primary = false, bool danger = false}) {
    final fg = danger ? const Color(0xFFDC2626) : (primary ? Colors.white : context.palette.muted2);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: primary ? null : (danger ? const Color(0xFFFEF2F2) : const Color(0xFFFAF7EF)),
          gradient: primary ? AppColors.emeraldGrad : null,
          borderRadius: BorderRadius.circular(10),
          border: primary ? null : Border.all(color: danger ? const Color(0xFFFCA5A5) : context.palette.line),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: fg),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 12.5, color: fg)),
        ]),
      ),
    );
  }

  Widget _storeRow(Map<String, dynamic> s) {
    final name = pickString(s, ['name']) ?? 'Store';
    final owner = pickString(s, ['owner_name']) ?? '';
    final email = pickString(s, ['owner_email']) ?? pickString(s, ['email']) ?? '';
    final sub = [owner, email].where((x) => x.isNotEmpty).join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: context.palette.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.palette.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 15, color: context.palette.ink)),
          if (sub.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: 'Inter', fontSize: 11.5, color: context.palette.muted)),
          ],
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _miniBtn(Icons.open_in_new_rounded, 'Manage', () => showStoreDetail(context, s), primary: true)),
            const SizedBox(width: 8),
            Expanded(child: _miniBtn(Icons.link_off_rounded, 'Unlink', () => _unlink(s), danger: true)),
          ]),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: BoxDecoration(color: context.palette.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 42, height: 4, decoration: BoxDecoration(color: context.palette.line, borderRadius: BorderRadius.circular(99)))),
            const SizedBox(height: 14),
            Text('Linked stores', style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 19, color: context.palette.ink)),
            const SizedBox(height: 4),
            Text('Digital stores tied to this farm.', style: TextStyle(fontFamily: 'Inter', fontSize: 12.5, color: context.palette.muted)),
            const SizedBox(height: 14),
            if (_loading)
              Padding(padding: const EdgeInsets.symmetric(vertical: 30), child: Center(child: Text('Loading…', style: TextStyle(fontFamily: 'Inter', color: context.palette.muted))))
            else if (_stores.isEmpty)
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text('No stores linked to this farm yet. Use "Link a store" to attach one.',
                      style: TextStyle(fontFamily: 'Inter', fontSize: 13.5, color: context.palette.muted2)))
            else
              Flexible(child: SingleChildScrollView(child: Column(children: _stores.map(_storeRow).toList()))),
          ],
        ),
      ),
    );
  }
}

// ----- Link / create a store for this farm ---------------------------------
class _ConnectStoreSheet extends StatefulWidget {
  final int farmId;
  const _ConnectStoreSheet({required this.farmId});
  @override
  State<_ConnectStoreSheet> createState() => _ConnectStoreSheetState();
}

class _ConnectStoreSheetState extends State<_ConnectStoreSheet> {
  final _name = TextEditingController();
  final _owner = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _countries = TextEditingController();
  final _desc = TextEditingController();
  List<Map<String, dynamic>> _stores = [];
  bool _loading = true;
  bool _saving = false;
  bool _createMode = false;
  int? _store;
  String? _err;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _name.dispose();
    _owner.dispose();
    _phone.dispose();
    _email.dispose();
    _countries.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await _loadStoresCached(context.read<DioClient>().dio);
      if (!mounted) return;
      setState(() {
        _stores = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _stores = [];
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _err = null);
    if (_createMode) {
      if (_name.text.trim().isEmpty) {
        setState(() => _err = 'Enter a name for the new store.');
        return;
      }
      if (_owner.text.trim().isEmpty) {
        setState(() => _err = 'Enter the store owner name.');
        return;
      }
      if (_phone.text.trim().isEmpty) {
        setState(() => _err = 'Enter a phone contact.');
        return;
      }
    } else if (_store == null) {
      setState(() => _err = 'Select a store to link.');
      return;
    }
    setState(() => _saving = true);
    try {
      final dio = context.read<DioClient>().dio;
      if (_createMode) {
        final countries = _countries.text.trim().isEmpty
            ? <String>[]
            : _countries.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
        final payload = <String, dynamic>{
          'name': _name.text.trim(),
          'farm': widget.farmId,
          'owner_name': _owner.text.trim(),
          'owner_phone': _phone.text.trim(),
          'owner_email': _email.text.trim(),
          'countries_of_operation': countries,
        };
        if (_desc.text.trim().isNotEmpty) payload['description'] = _desc.text.trim();
        await dio.post(Api.stores, data: payload);
        _invalidateStoresCache();
      } else {
        await dio.patch('${Api.stores}$_store/', data: {'farm': widget.farmId});
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _err = friendlyError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: BoxDecoration(color: context.palette.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 42, height: 4, decoration: BoxDecoration(color: context.palette.line, borderRadius: BorderRadius.circular(99)))),
              const SizedBox(height: 14),
              Text('Link a store to this farm',
                  style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 19, color: context.palette.ink)),
              const SizedBox(height: 14),
              if (_err != null) _sheetError(_err!),
              if (!_createMode) ...[
                _sheetLabel('Existing store'),
                _storeDropdown(
                    loading: _loading,
                    stores: _stores,
                    value: _store,
                    onChanged: (v) => setState(() => _store = v),
                    emptyText: 'No stores yet — create one below'),
                const SizedBox(height: 12),
              ],
              GestureDetector(
                onTap: () => setState(() => _createMode = !_createMode),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(_createMode ? Icons.remove_circle_outline_rounded : Icons.add_circle_outline_rounded, size: 18, color: AppColors.g700),
                  const SizedBox(width: 6),
                  Text(_createMode ? 'Use an existing store instead' : 'Create a new store',
                      style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.g700)),
                ]),
              ),
              if (_createMode) ...[
                const SizedBox(height: 12),
                _sheetLabel('Store name'),
                _sheetField(_name, 'Store name'),
                const SizedBox(height: 10),
                _sheetLabel('Owner name'),
                _sheetField(_owner, 'Owner name'),
                const SizedBox(height: 10),
                _sheetLabel('Phone contact'),
                _sheetField(_phone, 'Phone contact'),
                const SizedBox(height: 10),
                _sheetLabel('Store email (optional)'),
                _sheetField(_email, 'Email'),
                const SizedBox(height: 10),
                _sheetLabel('Countries of operation (optional)'),
                _sheetField(_countries, 'e.g. Uganda, Kenya'),
                const SizedBox(height: 10),
                _sheetLabel('Description (optional)'),
                _sheetField(_desc, 'Description', lines: 2),
              ],
              const SizedBox(height: 16),
              _sheetSaveButton(_saving ? 'Saving…' : (_createMode ? 'Create & link' : 'Link store'), _saving ? () {} : _save),
            ],
          ),
        ),
      ),
    );
  }
}