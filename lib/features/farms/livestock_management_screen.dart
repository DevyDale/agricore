import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/dio_client.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/json_utils.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/state_views.dart';
import 'farm_chrome.dart';

const String _fieldsPath = '/fields/';
const String _unitsPath = '/livestock-units/';
const String _animalsPath = '/animals/';

class LivestockManagementScreen extends StatefulWidget {
  final Map<String, dynamic> farm;
  const LivestockManagementScreen({super.key, required this.farm});
  @override
  State<LivestockManagementScreen> createState() => _LivestockManagementScreenState();
}

class _LivestockManagementScreenState extends State<LivestockManagementScreen> {
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _fields = [];
  List<Map<String, dynamic>> _units = [];
  List<Map<String, dynamic>> _animals = [];
  bool _loading = true;
  String? _error;
  String _query = '';
  String _status = 'all';
  String _sex = 'all';

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
        dio.get(_unitsPath),
        dio.get(_animalsPath),
      ]);
      if (!mounted) return;
      final fields = _asList(results[0].data);
      final fieldIds = fields.map((f) => (pickNum(f, ['id']) ?? -1).toInt()).toSet();
      final units = _asList(results[1].data)
          .where((u) => fieldIds.contains((pickNum(u, ['field']) ?? -2).toInt()))
          .toList();
      final unitIds = units.map((u) => (pickNum(u, ['id']) ?? -1).toInt()).toSet();
      final animals = _asList(results[2].data)
          .where((a) => unitIds.contains((pickNum(a, ['livestock_unit']) ?? -2).toInt()))
          .toList();
      setState(() {
        _fields = fields;
        _units = units;
        _animals = animals;
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

  String _unitName(int id) {
    for (final u in _units) {
      if ((pickNum(u, ['id']) ?? -1).toInt() == id) return pickString(u, ['unit_name']) ?? 'Unit';
    }
    return 'Unit';
  }

  int _animalsInUnit(int unitId) =>
      _animals.where((a) => (pickNum(a, ['livestock_unit']) ?? -1).toInt() == unitId).length;

  List<Map<String, dynamic>> get _view {
    return _animals.where((a) {
      final blob = '${pickString(a, ['name']) ?? ''} ${pickString(a, ['tag_id']) ?? ''} ${pickString(a, ['breed']) ?? ''}'.toLowerCase();
      final st = (pickString(a, ['status']) ?? '').toLowerCase();
      final sx = (pickString(a, ['sex']) ?? '').toLowerCase();
      final okQ = _query.isEmpty || blob.contains(_query.toLowerCase());
      final okSt = _status == 'all' || st == _status;
      final okSx = _sex == 'all' || sx == _sex;
      return okQ && okSt && okSx;
    }).toList();
  }

  Future<void> _unitForm({Map<String, dynamic>? existing}) async {
    if (_fields.isEmpty) {
      showToast(context, 'Add a land portion first (Land Management).', success: false);
      return;
    }
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _UnitSheet(fields: _fields, existing: existing),
    );
    if (result == null) return;
    if (!mounted) return;
    try {
      final dio = context.read<DioClient>().dio;
      if (existing != null) {
        await dio.patch('$_unitsPath${pickNum(existing, ['id'])?.toInt()}/', data: result);
      } else {
        await dio.post(_unitsPath, data: result);
      }
      if (!mounted) return;
      showToast(context, existing != null ? 'Unit updated' : 'Unit added');
      _load();
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), success: false);
    }
  }

  Future<void> _animalForm({Map<String, dynamic>? existing}) async {
    if (_units.isEmpty) {
      showToast(context, 'Add a livestock unit first.', success: false);
      return;
    }
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AnimalSheet(units: _units, existing: existing),
    );
    if (result == null) return;
    if (!mounted) return;
    try {
      final dio = context.read<DioClient>().dio;
      if (existing != null) {
        await dio.patch('$_animalsPath${pickNum(existing, ['id'])?.toInt()}/', data: result);
      } else {
        await dio.post(_animalsPath, data: result);
      }
      if (!mounted) return;
      showToast(context, existing != null ? 'Animal updated' : 'Animal added');
      _load();
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), success: false);
    }
  }

  Future<void> _delete(String path, Map<String, dynamic> obj, String label) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete $label?'),
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
      await dio.delete('$path${pickNum(obj, ['id'])?.toInt()}/');
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
    final active = _animals.where((a) {
      final s = (pickString(a, ['status']) ?? '').toLowerCase();
      return s == 'active' || s == 'healthy';
    }).length;
    final female = _animals.where((a) => (pickString(a, ['sex']) ?? '').toLowerCase() == 'female').length;
    final male = _animals.where((a) => (pickString(a, ['sex']) ?? '').toLowerCase() == 'male').length;

    return Scaffold(
      backgroundColor: AppColors.cream,
      body: MaxWidthBody(
        child: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            FarmHeroBar(title: 'Livestock Management', subtitle: farmName),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Row(children: [
                  Expanded(child: FarmStat(icon: Icons.pets_rounded, value: _animals.length.toDouble(), label: 'Animals', c1: const Color(0xFF10B981), c2: const Color(0xFF047857))),
                  const SizedBox(width: 8),
                  Expanded(child: FarmStat(icon: Icons.favorite_rounded, value: active.toDouble(), label: 'Active', c1: const Color(0xFF0D9488), c2: const Color(0xFF0F766E))),
                  const SizedBox(width: 8),
                  Expanded(child: FarmStat(icon: Icons.female_rounded, value: female.toDouble(), label: 'Female', c1: const Color(0xFFDB6FA0), c2: const Color(0xFFB23A78))),
                  const SizedBox(width: 8),
                  Expanded(child: FarmStat(icon: Icons.male_rounded, value: male.toDouble(), label: 'Male', c1: const Color(0xFF6366F1), c2: const Color(0xFF4338CA))),
                ]),
              ),
            ),
            if (_loading)
              const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.only(top: 36), child: LoadingView()))
            else if (_error != null)
              SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.only(top: 28), child: ErrorView(message: _error!, onRetry: _load)))
            else ...[
              SliverToBoxAdapter(child: _unitsBlock()),
              SliverToBoxAdapter(child: _animalsHeader()),
              if (_view.isEmpty)
                const SliverToBoxAdapter(
                    child: Padding(
                        padding: EdgeInsets.only(top: 18),
                        child: EmptyView(text: 'No animals yet. Tap "Add animal" to register one.', icon: Icons.pets_outlined)))
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) {
                        final a = _view[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: FarmRise(
                            index: i,
                            child: _AnimalCard(
                              animal: a,
                              unitName: _unitName((pickNum(a, ['livestock_unit']) ?? -1).toInt()),
                              onEdit: () => _animalForm(existing: a),
                              onDelete: () => _delete(_animalsPath, a, 'animal'),
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

  Widget _unitsBlock() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Livestock units',
                    style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.inkWarm)),
              ),
              GestureDetector(
                onTap: () => _unitForm(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                      color: Colors.white, borderRadius: BorderRadius.circular(11), border: Border.all(color: AppColors.line)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.add_rounded, color: AppColors.g700, size: 15),
                    SizedBox(width: 4),
                    Text('Add unit', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.g700)),
                  ]),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_units.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
              child: const Text('No units yet. A unit is a group (e.g. "Dairy herd"); animals belong to a unit.',
                  style: TextStyle(fontFamily: 'Inter', fontSize: 12.5, color: AppColors.slate500)),
            )
          else
            ..._units.asMap().entries.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: FarmRise(index: e.key, child: _UnitCard(
                    unit: e.value,
                    animalCount: _animalsInUnit((pickNum(e.value, ['id']) ?? -1).toInt()),
                    onEdit: () => _unitForm(existing: e.value),
                    onDelete: () => _delete(_unitsPath, e.value, 'unit'),
                  )),
                )),
        ],
      ),
    );
  }

  Widget _animalsHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Animals',
                    style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.inkWarm)),
              ),
              GestureDetector(
                onTap: () => _animalForm(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(gradient: AppColors.emeraldGrad, borderRadius: BorderRadius.circular(12)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.add_rounded, color: Colors.white, size: 16),
                    SizedBox(width: 5),
                    Text('Add animal', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 12.5, color: Colors.white)),
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
                hintText: 'Search by name, tag or breed…',
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
                ..._chipGroup(const [['all', 'All'], ['active', 'Active'], ['sold', 'Sold'], ['deceased', 'Deceased']], _status, (v) => setState(() => _status = v)),
                Container(width: 1, height: 20, margin: const EdgeInsets.symmetric(horizontal: 6), color: AppColors.line),
                ..._chipGroup(const [['all', 'Any sex'], ['female', 'Female'], ['male', 'Male']], _sex, (v) => setState(() => _sex = v)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _chipGroup(List<List<String>> opts, String sel, ValueChanged<String> onTap) {
    return opts.map((t) {
      final on = t[0] == sel;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: () => onTap(t[0]),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: on ? AppColors.g600 : Colors.white,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: on ? AppColors.g600 : AppColors.line),
            ),
            child: Text(t[1],
                style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13, color: on ? Colors.white : AppColors.slate700)),
          ),
        ),
      );
    }).toList();
  }
}

