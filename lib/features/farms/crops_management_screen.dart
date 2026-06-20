import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/dio_client.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/json_utils.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/state_views.dart';
import 'farm_chrome.dart';

const String _cropsPath = '/crop-cycles/';
const String _fieldsPath = '/fields/';

String _two(int n) => n < 10 ? '0$n' : '$n';

({Color bg, Color fg}) _statusStyle(String s) {
  final d = s.toLowerCase();
  if (d.contains('grow') || d.contains('active')) return (bg: const Color(0xFFDCFCE7), fg: const Color(0xFF166534));
  if (d.contains('harvest')) return (bg: const Color(0xFFDBEAFE), fg: const Color(0xFF1E40AF));
  if (d.contains('plan')) return (bg: const Color(0xFFFEF3C7), fg: const Color(0xFF92400E));
  if (d.contains('fail') || d.contains('loss')) return (bg: const Color(0xFFFEE2E2), fg: const Color(0xFF991B1B));
  return (bg: const Color(0xFFF4EFE3), fg: const Color(0xFF5B6B5F));
}

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
  String _status = 'all'; // 'all' or a status keyword (grow/harvest/plan/fail)

  int get _farmId => (pickNum(widget.farm, ['id']) ?? 0).toInt();

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
      // The crop-cycles endpoint is owner-scoped (all the user's farms) and takes
      // no farm param, so we keep only cycles whose land portion belongs to THIS
      // farm by matching the serializer's read-only `field_name`.
      final names = fields
          .map((f) => (pickString(f, ['name']) ?? '').trim())
          .where((n) => n.isNotEmpty)
          .toSet();
      final crops = _asList(results[1].data)
          .where((c) => names.contains((pickString(c, ['field_name']) ?? '').trim()))
          .toList();
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

  int _countStatus(bool Function(String) test) =>
      _crops.where((c) => test((pickString(c, ['status']) ?? '').toLowerCase())).length;

  List<Map<String, dynamic>> get _view {
    final q = _query.trim().toLowerCase();
    final list = _crops.where((c) {
      final blob = '${pickString(c, ['crop_type']) ?? ''} ${pickString(c, ['variety']) ?? ''} '
              '${pickString(c, ['field_name']) ?? ''}'
          .toLowerCase();
      final okQ = q.isEmpty || blob.contains(q);
      final st = (pickString(c, ['status']) ?? '').toLowerCase();
      final okSt = _status == 'all' || st.contains(_status);
      return okQ && okSt;
    }).toList();
    list.sort((a, b) => (pickString(b, ['planting_date']) ?? '').compareTo(pickString(a, ['planting_date']) ?? ''));
    return list;
  }

  Future<void> _cropForm({Map<String, dynamic>? existing}) async {
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
    if (!mounted) return;
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete crop?'),
        content: const Text('This cannot be undone.'),
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
      await dio.delete('$_cropsPath${pickNum(c, ['id'])?.toInt()}/');
      if (!mounted) return;
      showToast(context, 'Deleted');
      _load();
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), success: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final farmName = pickString(widget.farm, ['name', 'farm_name', 'title']) ?? 'Farm';
    final growing = _countStatus((s) => s.contains('grow') || s.contains('active'));
    final harvested = _countStatus((s) => s.contains('harvest'));

    return Scaffold(
      backgroundColor: AppColors.cream,
      body: MaxWidthBody(
        child: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            FarmHeroBar(title: 'Crops', subtitle: farmName),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Row(children: [
                  Expanded(child: FarmStat(icon: Icons.eco_rounded, value: _crops.length.toDouble(), label: 'Cycles', c1: const Color(0xFF10B981), c2: const Color(0xFF047857))),
                  const SizedBox(width: 8),
                  Expanded(child: FarmStat(icon: Icons.grass_rounded, value: growing.toDouble(), label: 'Growing', c1: const Color(0xFF0D9488), c2: const Color(0xFF0F766E))),
                  const SizedBox(width: 8),
                  Expanded(child: FarmStat(icon: Icons.agriculture_rounded, value: harvested.toDouble(), label: 'Harvested', c1: const Color(0xFFC39A48), c2: const Color(0xFFA9772E))),
                ]),
              ),
            ),
            if (_loading)
              const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.only(top: 36), child: LoadingView()))
            else if (_error != null)
              SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.only(top: 28), child: ErrorView(message: _error!, onRetry: _load)))
            else ...[
              SliverToBoxAdapter(child: _header()),
              if (_view.isEmpty)
                const SliverToBoxAdapter(
                    child: Padding(
                        padding: EdgeInsets.only(top: 18),
                        child: EmptyView(text: 'No crops yet. Tap "Add crop" to start a cycle.', icon: Icons.eco_outlined)))
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
                              onEdit: () => _cropForm(existing: c),
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
          ],
        ),
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
                child: Text('Crop cycles',
                    style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.inkWarm)),
              ),
              GestureDetector(
                onTap: () => _cropForm(),
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
                hintText: 'Search by crop, variety or portion…',
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
              children: [
                _filterChip('all', 'All'),
                _filterChip('grow', 'Growing'),
                _filterChip('harvest', 'Harvested'),
                _filterChip('plan', 'Planned'),
                _filterChip('fail', 'Failed'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String value, String label) {
    final on = _status == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _status = value),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: on ? AppColors.g600 : Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: on ? AppColors.g600 : AppColors.line),
          ),
          child: Text(label,
              style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13, color: on ? Colors.white : AppColors.slate700)),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
