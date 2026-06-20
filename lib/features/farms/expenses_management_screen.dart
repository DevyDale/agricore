import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/dio_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/json_utils.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/state_views.dart';
import 'farm_chrome.dart';

const String _expensesPath = '/expenses/';
const String _categoriesPath = '/expense-categories/';

String _two(int n) => n < 10 ? '0$n' : '$n';

String _ugx(num? v) {
  final n = (v ?? 0).round();
  final neg = n < 0;
  final str = n.abs().toString();
  final buf = StringBuffer();
  for (int i = 0; i < str.length; i++) {
    if (i > 0 && (str.length - i) % 3 == 0) buf.write(',');
    buf.write(str[i]);
  }
  return 'UGX ${neg ? '-' : ''}$buf';
}

/// Icon + colour per expense category (matched on the display name from the API).
({IconData icon, Color color}) _catStyle(String? displayName) {
  final d = (displayName ?? '').toLowerCase();
  if (d.contains('input')) return (icon: Icons.eco_rounded, color: const Color(0xFF10B981));
  if (d.contains('labor') || d.contains('labour')) return (icon: Icons.groups_rounded, color: const Color(0xFF6366F1));
  if (d.contains('equip')) return (icon: Icons.build_rounded, color: const Color(0xFFD97706));
  if (d.contains('util')) return (icon: Icons.bolt_rounded, color: const Color(0xFF0891B2));
  if (d.contains('over')) return (icon: Icons.category_rounded, color: const Color(0xFF7C3AED));
  return (icon: Icons.receipt_long_rounded, color: const Color(0xFF64748B));
}

class ExpensesManagementScreen extends StatefulWidget {
  final Map<String, dynamic> farm;
  const ExpensesManagementScreen({super.key, required this.farm});
  @override
  State<ExpensesManagementScreen> createState() => _ExpensesManagementScreenState();
}