// ---------------------------------------------------------------------------
class _UnitCard extends StatelessWidget {
  final Map<String, dynamic> unit;
  final int animalCount;
  final VoidCallback onEdit, onDelete;
  const _UnitCard({required this.unit, required this.animalCount, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final name = pickString(unit, ['unit_name']) ?? 'Unit';
    final type = pickString(unit, ['animal_type']) ?? '';
    final breed = pickString(unit, ['breed']) ?? '';
    final qty = pickNum(unit, ['quantity']);
    final sub = [type, breed].where((x) => x.isNotEmpty).join(' · ');
    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line)),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      child: Row(
        children: [
          Container(
            width: 40, height: 40, alignment: Alignment.center,
            decoration: BoxDecoration(color: const Color(0xFFEAF7EC), borderRadius: BorderRadius.circular(11)),
            child: const Icon(Icons.workspaces_outline, color: Color(0xFF0F7A4B), size: 19),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.inkWarm)),
                Text('${sub.isEmpty ? '' : '$sub · '}$animalCount tracked${qty != null ? ' / $qty' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'Inter', fontSize: 11.5, color: AppColors.slate500)),
              ],
            ),
          ),
          IconButton(onPressed: onEdit, icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.slate600), visualDensity: VisualDensity.compact),
          IconButton(onPressed: onDelete, icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFDC2626)), visualDensity: VisualDensity.compact),
        ],
      ),
    );
  }
}