class _CropCard extends StatelessWidget {
  final Map<String, dynamic> crop;
  final VoidCallback onEdit, onDelete;
  const _CropCard({required this.crop, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final c = crop;
    final type = pickString(c, ['crop_type']) ?? 'Crop';
    final variety = pickString(c, ['variety']) ?? '';
    final fieldName = pickString(c, ['field_name']) ?? '';
    final status = pickString(c, ['status']) ?? '';
    final planted = pickString(c, ['planting_date']) ?? '';
    final harvest = pickString(c, ['expected_harvest_date']) ?? '';
    final st = _statusStyle(status);
    final sub = [variety, fieldName].where((x) => x.isNotEmpty).join(' · ');

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 14, offset: const Offset(0, 6))],
      ),
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: const Color(0xFFEAF7EC), borderRadius: BorderRadius.circular(11)),
                child: const Icon(Icons.eco_rounded, color: Color(0xFF0F7A4B), size: 19),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(type,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.inkWarm)),
                    if (sub.isNotEmpty)
                      Text(sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontFamily: 'Inter', fontSize: 11.5, color: AppColors.slate500)),
                  ],
                ),
              ),
              if (status.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(color: st.bg, borderRadius: BorderRadius.circular(999)),
                  child: Text(status[0].toUpperCase() + status.substring(1),
                      style: TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w800, color: st.fg)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(Icons.spa_rounded, size: 13, color: AppColors.slate500),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(planted.isEmpty ? 'Planted —' : 'Planted $planted',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontFamily: 'Inter', fontSize: 11.5, color: AppColors.slate600)),
                    ),
                    if (harvest.isNotEmpty) ...[
                      const SizedBox(width: 12),
                      const Icon(Icons.event_available_rounded, size: 13, color: AppColors.slate500),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text('Harvest $harvest',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontFamily: 'Inter', fontSize: 11.5, color: AppColors.slate600)),
                      ),
                    ],
                  ],
                ),
              ),
              _iconBtn(Icons.edit_outlined, onEdit, 'Edit'),
              const SizedBox(width: 6),
              _iconBtn(Icons.delete_outline_rounded, onDelete, 'Delete', danger: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap, String tip, {bool danger = false}) {
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(9), color: Colors.white),
          child: Icon(icon, size: 16, color: danger ? const Color(0xFFDC2626) : AppColors.slate600),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
class _CropSheet extends StatefulWidget {
  final List<Map<String, dynamic>> fields;
  final Map<String, dynamic>? existing;
  const _CropSheet({required this.fields, this.existing});
  @override
  State<_CropSheet> createState() => _CropSheetState();
}

class _CropSheetState extends State<_CropSheet> {
  late int? _fieldId = _resolveField();
  late final _type = TextEditingController(text: pickString(widget.existing ?? {}, ['crop_type']) ?? '');
  late final _variety = TextEditingController(text: pickString(widget.existing ?? {}, ['variety']) ?? '');
  late final _notes = TextEditingController(text: pickString(widget.existing ?? {}, ['additional_notes']) ?? '');
  late DateTime _planting = DateTime.tryParse(pickString(widget.existing ?? {}, ['planting_date']) ?? '') ?? DateTime.now();
  late DateTime? _harvest = DateTime.tryParse(pickString(widget.existing ?? {}, ['expected_harvest_date']) ?? '');
  late String _status = pickString(widget.existing ?? {}, ['status']) ?? 'Growing';
  String? _err;

  // Existing cycles expose `field_name` (read-only), not the field id; resolve the
  // id back from this farm's fields so the land-portion chip pre-selects correctly.
  int? _resolveField() {
    final fn = pickString(widget.existing ?? {}, ['field_name']);
    if (fn != null && fn.isNotEmpty) {
      for (final f in widget.fields) {
        if ((pickString(f, ['name']) ?? '') == fn) return (pickNum(f, ['id']) ?? 0).toInt();
      }
    }
    return widget.fields.isNotEmpty ? (pickNum(widget.fields.first, ['id'])?.toInt()) : null;
  }