class _ExpensesManagementScreenState extends State<ExpensesManagementScreen> {
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _expenses = [];
  List<Map<String, dynamic>> _categories = [];
  bool _loading = true;
  String? _error;
  String _query = '';
  String _categoryFilter = 'all'; // 'all' or a category id as a string

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
        dio.get(_expensesPath, queryParameters: {'farm': _farmId}),
        dio.get(_categoriesPath),
      ]);
      if (!mounted) return;
      setState(() {
        _expenses = _asList(results[0].data);
        _categories = _asList(results[1].data);
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

  double _expenseTotal(Map<String, dynamic> e) => (pickNum(e, ['total_cost']) ?? 0).toDouble();

  double get _total => _expenses.fold(0.0, (s, e) => s + _expenseTotal(e));

  double get _thisMonth {
    final now = DateTime.now();
    final pref = '${now.year}-${_two(now.month)}';
    return _expenses
        .where((e) => (pickString(e, ['date']) ?? '').startsWith(pref))
        .fold(0.0, (s, e) => s + _expenseTotal(e));
  }

  List<Map<String, dynamic>> get _view {
    final q = _query.trim().toLowerCase();
    final list = _expenses.where((e) {
      final blob = '${pickString(e, ['name']) ?? ''} ${pickString(e, ['vendor']) ?? ''} '
              '${pickString(e, ['notes']) ?? ''} ${pickString(e, ['category_name']) ?? ''}'
          .toLowerCase();
      final okQ = q.isEmpty || blob.contains(q);
      final catId = (pickNum(e, ['category']) ?? -1).toInt().toString();
      final okCat = _categoryFilter == 'all' || catId == _categoryFilter;
      return okQ && okCat;
    }).toList();
    // ISO dates sort lexically; newest first.
    list.sort((a, b) => (pickString(b, ['date']) ?? '').compareTo(pickString(a, ['date']) ?? ''));
    return list;
  }

  Future<void> _expenseForm({Map<String, dynamic>? existing}) async {
    if (_categories.isEmpty) {
      showToast(context, 'Expense categories not loaded yet. Pull to refresh.', success: false);
      return;
    }
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ExpenseSheet(categories: _categories, farmId: _farmId, existing: existing),
    );
    if (result == null) return;
    if (!mounted) return;
    try {
      final dio = context.read<DioClient>().dio;
      if (existing != null) {
        await dio.patch('$_expensesPath${pickNum(existing, ['id'])?.toInt()}/', data: result);
      } else {
        await dio.post(_expensesPath, data: result);
      }
      if (!mounted) return;
      showToast(context, existing != null ? 'Expense updated' : 'Expense added');
      _load();
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), success: false);
    }
  }

  Future<void> _delete(Map<String, dynamic> obj) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete expense?'),
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
      await dio.delete('$_expensesPath${pickNum(obj, ['id'])?.toInt()}/');
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

    return Scaffold(
      backgroundColor: AppColors.cream,
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            FarmHeroBar(title: 'Expenses', subtitle: farmName),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Row(children: [
                  Expanded(
                      child: _Stat(
                          icon: Icons.account_balance_wallet_rounded,
                          value: _ugx(_total),
                          label: 'Total spend',
                          c1: const Color(0xFF10B981),
                          c2: const Color(0xFF047857))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _Stat(
                          icon: Icons.calendar_month_rounded,
                          value: _ugx(_thisMonth),
                          label: 'This month',
                          c1: const Color(0xFF0D9488),
                          c2: const Color(0xFF0F766E))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _Stat(
                          icon: Icons.receipt_long_rounded,
                          value: '${_expenses.length}',
                          label: 'Records',
                          c1: const Color(0xFF6366F1),
                          c2: const Color(0xFF4338CA))),
                ]),
              ),
            ),
            if (_loading)
              const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.only(top: 36), child: LoadingView()))
            else if (_error != null)
              SliverToBoxAdapter(
                  child: Padding(padding: const EdgeInsets.only(top: 28), child: ErrorView(message: _error!, onRetry: _load)))
            else ...[
              SliverToBoxAdapter(child: _header()),
              if (_view.isEmpty)
                const SliverToBoxAdapter(
                    child: Padding(
                        padding: EdgeInsets.only(top: 18),
                        child: EmptyView(text: 'No expenses yet. Tap "Add expense" to record one.', icon: Icons.receipt_long_outlined)))
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) {
                        final e = _view[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: FarmRise(
                            index: i,
                            child: _ExpenseCard(
                              expense: e,
                              onEdit: () => _expenseForm(existing: e),
                              onDelete: () => _delete(e),
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
                child: Text('Expenses',
                    style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.inkWarm)),
              ),
              GestureDetector(
                onTap: () => _expenseForm(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(gradient: AppColors.emeraldGrad, borderRadius: BorderRadius.circular(12)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.add_rounded, color: Colors.white, size: 16),
                    SizedBox(width: 5),
                    Text('Add expense',
                        style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 12.5, color: Colors.white)),
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
                hintText: 'Search by name, vendor or note…',
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
                ..._categories.map((c) {
                  final id = (pickNum(c, ['id']) ?? 0).toInt().toString();
                  final label = pickString(c, ['display_name']) ?? pickString(c, ['name']) ?? 'Category';
                  return _filterChip(id, label);
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String value, String label) {
    final on = _categoryFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _categoryFilter = value),
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
class _Stat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color c1, c2;
  const _Stat({required this.icon, required this.value, required this.label, required this.c1, required this.c2});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(gradient: LinearGradient(colors: [c1, c2]), borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, size: 16, color: Colors.white),
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                maxLines: 1,
                style: const TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.inkWarm)),
          ),
          const SizedBox(height: 2),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppColors.slate500)),
        ],
      ),
    );
  }
}

class _ExpenseCard extends StatelessWidget {
  final Map<String, dynamic> expense;
  final VoidCallback onEdit, onDelete;
  const _ExpenseCard({required this.expense, required this.onEdit, required this.onDelete});

  List<Map<String, dynamic>> _payments() {
    final p = expense['payments'];
    if (p is List) return p.whereType<Map<String, dynamic>>().toList();
    return [];
  }