class _AnimalCard extends StatelessWidget {
  final Map<String, dynamic> animal;
  final String unitName;
  final VoidCallback onEdit, onDelete;
  const _AnimalCard({required this.animal, required this.unitName, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final a = animal;
    final tag = pickString(a, ['tag_id']) ?? '';
    final name = pickString(a, ['name']);
    final sex = (pickString(a, ['sex']) ?? '').toLowerCase();
    final age = pickString(a, ['age_group']);
    final breed = pickString(a, ['breed']);
    final status = (pickString(a, ['status']) ?? '').toLowerCase();
    final isFemale = sex == 'female';

    Color stBg, stFg;
    if (status == 'active' || status == 'healthy') {
      stBg = const Color(0xFFDCFCE7); stFg = const Color(0xFF166534);
    } else if (status == 'sold') {
      stBg = const Color(0xFFDBEAFE); stFg = const Color(0xFF1E40AF);
    } else if (status == 'deceased') {
      stBg = const Color(0xFFFEE2E2); stFg = const Color(0xFF991B1B);
    } else {
      stBg = const Color(0xFFF4EFE3); stFg = const Color(0xFF5B6B5F);
    }

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
                width: 34, height: 34, alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: isFemale ? const Color(0xFFFCE7F3) : const Color(0xFFE0E7FF),
                    borderRadius: BorderRadius.circular(9)),
                child: Icon(isFemale ? Icons.female_rounded : Icons.male_rounded,
                    size: 18, color: isFemale ? const Color(0xFFB23A78) : const Color(0xFF4338CA)),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name != null && name.isNotEmpty ? name : (tag.isNotEmpty ? tag : 'Animal'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.inkWarm)),
                    Text([if (tag.isNotEmpty) 'Tag $tag', if (breed != null && breed.isNotEmpty) breed, if (age != null && age.isNotEmpty) age].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontFamily: 'Inter', fontSize: 11.5, color: AppColors.slate500)),
                  ],
                ),
              ),
              if (status.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(color: stBg, borderRadius: BorderRadius.circular(999)),
                  child: Text(status[0].toUpperCase() + status.substring(1),
                      style: TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w800, color: stFg)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.workspaces_outline, size: 13, color: AppColors.slate500),
              const SizedBox(width: 4),
              Expanded(
                child: Text(unitName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'Inter', fontSize: 11.5, color: AppColors.slate600)),
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
class _UnitSheet extends StatefulWidget {
  final List<Map<String, dynamic>> fields;
  final Map<String, dynamic>? existing;
  const _UnitSheet({required this.fields, this.existing});
  @override
  State<_UnitSheet> createState() => _UnitSheetState();
}

