import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/dio_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/json_utils.dart';
import '../../widgets/fresh_kit.dart';
import '../../widgets/state_views.dart';

const _farmsPath = '/farms/';
const _financesPath = '/farm-finances/';

/// Finances / Profits analytics: pulls farm-finance records and rolls them up
/// into revenue, expenses, net profit and margin. Mirrors the web finances
/// page (income-vs-expense P&L) in a phone-first layout. Records can be
/// filtered to a single farm via the chips below the hero.
class FinancesScreen extends StatefulWidget {
  const FinancesScreen({super.key});
  @override
  State<FinancesScreen> createState() => _FinancesScreenState();
}

class _FinancesScreenState extends State<FinancesScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _farms = [];
  List<Map<String, dynamic>> _records = [];

  /// Selected farm id filter; null = All.
  int? _farmFilter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dio = context.read<DioClient>().dio;
      final res = await Future.wait([
        dio.get(_farmsPath),
        dio.get(_financesPath),
      ]);
      if (!mounted) return;
      setState(() {
        _farms = asList(res[0].data);
        _records = asList(res[1].data);
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

  bool _isIncome(Map<String, dynamic> r) {
    final t = (pickString(r, ['metric_type']) ?? '').toLowerCase();
    return t.contains('income') ||
        t.contains('revenue') ||
        t.contains('sale') ||
        t.contains('credit');
  }

  /// Records filtered by the selected farm.
  List<Map<String, dynamic>> get _filtered {
    if (_farmFilter == null) return _records;
    return _records
        .where((r) => pickNum(r, ['farm'])?.toInt() == _farmFilter)
        .toList();
  }

  double get _totalRevenue => _filtered
      .where(_isIncome)
      .fold(0.0, (s, r) => s + (pickNum(r, ['metric_value']) ?? 0).toDouble());

  double get _totalExpenses => _filtered
      .where((r) => !_isIncome(r))
      .fold(0.0, (s, r) => s + (pickNum(r, ['metric_value']) ?? 0).toDouble());

  double get _netProfit => _totalRevenue - _totalExpenses;

  double get _margin =>
      _totalRevenue > 0 ? (_netProfit / _totalRevenue) * 100 : 0;

  String _farmName(Map<String, dynamic> farm) =>
      pickString(farm, ['name', 'farm_name', 'title']) ?? 'Farm';

  /// Records sorted newest period first.
  List<Map<String, dynamic>> get _sortedRecords {
    final list = [..._filtered];
    list.sort((a, b) {
      final pa = pickString(a, ['period']) ?? '';
      final pb = pickString(b, ['period']) ?? '';
      return pb.compareTo(pa);
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final revenue = _totalRevenue;
    final expenses = _totalExpenses;
    final marginLabel = '${_margin.toStringAsFixed(0)}%';

    return Scaffold(
      backgroundColor: AppColors.cream,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            GradientHero(
              title: 'Finances',
              subtitle: 'Profit & loss',
              icon: Icons.insights_rounded,
              bigLabel: 'Net profit',
              bigValue: _loading ? '—' : money(_netProfit, decimals: 0),
              onBack: () => Navigator.of(context).maybePop(),
              chips: [
                HeroChip(icon: Icons.percent_rounded, label: '$marginLabel margin'),
              ],
            ),
            if (_loading)
              const Padding(padding: EdgeInsets.only(top: 40), child: LoadingView())
            else if (_error != null)
              Padding(
                  padding: const EdgeInsets.only(top: 32),
                  child: ErrorView(message: _error!, onRetry: _load))
            else ...[
              // ----- metric cards -----
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: MetricCard(
                        icon: Icons.trending_up_rounded,
                        value: money(revenue, decimals: 0),
                        label: 'Revenue',
                        color: AppColors.green,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: MetricCard(
                        icon: Icons.trending_down_rounded,
                        value: money(expenses, decimals: 0),
                        label: 'Expenses',
                        color: const Color(0xFFE11D48),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: MetricCard(
                        icon: Icons.percent_rounded,
                        value: marginLabel,
                        label: 'Margin',
                        color: const Color(0xFF6366F1),
                      ),
                    ),
                  ],
                ),
              ),
              // ----- farm filter chips -----
              if (_farms.isNotEmpty)
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      _FilterChip(
                        label: 'All',
                        selected: _farmFilter == null,
                        onTap: () => setState(() => _farmFilter = null),
                      ),
                      for (final f in _farms)
                        _FilterChip(
                          label: _farmName(f),
                          selected: _farmFilter == pickNum(f, ['id'])?.toInt(),
                          onTap: () => setState(
                              () => _farmFilter = pickNum(f, ['id'])?.toInt()),
                        ),
                    ],
                  ),
                ),
              // ----- income vs expense bars -----
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: _IncomeExpenseCard(revenue: revenue, expenses: expenses),
              ),
              // ----- records -----
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: FreshSectionHeader(title: 'Records'),
              ),
              if (_sortedRecords.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 16, bottom: 28),
                  child: EmptyView(
                      text: 'No finance records yet.',
                      icon: Icons.receipt_long_rounded),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                  child: Column(
                    children: [
                      for (final r in _sortedRecords)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _RecordTile(record: r, income: _isIncome(r)),
                        ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            gradient: selected ? AppColors.emeraldGrad : null,
            color: selected ? null : Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? Colors.transparent : AppColors.line),
          ),
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  color: selected ? Colors.white : AppColors.slate600)),
        ),
      ),
    );
  }
}

