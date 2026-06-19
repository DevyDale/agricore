import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/network/dio_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/json_utils.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/state_views.dart';
import 'farm_chrome.dart';

const String _cropsPath = '/crops/';
const String _fieldsPath = '/fields/';

class CropsManagementScreen extends StatefulWidget {
  final Map<String, dynamic> farm;
  const CropsManagementScreen({super.key, required this.farm});
  @override
  State<CropsManagementScreen> createState() => _CropsManagementScreenState();
}

class _CropsManagementScreenState extends State<CropsManagementScreen> {
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _crops = [];
  List<Map<String, dynamic>> _fields = [];
  bool _loading = true;
  String? _error;
  String _query = '';
  String _status = 'all';

  int get _farmId => (pickNum(widget.farm, ['id']) ?? 0).toInt();

  static const _statusTabs = [
    ['all', 'All'],
    ['growing', 'Growing'],
    ['planned', 'Planned'],
    ['harvested', 'Harvested'],
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
      final results = await Future.wait([
        dio.get(_fieldsPath, queryParameters: {'farm': _farmId}),
        dio.get(_cropsPath),
      ]);
      if (!mounted) return;
      final fields = _asList(results[0].data);
      final fieldIds = fields.map((f) => (pickNum(f, ['id']) ?? -1).toInt()).toSet();
      final crops = _asList(results[1].data).where((c) {
        final fid = (pickNum(c, ['field']) ?? -2).toInt();
        return fieldIds.contains(fid);
      }).toList();
      setState(() {
        _fields = fields;
        _crops = crops;
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

  String _fieldName(int id) {
    for (final f in _fields) {
      if ((pickNum(f, ['id']) ?? -1).toInt() == id) return pickString(f, ['name']) ?? 'Portion';
    }
    return 'Portion';
  }

  List<Map<String, dynamic>> get _view {
    return _crops.where((c) {
      final name = '${pickString(c, ['name']) ?? ''} ${pickString(c, ['variety']) ?? ''}'.toLowerCase();
      final st = (pickString(c, ['status']) ?? '').toLowerCase();
      final okQ = _query.isEmpty || name.contains(_query.toLowerCase());
      final okS = _status == 'all' || st.contains(_status);
      return okQ && okS;
    }).toList();
  }

  Future<void> _openForm({Map<String, dynamic>? existing}) async {
    if (_fields.isEmpty) {
      showToast(context, 'Add a land portion first (Land Management).', success: false);
      return;
    }
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CropSheet(fields: _fields, existing: existing),
    );
    if (result == null) return;
    try {
      final dio = context.read<DioClient>().dio;
      if (existing != null) {
        await dio.patch('$_cropsPath${pickNum(existing, ['id'])?.toInt()}/', data: result);
      } else {
        await dio.post(_cropsPath, data: result);
      }
      if (!mounted) return;
      showToast(context, existing != null ? 'Crop updated' : 'Crop added');
      _load();
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), success: false);
    }
  }