class _UnitSheetState extends State<_UnitSheet> {
  late final _name = TextEditingController(text: pickString(widget.existing ?? {}, ['unit_name']) ?? '');
  late final _type = TextEditingController(text: pickString(widget.existing ?? {}, ['animal_type']) ?? '');
  late final _breed = TextEditingController(text: pickString(widget.existing ?? {}, ['breed']) ?? '');
  late final _qty = TextEditingController(text: (pickNum(widget.existing ?? {}, ['quantity'])?.toInt().toString()) ?? '');
  late final _notes = TextEditingController(text: pickString(widget.existing ?? {}, ['additional_notes']) ?? '');
  late int? _fieldId = (pickNum(widget.existing ?? {}, ['field'])?.toInt()) ?? (widget.fields.isNotEmpty ? (pickNum(widget.fields.first, ['id'])?.toInt()) : null);
  String? _err;

  @override
  void dispose() {
    for (final c in [_name, _type, _breed, _qty, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    final type = _type.text.trim();
    final breed = _breed.text.trim();
    final qty = int.tryParse(_qty.text.trim());
    if (_fieldId == null || name.isEmpty || type.isEmpty || breed.isEmpty || qty == null) {
      setState(() => _err = 'Fill portion, unit name, animal type, breed and quantity.');
      return;
    }
    Navigator.pop(context, {
      'field': _fieldId,
      'unit_name': name,
      'animal_type': type,
      'breed': breed,
      'quantity': qty,
      'additional_notes': _notes.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      title: widget.existing != null ? 'Edit unit' : 'Add livestock unit',
      error: _err,
      onSubmit: _submit,
      submitLabel: widget.existing != null ? 'Update unit' : 'Save unit',
      children: [
        _PickerChips(
          label: 'Land portion',
          options: widget.fields.map((f) => MapEntry((pickNum(f, ['id']) ?? 0).toInt(), pickString(f, ['name']) ?? 'Portion')).toList(),
          selected: _fieldId,
          onTap: (v) => setState(() => _fieldId = v),
        ),
        const SizedBox(height: 12),
        _SheetField(controller: _name, hint: 'Unit name (e.g. Dairy herd)'),
        const SizedBox(height: 10),
        _SheetField(controller: _type, hint: 'Animal type (e.g. Cattle, Goats)'),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _SheetField(controller: _breed, hint: 'Breed')),
          const SizedBox(width: 10),
          Expanded(child: _SheetField(controller: _qty, hint: 'Quantity', number: true)),
        ]),
        const SizedBox(height: 10),
        _SheetField(controller: _notes, hint: 'Notes (optional)', lines: 2),
      ],
    );
  }
}

