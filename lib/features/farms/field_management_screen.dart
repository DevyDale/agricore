import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/network/dio_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/json_utils.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/farmland_background.dart';
import '../../widgets/state_views.dart';

const Color _heroDark = Color(0xFF22432C);
const String _fieldsPath = '/fields/';

class FieldManagementScreen extends StatefulWidget {
  final Map<String, dynamic> farm;
  const FieldManagementScreen({super.key, required this.farm});
  @override
  State<FieldManagementScreen> createState() => _FieldManagementScreenState();
}

class _FieldManagementScreenState extends State<FieldManagementScreen> {
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _portions = [];
  bool _loading = true;
  String? _error;
  String _query = '';

  int get _farmId => (pickNum(widget.farm, ['id']) ?? 0).toInt();
  double get _maxSize => (pickNum(widget.farm, ['total_size']) ?? 0).toDouble();
  String get _unit => pickString(widget.farm, ['size_unit']) ?? 'acres';

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

  double _portionSize(Map<String, dynamic> p) => (pickNum(p, ['total_size', 'size']) ?? 0).toDouble();
  double get _used => _portions.fold(0.0, (s, p) => s + _portionSize(p));
  double get _available => _maxSize > 0 ? (_maxSize - _used).clamp(0, _maxSize) : 0;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dio = context.read<DioClient>().dio;
      final res = await dio.get(_fieldsPath, queryParameters: {'farm': _farmId});
      if (!mounted) return;
      setState(() {
        _portions = _asList(res.data);
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
    if (_query.isEmpty) return _portions;
    final q = _query.toLowerCase();
    return _portions.where((p) {
      final blob = [
        pickString(p, ['name']),
        pickString(p, ['purpose']),
        pickString(p, ['soil_type']),
      ].whereType<String>().join(' ').toLowerCase();
      return blob.contains(q);
    }).toList();
  }

  Future<void> _addPortion() async {
    if (_maxSize > 0 && _available <= 0) {
      showToast(context, 'No land left to allocate.', success: false);
      return;
    }
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PortionSheet(maxAvailable: _maxSize > 0 ? _available : null, unit: _unit),
    );
    if (result == null) return;
    if (!mounted) return;
    try {
      final dio = context.read<DioClient>().dio;
      await dio.post(_fieldsPath, data: {...result, 'farm': _farmId, 'size_unit': _unit});
      if (!mounted) return;
      showToast(context, 'Portion added');
      _load();
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), success: false);
    }
  }

  Future<void> _deletePortion(Map<String, dynamic> p) async {
    final name = pickString(p, ['name']) ?? 'this portion';
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete portion?'),
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
      final dio = context.read<DioClient>().dio;
      await dio.delete('$_fieldsPath${pickNum(p, ['id'])?.toInt()}/');
      if (!mounted) return;
      showToast(context, 'Portion deleted');
      _load();
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), success: false);
    }
  }

  Future<void> _transfer(Map<String, dynamic> from) async {
    final others = _portions.where((p) => p['id'] != from['id']).toList();
    if (others.isEmpty) {
      showToast(context, 'You need at least two portions to transfer.', success: false);
      return;
    }
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TransferSheet(from: from, others: others, unit: _unit, sizeOf: _portionSize),
    );
    if (result == null) return;
    final toId = result['to'] as int;
    final amt = result['amount'] as double;
    final to = _portions.firstWhere((p) => (pickNum(p, ['id'])?.toInt()) == toId);
    final newFrom = (_portionSize(from) - amt);
    final newTo = (_portionSize(to) + amt);
    if (!mounted) return;
    try {
      final dio = context.read<DioClient>().dio;
      await dio.patch('$_fieldsPath${pickNum(from, ['id'])?.toInt()}/', data: {'total_size': newFrom});
      await dio.patch('$_fieldsPath$toId/', data: {'total_size': newTo});
      if (!mounted) return;
      showToast(context, 'Land transferred');
      _load();
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), success: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final farmName = pickString(widget.farm, ['name', 'farm_name', 'title']) ?? 'Farm';
    final sizeTxt = _maxSize > 0 ? '${_fmt(_maxSize)} $_unit' : 'Size not set';
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: 176,
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
                title: const Text('Land Management',
                    style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w900, fontSize: 18, color: Colors.white)),
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
                      bottom: 50,
                      child: SafeArea(
                        bottom: false,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                          decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.2))),
                          child: Text('$farmName  ·  $sizeTxt',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFBBF7D0))),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(child: _allocationCard()),
            SliverToBoxAdapter(child: _portionsHeader()),
            if (_loading)
              const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.only(top: 36), child: LoadingView()))
            else if (_error != null)
              SliverToBoxAdapter(
                  child: Padding(padding: const EdgeInsets.only(top: 28), child: ErrorView(message: _error!, onRetry: _load)))
            else if (_view.isEmpty)
              const SliverToBoxAdapter(
                  child: Padding(
                      padding: EdgeInsets.only(top: 24),
                      child: EmptyView(text: 'No land portions yet. Tap "Add portion" to divide your farm into plots.', icon: Icons.grass_outlined)))
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) {
                      final p = _view[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _Rise(
                          index: i,
                          child: _PortionCard(
                            portion: p,
                            unit: _unit,
                            maxSize: _maxSize,
                            sizeOf: _portionSize,
                            canTransfer: _portions.length >= 2,
                            onTransfer: () => _transfer(p),
                            onDelete: () => _deletePortion(p),
                          ),
                        ),
                      );
                    },
                    childCount: _view.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _allocationCard() {
    final pct = _maxSize > 0 ? (_used / _maxSize * 100) : 0.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.line),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 22, offset: const Offset(0, 10))]),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Land allocation',
                style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.inkWarm)),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _UtilRing(pct: pct.toDouble()),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _AllocBar(portions: _portions, max: _maxSize, sizeOf: _portionSize),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 18,
                        runSpacing: 12,
                        children: [
                          _fig('Total area', _maxSize > 0 ? _maxSize : null, const Color(0xFF2F6B3C)),
                          _fig('Used', _used, const Color(0xFF10B981)),
                          _fig('Available', _maxSize > 0 ? _available : null, const Color(0xFFE7DCC6)),
                          _fig('Portions', _portions.length.toDouble(), AppColors.slate500, isCount: true),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _fig(String label, double? value, Color dot, {bool isCount = false}) {
    return SizedBox(
      width: 96,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          value == null
              ? const Text('—',
                  style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.inkWarm))
              : TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: value),
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, __) => Text(
                    isCount ? v.round().toString() : _fmt(v),
                    style: const TextStyle(
                        fontFamily: 'Fraunces', fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.inkWarm),
                  ),
                ),
          const SizedBox(height: 3),
          Row(
            children: [
              Container(width: 9, height: 9, decoration: BoxDecoration(color: dot, borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 5),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontFamily: 'Inter', fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.slate500)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _portionsHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Land portions',
                    style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.inkWarm)),
              ),
              GestureDetector(
                onTap: _addPortion,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(gradient: AppColors.emeraldGrad, borderRadius: BorderRadius.circular(12)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.add_rounded, color: Colors.white, size: 16),
                    SizedBox(width: 5),
                    Text('Add portion', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 12.5, color: Colors.white)),
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
                hintText: 'Search portions…',
                prefixIcon: const Icon(Icons.search, size: 20),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: const BorderSide(color: AppColors.line)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: const BorderSide(color: AppColors.line)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: const BorderSide(color: AppColors.green)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _fmt(double v) {
  final n = (v * 100).round() / 100;
  if (n == n.roundToDouble()) return n.toInt().toString();
  return n.toStringAsFixed(2);
}