  Future<void> _delete(Map<String, dynamic> c) async {
    final name = pickString(c, ['name']) ?? 'this crop';
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete crop?'),
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
    try {
      final dio = context.read<DioClient>().dio;
      await dio.delete('$_cropsPath${pickNum(c, ['id'])?.toInt()}/');
      if (!mounted) return;
      showToast(context, 'Crop deleted');
      _load();
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), success: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final farmName = pickString(widget.farm, ['name', 'farm_name', 'title']) ?? 'Farm';
    int countWhere(bool Function(String) test) =>
        _crops.where((c) => test((pickString(c, ['status']) ?? '').toLowerCase())).length;
    final growing = countWhere((s) => s.contains('grow') || s.contains('active'));
    final harvested = countWhere((s) => s.contains('harvest'));
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            FarmHeroBar(title: 'Crop Management', subtitle: farmName),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Row(children: [
                  Expanded(child: FarmStat(icon: Icons.spa_rounded, value: _crops.length.toDouble(), label: 'Crops', c1: const Color(0xFF10B981), c2: const Color(0xFF047857))),
                  const SizedBox(width: 10),
                  Expanded(child: FarmStat(icon: Icons.eco_rounded, value: growing.toDouble(), label: 'Growing', c1: const Color(0xFF6AA83A), c2: const Color(0xFF4F8A2F))),
                  const SizedBox(width: 10),
                  Expanded(child: FarmStat(icon: Icons.agriculture_rounded, value: harvested.toDouble(), label: 'Harvested', c1: const Color(0xFFC39A48), c2: const Color(0xFFA9772E))),
                ]),
              ),
            ),
            SliverToBoxAdapter(child: _header()),
            if (_loading)
              const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.only(top: 36), child: LoadingView()))
            else if (_error != null)
              SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.only(top: 28), child: ErrorView(message: _error!, onRetry: _load)))
            else if (_view.isEmpty)
              const SliverToBoxAdapter(
                  child: Padding(
                      padding: EdgeInsets.only(top: 24),
                      child: EmptyView(text: 'No crops yet. Tap "Add crop" to start a cycle.', icon: Icons.spa_outlined)))
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) {
                      final c = _view[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: FarmRise(
                          index: i,
                          child: _CropCard(
                            crop: c,
                            fieldName: _fieldName((pickNum(c, ['field']) ?? -1).toInt()),
                            onEdit: () => _openForm(existing: c),
                            onDelete: () => _delete(c),
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

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Crops',
                    style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.inkWarm)),
              ),
              GestureDetector(
                onTap: () => _openForm(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(gradient: AppColors.emeraldGrad, borderRadius: BorderRadius.circular(12)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.add_rounded, color: Colors.white, size: 16),
                    SizedBox(width: 5),
                    Text('Add crop', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 12.5, color: Colors.white)),
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
                hintText: 'Search crops…',
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
              children: _statusTabs.map((t) {
                final on = t[0] == _status;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _status = t[0]),
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

class _CropCard extends StatelessWidget {
  final Map<String, dynamic> crop;
  final String fieldName;
  final VoidCallback onEdit, onDelete;
  const _CropCard({required this.crop, required this.fieldName, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final c = crop;
    final name = pickString(c, ['name']) ?? 'Crop';
    final variety = pickString(c, ['variety']);
    final status = pickString(c, ['status']) ?? '';
    final planted = pickString(c, ['planting_month_year']);
    final harvest = pickString(c, ['expected_harvest_month_year']);
    final yieldEst = pickNum(c, ['yield_estimate']);
    final yieldUnit = pickString(c, ['yield_unit']) ?? '';

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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.inkWarm)),
                    if (variety != null && variety.isNotEmpty)
                      Text(variety,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontFamily: 'Inter', fontSize: 11.5, color: AppColors.slate500)),
                  ],
                ),
              ),
              if (status.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(color: const Color(0xFFE7F4EC), borderRadius: BorderRadius.circular(999)),
                  child: Text(status,
                      style: const TextStyle(fontFamily: 'Inter', fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF0F7A4B))),
                ),
            ],
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              _meta(Icons.place_outlined, fieldName),
              if (planted != null && planted.isNotEmpty) _meta(Icons.event_outlined, 'Planted $planted'),
              if (harvest != null && harvest.isNotEmpty) _meta(Icons.agriculture_outlined, 'Harvest $harvest'),
              if (yieldEst != null) _meta(Icons.scale_outlined, 'Yield ${yieldEst % 1 == 0 ? yieldEst.toInt() : yieldEst} $yieldUnit'),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _iconBtn(Icons.edit_outlined, onEdit, 'Edit'),
              const SizedBox(width: 6),
              _iconBtn(Icons.delete_outline_rounded, onDelete, 'Delete', danger: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _meta(IconData icon, String text) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: AppColors.slate500),
      const SizedBox(width: 4),
      Text(text, style: const TextStyle(fontFamily: 'Inter', fontSize: 11.5, color: AppColors.slate600)),
    ]);
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap, String tip, {bool danger = false}) {
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(9), color: Colors.white),
          child: Icon(icon, size: 17, color: danger ? const Color(0xFFDC2626) : AppColors.slate600),
        ),
      ),
    );
  }
}

class _CropSheet extends StatefulWidget {
  final List<Map<String, dynamic>> fields;
  final Map<String, dynamic>? existing;
  const _CropSheet({required this.fields, this.existing});
  @override
  State<_CropSheet> createState() => _CropSheetState();
}