class _AnimalSheet extends StatefulWidget {
  final List<Map<String, dynamic>> units;
  final Map<String, dynamic>? existing;
  const _AnimalSheet({required this.units, this.existing});
  @override
  State<_AnimalSheet> createState() => _AnimalSheetState();
}

class _AnimalSheetState extends State<_AnimalSheet> {
  late final _tag = TextEditingController(text: pickString(widget.existing ?? {}, ['tag_id']) ?? '');
  late final _name = TextEditingController(text: pickString(widget.existing ?? {}, ['name']) ?? '');
  late final _age = TextEditingController(text: pickString(widget.existing ?? {}, ['age_group']) ?? '');
  late final _breed = TextEditingController(text: pickString(widget.existing ?? {}, ['breed']) ?? '');
  late final _notes = TextEditingController(text: pickString(widget.existing ?? {}, ['additional_notes']) ?? '');
  late int? _unitId = (pickNum(widget.existing ?? {}, ['livestock_unit'])?.toInt()) ?? (widget.units.isNotEmpty ? (pickNum(widget.units.first, ['id'])?.toInt()) : null);
  late String _sex = (pickString(widget.existing ?? {}, ['sex']) ?? '').toLowerCase();
  late String _status = (pickString(widget.existing ?? {}, ['status']) ?? 'active').toLowerCase();
  String? _err;

  static const _statuses = ['active', 'sold', 'deceased'];

  @override
  void dispose() {
    for (final c in [_tag, _name, _age, _breed, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final tag = _tag.text.trim();
    final age = _age.text.trim();
    final breed = _breed.text.trim();
    if (_unitId == null || tag.isEmpty || _sex.isEmpty || age.isEmpty || breed.isEmpty) {
      setState(() => _err = 'Fill unit, tag, sex, age group and breed.');
      return;
    }
    Navigator.pop(context, {
      'livestock_unit': _unitId,
      'tag_id': tag,
      'name': _name.text.trim(),
      'sex': _sex,
      'age_group': age,
      'breed': breed,
      'status': _status,
      'additional_notes': _notes.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      title: widget.existing != null ? 'Edit animal' : 'Add animal',
      error: _err,
      onSubmit: _submit,
      submitLabel: widget.existing != null ? 'Update animal' : 'Save animal',
      children: [
        _PickerChips(
          label: 'Livestock unit',
          options: widget.units.map((u) => MapEntry((pickNum(u, ['id']) ?? 0).toInt(), pickString(u, ['unit_name']) ?? 'Unit')).toList(),
          selected: _unitId,
          onTap: (v) => setState(() => _unitId = v),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _SheetField(controller: _tag, hint: 'Tag / ID')),
          const SizedBox(width: 10),
          Expanded(child: _SheetField(controller: _name, hint: 'Name (optional)')),
        ]),
        const SizedBox(height: 12),
        _LabeledChips(
          label: 'Sex',
          options: const [['female', 'Female'], ['male', 'Male']],
          selected: _sex,
          onTap: (v) => setState(() => _sex = v),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _SheetField(controller: _age, hint: 'Age group (e.g. Adult)')),
          const SizedBox(width: 10),
          Expanded(child: _SheetField(controller: _breed, hint: 'Breed')),
        ]),
        const SizedBox(height: 12),
        _LabeledChips(
          label: 'Status',
          options: _statuses.map((s) => [s, s[0].toUpperCase() + s.substring(1)]).toList(),
          selected: _status,
          onTap: (v) => setState(() => _status = v),
        ),
        const SizedBox(height: 12),
        _SheetField(controller: _notes, hint: 'Notes (optional)', lines: 2),
      ],
    );
  }
}

// ---- small shared sheet pieces ----
class _SheetScaffold extends StatelessWidget {
  final String title;
  final String? error;
  final VoidCallback onSubmit;
  final String submitLabel;
  final List<Widget> children;
  const _SheetScaffold({required this.title, required this.error, required this.onSubmit, required this.submitLabel, required this.children});

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
                  decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFFCA5A5))),
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
  final bool number;
  final int lines;
  const _SheetField({required this.controller, required this.hint, this.number = false, this.lines = 1});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
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