Color purposeColor(String? purpose) {
  final u = (purpose ?? '').toLowerCase();
  if (u.contains('graz') || u.contains('live')) return const Color(0xFFBD8F3E);
  if (u.contains('fallow') || u.contains('forest')) return const Color(0xFF7E9046);
  if (u.contains('orchard') || u.contains('green')) return const Color(0xFF4F8A2F);
  return const Color(0xFF549040);
}

// ---------------------------------------------------------------------------
class _UtilRing extends StatelessWidget {
  final double pct;
  const _UtilRing({required this.pct});

  @override
  Widget build(BuildContext context) {
    final color = pct > 100
        ? const Color(0xFFDC2626)
        : (pct >= 90 ? const Color(0xFFC39A48) : const Color(0xFF10B981));
    return SizedBox(
      width: 96,
      height: 96,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: pct),
        duration: const Duration(milliseconds: 850),
        curve: Curves.easeOutCubic,
        builder: (_, v, __) => Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 96,
              height: 96,
              child: CircularProgressIndicator(
                value: (v / 100).clamp(0.0, 1.0),
                strokeWidth: 11,
                backgroundColor: const Color(0xFFEEE4D2),
                valueColor: AlwaysStoppedAnimation<Color>(color),
                strokeCap: StrokeCap.round,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${v.round()}%',
                    style: const TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w900, fontSize: 20, color: AppColors.inkWarm)),
                const Text('used',
                    style: TextStyle(fontFamily: 'Inter', fontSize: 9.5, fontWeight: FontWeight.w700, color: AppColors.slate500)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AllocBar extends StatelessWidget {
  final List<Map<String, dynamic>> portions;
  final double max;
  final double Function(Map<String, dynamic>) sizeOf;
  const _AllocBar({required this.portions, required this.max, required this.sizeOf});

  @override
  Widget build(BuildContext context) {
    const pal = [
      Color(0xFF2F6B3C), Color(0xFF10B981), Color(0xFF3C7A3C), Color(0xFF6AA83A),
      Color(0xFFC39A48), Color(0xFF8A9A4E), Color(0xFF0D9488),
    ];
    final segments = <Widget>[];
    if (max > 0) {
      double usedPct = 0;
      for (var i = 0; i < portions.length; i++) {
        final sz = sizeOf(portions[i]);
        if (sz <= 0) continue;
        final pctW = (sz / max * 100).clamp(0, 100).toDouble();
        usedPct += pctW;
        segments.add(Expanded(
          flex: (pctW * 10).round().clamp(1, 100000),
          child: Container(color: pal[i % pal.length]),
        ));
      }
      final avail = (100 - usedPct).clamp(0, 100).toDouble();
      if (avail > 0.01) {
        segments.add(Expanded(
          flex: (avail * 10).round().clamp(1, 100000),
          child: Container(color: const Color(0xFFEFE7D6)),
        ));
      }
    } else {
      segments.add(Expanded(child: Container(color: const Color(0xFFEFE7D6))));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 26,
        decoration: BoxDecoration(border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(8)),
        child: Row(children: segments.isEmpty ? [Expanded(child: Container(color: const Color(0xFFEFE7D6)))] : segments),
      ),
    );
  }
}

class _PortionCard extends StatelessWidget {
  final Map<String, dynamic> portion;
  final String unit;
  final double maxSize;
  final double Function(Map<String, dynamic>) sizeOf;
  final bool canTransfer;
  final VoidCallback onTransfer, onDelete;
  const _PortionCard({
    required this.portion,
    required this.unit,
    required this.maxSize,
    required this.sizeOf,
    required this.canTransfer,
    required this.onTransfer,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final p = portion;
    final name = pickString(p, ['name']) ?? 'Portion';
    final size = sizeOf(p);
    final purpose = pickString(p, ['purpose']);
    final soil = pickString(p, ['soil_type']);
    final notes = pickString(p, ['additional_notes']);
    final share = maxSize > 0 ? (size / maxSize * 100).clamp(0, 100).toDouble() : 0.0;

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
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: purposeColor(purpose), borderRadius: BorderRadius.circular(9)),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.inkWarm)),
                    if (notes != null && notes.isNotEmpty)
                      Text(notes,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontFamily: 'Inter', fontSize: 11.5, color: AppColors.slate500)),
                  ],
                ),
              ),
              Text('${_fmt(size)} $unit',
                  style: const TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w900, fontSize: 15, color: AppColors.g700)),
            ],
          ),
          if (maxSize > 0) ...[
            const SizedBox(height: 9),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: share / 100),
                duration: const Duration(milliseconds: 650),
                curve: Curves.easeOutCubic,
                builder: (_, v, __) => LinearProgressIndicator(
                  value: v,
                  minHeight: 5,
                  backgroundColor: const Color(0xFFEEE4D2),
                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.g600),
                ),
              ),
            ),
            const SizedBox(height: 3),
            Text('${share.toStringAsFixed(1)}% of farm',
                style: const TextStyle(fontFamily: 'Inter', fontSize: 10.5, color: AppColors.slate500)),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              if (purpose != null && purpose.isNotEmpty) _tag(purpose, const Color(0xFFE7F4EC), const Color(0xFF0F7A4B)),
              if (soil != null && soil.isNotEmpty) ...[
                const SizedBox(width: 6),
                _tag(soil, const Color(0xFFF6EFE1), const Color(0xFF8A6D2F)),
              ],
              const Spacer(),
              _iconBtn(Icons.swap_horiz_rounded, canTransfer ? onTransfer : null, 'Transfer'),
              const SizedBox(width: 6),
              _iconBtn(Icons.delete_outline_rounded, onDelete, 'Delete', danger: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tag(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(text,
          style: TextStyle(fontFamily: 'Inter', fontSize: 10.5, fontWeight: FontWeight.w700, color: fg)),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback? onTap, String tip, {bool danger = false}) {
    final enabled = onTap != null;
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              border: Border.all(color: AppColors.line),
              borderRadius: BorderRadius.circular(9),
              color: Colors.white),
          child: Icon(icon,
              size: 17,
              color: !enabled
                  ? AppColors.line
                  : (danger ? const Color(0xFFDC2626) : AppColors.slate600)),
        ),
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
class _PortionSheet extends StatefulWidget {
  final double? maxAvailable;
  final String unit;
  const _PortionSheet({required this.maxAvailable, required this.unit});
  @override
  State<_PortionSheet> createState() => _PortionSheetState();
}