  @override
  void dispose() {
    for (final c in [_type, _variety, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  String _iso(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

  Future<void> _pickPlanting() async {
    final picked = await showDatePicker(context: context, initialDate: _planting, firstDate: DateTime(2015), lastDate: DateTime(2100));
    if (picked != null) setState(() => _planting = picked);
  }

  Future<void> _pickHarvest() async {
    final picked = await showDatePicker(context: context, initialDate: _harvest ?? _planting, firstDate: DateTime(2015), lastDate: DateTime(2100));
    if (picked != null) setState(() => _harvest = picked);
  }

  void _submit() {
    final type = _type.text.trim();
    if (_fieldId == null || type.isEmpty) {
      setState(() => _err = 'Choose a land portion and enter the crop type.');
      return;
    }
    Navigator.pop(context, {
      'field': _fieldId,
      'crop_type': type,
      'variety': _variety.text.trim(),
      'planting_date': _iso(_planting),
      'expected_harvest_date': _harvest != null ? _iso(_harvest!) : null,
      'status': _status,
      'additional_notes': _notes.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      title: widget.existing != null ? 'Edit crop' : 'Add crop',
      error: _err,
      onSubmit: _submit,
      submitLabel: widget.existing != null ? 'Update crop' : 'Save crop',
      children: [
        _PickerChips(
          label: 'Land portion',
          options: widget.fields.map((f) => MapEntry((pickNum(f, ['id']) ?? 0).toInt(), pickString(f, ['name']) ?? 'Portion')).toList(),
          selected: _fieldId,
          onTap: (v) => setState(() => _fieldId = v),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _SheetField(controller: _type, hint: 'Crop type (e.g. Maize)')),
          const SizedBox(width: 10),
          Expanded(child: _SheetField(controller: _variety, hint: 'Variety (optional)')),
        ]),
        const SizedBox(height: 12),
        _LabeledChips(
          label: 'Status',
          options: const [
            ['Planned', 'Planned'],
            ['Growing', 'Growing'],
            ['Harvested', 'Harvested'],
            ['Failed', 'Failed'],
          ],
          selected: _status,
          onTap: (v) => setState(() => _status = v),
        ),
        const SizedBox(height: 12),
        _dateRow('Planting date', _iso(_planting), _pickPlanting, null),
        const SizedBox(height: 10),
        _dateRow(
          'Expected harvest (optional)',
          _harvest != null ? _iso(_harvest!) : 'Not set',
          _pickHarvest,
          _harvest != null ? () => setState(() => _harvest = null) : null,
        ),
        const SizedBox(height: 10),
        _SheetField(controller: _notes, hint: 'Notes (optional)', lines: 2),
      ],
    );
  }

  Widget _dateRow(String label, String value, VoidCallback onTap, VoidCallback? onClear) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 6),
          child: Text(label, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 12.5, color: AppColors.slate700)),
        ),
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(11), border: Border.all(color: AppColors.line)),
            child: Row(children: [
              const Icon(Icons.event_rounded, size: 18, color: AppColors.slate600),
              const SizedBox(width: 10),
              Text(value, style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppColors.inkWarm)),
              const Spacer(),
              if (onClear != null)
                GestureDetector(onTap: onClear, child: const Icon(Icons.close_rounded, size: 18, color: AppColors.slate500))
              else
                const Icon(Icons.expand_more_rounded, size: 18, color: AppColors.slate500),
            ]),
          ),
        ),
      ],
    );
  }
}

// ---- small shared sheet pieces (private to this screen) ----
class _SheetScaffold extends StatelessWidget {
  final String title;
  final String? error;
  final VoidCallback onSubmit;
  final String submitLabel;
  final List<Widget> children;
  const _SheetScaffold(
      {required this.title, required this.error, required this.onSubmit, required this.submitLabel, required this.children});

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
              Text(title, style: const TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 19, color: AppColors.inkWarm)),
              const SizedBox(height: 14),
              if (error != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFFCA5A5))),
                  child: Text(error!, style: const TextStyle(fontFamily: 'Inter', fontSize: 12.5, color: Color(0xFFDC2626))),
                ),
                const SizedBox(height: 12),
              ],
              ...children,
              const SizedBox(height: 16),
              GestureDetector(
                onTap: onSubmit,
                child: Container(
                  height: 50,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(gradient: AppColors.emeraldGrad, borderRadius: BorderRadius.circular(13)),
                  child: Text(submitLabel, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, color: Colors.white, fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final int lines;
  const _SheetField({required this.controller, required this.hint, this.lines = 1});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: lines,
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
}

class _LabeledChips extends StatelessWidget {
  final String label;
  final List<List<String>> options;
  final String selected;
  final ValueChanged<String> onTap;
  const _LabeledChips({required this.label, required this.options, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
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
          children: options.map((o) {
            final on = selected == o[0];
            return GestureDetector(
              onTap: () => onTap(o[0]),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: on ? AppColors.g600 : Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: on ? AppColors.g600 : AppColors.line),
                ),
                child: Text(o[1], style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 12.5, color: on ? Colors.white : AppColors.slate700)),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _PickerChips extends StatelessWidget {
  final String label;
  final List<MapEntry<int, String>> options;
  final int? selected;
  final ValueChanged<int> onTap;
  const _PickerChips({required this.label, required this.options, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
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
          children: options.map((o) {
            final on = selected == o.key;
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