class _CropSheetState extends State<_CropSheet> {
  late final _name = TextEditingController(text: pickString(widget.existing ?? {}, ['name']) ?? '');
  late final _variety = TextEditingController(text: pickString(widget.existing ?? {}, ['variety']) ?? '');
  late final _seed = TextEditingController(text: pickString(widget.existing ?? {}, ['seed_source']) ?? '');
  late final _planted = TextEditingController(text: pickString(widget.existing ?? {}, ['planting_month_year']) ?? '');
  late final _harvest = TextEditingController(text: pickString(widget.existing ?? {}, ['expected_harvest_month_year']) ?? '');
  late final _yield = TextEditingController(text: (pickNum(widget.existing ?? {}, ['yield_estimate'])?.toString()) ?? '');
  late final _yieldUnit = TextEditingController(text: pickString(widget.existing ?? {}, ['yield_unit']) ?? '');
  late final _notes = TextEditingController(text: pickString(widget.existing ?? {}, ['additional_notes']) ?? '');
  late int? _fieldId = (pickNum(widget.existing ?? {}, ['field'])?.toInt()) ?? (widget.fields.isNotEmpty ? (pickNum(widget.fields.first, ['id'])?.toInt()) : null);
  late String _status = pickString(widget.existing ?? {}, ['status']) ?? 'Growing';
  String? _err;

  static const _statuses = ['Growing', 'Planned', 'Harvested', 'Failed'];

  @override
  void dispose() {
    for (final c in [_name, _variety, _seed, _planted, _harvest, _yield, _yieldUnit, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    final variety = _variety.text.trim();
    final seed = _seed.text.trim();
    final planted = _planted.text.trim();
    final harvest = _harvest.text.trim();
    if (_fieldId == null || name.isEmpty || variety.isEmpty || seed.isEmpty || planted.isEmpty || harvest.isEmpty) {
      setState(() => _err = 'Fill portion, name, variety, seed source, planting and expected harvest.');
      return;
    }
    final payload = <String, dynamic>{
      'field': _fieldId,
      'name': name,
      'variety': variety,
      'seed_source': seed,
      'planting_month_year': planted,
      'expected_harvest_month_year': harvest,
      'status': _status,
      'yield_unit': _yieldUnit.text.trim(),
      'additional_notes': _notes.text.trim(),
    };
    final y = double.tryParse(_yield.text.trim());
    if (y != null) payload['yield_estimate'] = y;
    Navigator.pop(context, payload);
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
              Text(widget.existing != null ? 'Edit crop cycle' : 'Start crop cycle',
                  style: const TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 19, color: AppColors.inkWarm)),
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
              _chips('Land portion', widget.fields.map((f) => MapEntry((pickNum(f, ['id']) ?? 0).toInt(), pickString(f, ['name']) ?? 'Portion')).toList(), _fieldId, (v) => setState(() => _fieldId = v)),
              const SizedBox(height: 12),
              _field(_name, 'Crop name (e.g. Maize)'),
              const SizedBox(height: 10),
              _field(_variety, 'Variety (e.g. Longe 5)'),
              const SizedBox(height: 10),
              _field(_seed, 'Seed source (e.g. Agrodealer)'),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _field(_planted, 'Planted (e.g. 2026-03)')),
                const SizedBox(width: 10),
                Expanded(child: _field(_harvest, 'Harvest (e.g. 2026-07)')),
              ]),
              const SizedBox(height: 12),
              _statusChips(),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _field(_yield, 'Yield estimate', number: true)),
                const SizedBox(width: 10),
                Expanded(child: _field(_yieldUnit, 'Yield unit (e.g. kg)')),
              ]),
              const SizedBox(height: 10),
              _field(_notes, 'Notes (optional)', lines: 2),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: _submit,
                child: Container(
                  height: 50,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(gradient: AppColors.emeraldGrad, borderRadius: BorderRadius.circular(13)),
                  child: Text(widget.existing != null ? 'Update crop' : 'Save crop',
                      style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, color: Colors.white, fontSize: 15)),
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

  Widget _statusChips() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 2, bottom: 6),
          child: Text('Status', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 12.5, color: AppColors.slate700)),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _statuses.map((s) {
            final on = _status == s;
            return GestureDetector(
              onTap: () => setState(() => _status = s),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: on ? AppColors.g600 : Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: on ? AppColors.g600 : AppColors.line),
                ),
                child: Text(s, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 12.5, color: on ? Colors.white : AppColors.slate700)),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _chips(String label, List<MapEntry<int, String>> opts, int? sel, ValueChanged<int> onTap) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 6),
          child: Text(label, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 12.5, color: AppColors.slate700)),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: opts.map((o) {
            final on = sel == o.key;
            return GestureDetector(
              onTap: () => onTap(o.key),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: on ? AppColors.g600 : Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: on ? AppColors.g600 : AppColors.line),
                ),
                child: Text(o.value, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 12.5, color: on ? Colors.white : AppColors.slate700)),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