class _PortionSheetState extends State<_PortionSheet> {
  final _name = TextEditingController();
  final _size = TextEditingController();
  final _notes = TextEditingController();
  String _soil = '';
  String _purpose = '';
  String? _err;

  static const _soils = ['Loam', 'Clay', 'Sandy', 'Silty', 'Peaty', 'Chalky', 'Other'];
  static const _uses = ['Crops', 'Grazing', 'Fallow', 'Orchard', 'Greenhouse', 'Storage', 'Other'];

  @override
  void dispose() {
    _name.dispose();
    _size.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    final size = double.tryParse(_size.text.trim());
    if (name.isEmpty || size == null || size <= 0) {
      setState(() => _err = 'Enter a name and a size greater than zero.');
      return;
    }
    if (widget.maxAvailable != null && size > widget.maxAvailable! + 0.0001) {
      setState(() => _err = 'Only ${_fmt(widget.maxAvailable!)} ${widget.unit} available.');
      return;
    }
    Navigator.pop(context, {
      'name': name,
      'total_size': size,
      if (_soil.isNotEmpty) 'soil_type': _soil,
      if (_purpose.isNotEmpty) 'purpose': _purpose,
      if (_notes.text.trim().isNotEmpty) 'additional_notes': _notes.text.trim(),
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
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 42, height: 4, decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(99)))),
              const SizedBox(height: 14),
              const Text('Add land portion',
                  style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 19, color: AppColors.inkWarm)),
              if (widget.maxAvailable != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('${_fmt(widget.maxAvailable!)} ${widget.unit} available',
                      style: const TextStyle(fontFamily: 'Inter', fontSize: 12.5, color: AppColors.slate500)),
                ),
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
              _field(_name, 'Portion name (e.g. North Field)'),
              const SizedBox(height: 10),
              _field(_size, 'Size in ${widget.unit}', number: true),
              const SizedBox(height: 12),
              _chips('Soil type', _soils, _soil, (v) => setState(() => _soil = v)),
              const SizedBox(height: 12),
              _chips('Current use', _uses, _purpose, (v) => setState(() => _purpose = v)),
              const SizedBox(height: 12),
              _field(_notes, 'Notes (optional)', lines: 2),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: _submit,
                child: Container(
                  height: 50,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(gradient: AppColors.emeraldGrad, borderRadius: BorderRadius.circular(13)),
                  child: const Text('Save portion',
                      style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, color: Colors.white, fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
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

  Widget _chips(String label, List<String> opts, String sel, ValueChanged<String> onTap) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 6),
          child: Text(label,
              style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 12.5, color: AppColors.slate700)),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: opts.map((o) {
            final on = sel == o;
            return GestureDetector(
              onTap: () => onTap(o),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: on ? AppColors.g600 : Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: on ? AppColors.g600 : AppColors.line),
                ),
                child: Text(o,
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

// ---------------------------------------------------------------------------
class _TransferSheet extends StatefulWidget {
  final Map<String, dynamic> from;
  final List<Map<String, dynamic>> others;
  final String unit;
  final double Function(Map<String, dynamic>) sizeOf;
  const _TransferSheet({required this.from, required this.others, required this.unit, required this.sizeOf});
  @override
  State<_TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends State<_TransferSheet> {
  final _amount = TextEditingController();
  int? _toId;
  String? _err;

  @override
  void initState() {
    super.initState();
    _toId = (pickNum(widget.others.first, ['id']) ?? 0).toInt();
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _submit() {
    final fromSize = widget.sizeOf(widget.from);
    final amt = double.tryParse(_amount.text.trim());
    if (_toId == null) {
      setState(() => _err = 'Choose a portion to transfer to.');
      return;
    }
    if (amt == null || amt <= 0) {
      setState(() => _err = 'Enter an amount greater than zero.');
      return;
    }
    if (amt > fromSize + 0.0001) {
      setState(() => _err = 'You can only move up to ${_fmt(fromSize)} ${widget.unit}.');
      return;
    }
    Navigator.pop(context, {'to': _toId!, 'amount': amt});
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final fromName = pickString(widget.from, ['name']) ?? 'Portion';
    final fromSize = widget.sizeOf(widget.from);
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: const BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 42, height: 4, decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(99)))),
              const SizedBox(height: 14),
              const Text('Transfer land',
                  style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 19, color: AppColors.inkWarm)),
              const SizedBox(height: 4),
              Text('Move area from "$fromName" (${_fmt(fromSize)} ${widget.unit}) into another portion.',
                  style: const TextStyle(fontFamily: 'Inter', fontSize: 12.5, color: AppColors.slate500)),
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
              const Padding(
                padding: EdgeInsets.only(left: 2, bottom: 6),
                child: Text('Transfer to',
                    style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 12.5, color: AppColors.slate700)),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: widget.others.map((p) {
                  final id = (pickNum(p, ['id']) ?? 0).toInt();
                  final on = _toId == id;
                  final label = '${pickString(p, ['name']) ?? 'Portion'} (${_fmt(widget.sizeOf(p))} ${widget.unit})';
                  return GestureDetector(
                    onTap: () => setState(() => _toId = id),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        color: on ? AppColors.g600 : Colors.white,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: on ? AppColors.g600 : AppColors.line),
                      ),
                      child: Text(label,
                          style: TextStyle(
                              fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 12.5, color: on ? Colors.white : AppColors.slate700)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  hintText: 'Amount in ${widget.unit}',
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: AppColors.line)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: AppColors.line)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: AppColors.green)),
                ),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: _submit,
                child: Container(
                  height: 50,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(gradient: AppColors.emeraldGrad, borderRadius: BorderRadius.circular(13)),
                  child: const Text('Transfer',
                      style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, color: Colors.white, fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