class _IncomeExpenseCard extends StatelessWidget {
  final double revenue;
  final double expenses;
  const _IncomeExpenseCard({required this.revenue, required this.expenses});

  @override
  Widget build(BuildContext context) {
    final max = revenue > expenses ? revenue : expenses;
    final revFrac = max > 0 ? (revenue / max).clamp(0.0, 1.0) : 0.0;
    final expFrac = max > 0 ? (expenses / max).clamp(0.0, 1.0) : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Income vs expense',
              style: TextStyle(
                  fontFamily: 'Fraunces',
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: AppColors.inkWarm)),
          const SizedBox(height: 14),
          _ProportionBar(
            label: 'Income',
            value: money(revenue, decimals: 0),
            fraction: revFrac.toDouble(),
            color: AppColors.green,
          ),
          const SizedBox(height: 12),
          _ProportionBar(
            label: 'Expense',
            value: money(expenses, decimals: 0),
            fraction: expFrac.toDouble(),
            color: const Color(0xFFE11D48),
          ),
        ],
      ),
    );
  }
}

class _ProportionBar extends StatelessWidget {
  final String label;
  final String value;
  final double fraction;
  final Color color;
  const _ProportionBar(
      {required this.label,
      required this.value,
      required this.fraction,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                      color: AppColors.slate600)),
            ),
            Text(value,
                style: const TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: AppColors.inkWarm)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: Container(
            height: 10,
            color: AppColors.line,
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: fraction,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RecordTile extends StatelessWidget {
  final Map<String, dynamic> record;
  final bool income;
  const _RecordTile({required this.record, required this.income});

  @override
  Widget build(BuildContext context) {
    final type = pickString(record, ['metric_type']) ?? 'Metric';
    final period = pickString(record, ['period']) ?? '';
    final amount = pickNum(record, ['metric_value']) ?? 0;
    final color = income ? AppColors.green : const Color(0xFFE11D48);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(11)),
            child: Icon(
                income
                    ? Icons.arrow_downward_rounded
                    : Icons.arrow_upward_rounded,
                size: 18,
                color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(type,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppColors.inkWarm)),
                if (period.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(period,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          color: AppColors.slate500)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text('${income ? '+' : '-'}${money(amount, decimals: 0)}',
              style: TextStyle(
                  fontFamily: 'Fraunces',
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: color)),
        ],
      ),
    );
  }
}