  @override
  Widget build(BuildContext context) {
    final e = expense;
    final name = pickString(e, ['name']) ?? 'Expense';
    final categoryName = pickString(e, ['category_name']) ?? '';
    final total = (pickNum(e, ['total_cost']) ?? 0).toDouble();
    final qty = pickNum(e, ['quantity']);
    final unit = pickString(e, ['unit']) ?? '';
    final unitCost = pickNum(e, ['unit_cost']);
    final date = pickString(e, ['date']) ?? '';
    final vendor = pickString(e, ['vendor']) ?? '';
    final style = _catStyle(categoryName);

    // Derive a payment badge from the nested payments already in the response.
    final paid = _payments()
        .where((p) => (pickString(p, ['status']) ?? '').toLowerCase() == 'paid')
        .fold(0.0, (s, p) => s + (pickNum(p, ['amount']) ?? 0).toDouble());
    Widget? badge;
    if (total > 0 && paid >= total) {
      badge = _PayBadge('Paid', const Color(0xFFDCFCE7), const Color(0xFF166534));
    } else if (paid > 0) {
      badge = _PayBadge('Part-paid', const Color(0xFFFEF3C7), const Color(0xFF92400E));
    }

    final breakdown = [
      if (qty != null) '${qty == qty.roundToDouble() ? qty.toInt() : qty} $unit'.trim(),
      if (unitCost != null) '@ ${_ugx(unitCost)}',
    ].where((x) => x.trim().isNotEmpty).join('  ');

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
                decoration: BoxDecoration(color: style.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(11)),
                child: Icon(style.icon, color: style.color, size: 19),
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
                    if (categoryName.isNotEmpty)
                      Text(categoryName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontFamily: 'Inter', fontSize: 11.5, fontWeight: FontWeight.w600, color: style.color)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_ugx(total),
                      style: const TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.inkWarm)),
                  if (badge != null) ...[const SizedBox(height: 4), badge],
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (breakdown.isNotEmpty) ...[
                const Icon(Icons.straighten_rounded, size: 13, color: AppColors.slate500),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(breakdown,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: 'Inter', fontSize: 11.5, color: AppColors.slate600)),
                ),
                const SizedBox(width: 12),
              ],
              const Icon(Icons.event_rounded, size: 13, color: AppColors.slate500),
              const SizedBox(width: 4),
              Text(date,
                  style: const TextStyle(fontFamily: 'Inter', fontSize: 11.5, color: AppColors.slate600)),
              const Spacer(),
              _iconBtn(Icons.edit_outlined, onEdit, 'Edit'),
              const SizedBox(width: 6),
              _iconBtn(Icons.delete_outline_rounded, onDelete, 'Delete', danger: true),
            ],
          ),
          if (vendor.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.storefront_rounded, size: 13, color: AppColors.slate500),
              const SizedBox(width: 4),
              Expanded(
                child: Text(vendor,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'Inter', fontSize: 11.5, color: AppColors.slate600)),
              ),
            ]),
          ],
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

class _PayBadge extends StatelessWidget {
  final String text;
  final Color bg, fg;
  const _PayBadge(this.text, this.bg, this.fg);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: TextStyle(fontFamily: 'Inter', fontSize: 9.5, fontWeight: FontWeight.w800, color: fg)),
    );
  }
}

// ---------------------------------------------------------------------------
class _ExpenseSheet extends StatefulWidget {
  final List<Map<String, dynamic>> categories;
  final int farmId;
  final Map<String, dynamic>? existing;
  const _ExpenseSheet({required this.categories, required this.farmId, this.existing});
  @override
  State<_ExpenseSheet> createState() => _ExpenseSheetState();
}

class _ExpenseSheetState extends State<_ExpenseSheet> {
  late int? _categoryId = (pickNum(widget.existing ?? {}, ['category'])?.toInt()) ??
      (widget.categories.isNotEmpty ? (pickNum(widget.categories.first, ['id'])?.toInt()) : null);
  late final _name = TextEditingController(text: pickString(widget.existing ?? {}, ['name']) ?? '');
  late final _qty = TextEditingController(
      text: pickString(widget.existing ?? {}, ['quantity']) ?? (pickNum(widget.existing ?? {}, ['quantity'])?.toString() ?? ''));
  late final _unit = TextEditingController(text: pickString(widget.existing ?? {}, ['unit']) ?? '');
  late final _unitCost = TextEditingController(
      text: pickString(widget.existing ?? {}, ['unit_cost']) ?? (pickNum(widget.existing ?? {}, ['unit_cost'])?.toString() ?? ''));
  late final _vendor = TextEditingController(text: pickString(widget.existing ?? {}, ['vendor']) ?? '');
  late final _pm = TextEditingController(text: pickString(widget.existing ?? {}, ['payment_method']) ?? '');
  late final _notes = TextEditingController(text: pickString(widget.existing ?? {}, ['notes']) ?? '');
  late DateTime _date = DateTime.tryParse(pickString(widget.existing ?? {}, ['date']) ?? '') ?? DateTime.now();
  String? _err;

  @override
  void initState() {
    super.initState();
    _qty.addListener(_refresh);
    _unitCost.addListener(_refresh);
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    for (final c in [_name, _qty, _unit, _unitCost, _vendor, _pm, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  double get _preview =>
      (double.tryParse(_qty.text.trim()) ?? 0) * (double.tryParse(_unitCost.text.trim()) ?? 0);

  String get _isoDate => '${_date.year}-${_two(_date.month)}-${_two(_date.day)}';

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _submit() {
    final name = _name.text.trim();
    final unit = _unit.text.trim();
    final qty = double.tryParse(_qty.text.trim());
    final cost = double.tryParse(_unitCost.text.trim());
    if (_categoryId == null || name.isEmpty || unit.isEmpty || qty == null || cost == null) {
      setState(() => _err = 'Fill category, name, quantity, unit and unit cost.');
      return;
    }
    Navigator.pop(context, {
      'category': _categoryId,
      'name': name,
      'quantity': _qty.text.trim(),
      'unit': unit,
      'unit_cost': _unitCost.text.trim(),
      'date': _isoDate,
      'vendor': _vendor.text.trim(),
      'payment_method': _pm.text.trim(),
      'notes': _notes.text.trim(),
      'farm': widget.farmId,
    });
  }

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      title: widget.existing != null ? 'Edit expense' : 'Add expense',
      error: _err,
      onSubmit: _submit,
      submitLabel: widget.existing != null ? 'Update expense' : 'Save expense',
      children: [
        _PickerChips(
          label: 'Category',
          options: widget.categories
              .map((c) => MapEntry((pickNum(c, ['id']) ?? 0).toInt(),
                  pickString(c, ['display_name']) ?? pickString(c, ['name']) ?? 'Category'))
              .toList(),
          selected: _categoryId,
          onTap: (v) => setState(() => _categoryId = v),
        ),
        const SizedBox(height: 12),
        _SheetField(controller: _name, hint: 'Name (e.g. NPK fertiliser)'),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _SheetField(controller: _qty, hint: 'Quantity', number: true)),
          const SizedBox(width: 10),
          Expanded(child: _SheetField(controller: _unit, hint: 'Unit (e.g. kg, bag)')),
        ]),
        const SizedBox(height: 10),
        _SheetField(controller: _unitCost, hint: 'Unit cost (UGX)', number: true),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
              color: const Color(0xFFEAF7EC), borderRadius: BorderRadius.circular(11), border: Border.all(color: AppColors.line)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total',
                  style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 12.5, color: AppColors.slate700)),
              Text(_ugx(_preview),
                  style: const TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFF0F7A4B))),
            ],
          ),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: _pickDate,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(11), border: Border.all(color: AppColors.line)),
            child: Row(children: [
              const Icon(Icons.event_rounded, size: 18, color: AppColors.slate600),
              const SizedBox(width: 10),
              Text(_isoDate, style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppColors.inkWarm)),
              const Spacer(),
              const Icon(Icons.expand_more_rounded, size: 18, color: AppColors.slate500),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _SheetField(controller: _vendor, hint: 'Vendor (optional)')),
          const SizedBox(width: 10),
          Expanded(child: _SheetField(controller: _pm, hint: 'Payment method (optional)')),
        ]),
        const SizedBox(height: 10),
        _SheetField(controller: _notes, hint: 'Notes (optional)', lines: 2),
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
