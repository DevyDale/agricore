import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/dio_client.dart';
import '../../core/security/secure_screen.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/json_utils.dart';
import '../../core/utils/log.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/fresh_kit.dart';
import '../../widgets/state_views.dart';
import '../../core/i18n/locale_provider.dart';
import '../../core/responsive/responsive.dart';

const _walletsPath = '/digital-wallets/';
const _payoutPath = '/payout-accounts/';

/// Wallet hub: shows the digital-wallet balance and the seller payout
/// destination (mobile money or bank). Mirrors the web "Manage Wallet" flow
/// (a single payout account per user) in a phone-first layout.
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});
  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> with SecureScreenMixin {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _wallet;
  Map<String, dynamic>? _payout;

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
        dio.get(_walletsPath),
        dio.get(_payoutPath),
      ]);
      if (!mounted) return;
      final wallets = asList(res[0].data);
      final payouts = asList(res[1].data);
      setState(() {
        _wallet = wallets.isNotEmpty ? wallets.first : null;
        _payout = payouts.isNotEmpty ? payouts.first : null;
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

  Future<void> _editPayout() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PayoutSheet(existing: _payout),
    );
    if (result == null) return;
    if (!mounted) return;
    try {
      final dio = context.read<DioClient>().dio;
      if (_payout != null) {
        await dio.patch('$_payoutPath${pickNum(_payout!, ['id'])?.toInt()}/', data: result);
      } else {
        await dio.post(_payoutPath, data: result);
      }
      if (!mounted) return;
      showToast(context, 'Payout account saved');
      _load();
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), success: false);
    }
  }

  String get _balanceText {
    final code = pickString(_wallet ?? {}, ['currency']) ?? 'USD';
    final bal = pickNum(_wallet ?? {}, ['balance']) ?? 0;
    return money(bal, code: code, decimals: 2);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: MaxWidthBody(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              GradientHero(
                title: context.tr('Wallet'),
              subtitle: context.tr('Balance & payouts'),
              icon: Icons.account_balance_wallet_rounded,
              bigLabel: context.tr('Available balance'),
              bigValue: _loading ? '—' : _balanceText,
              chips: [
                HeroChip(
                    icon: _payout == null
                        ? Icons.error_outline_rounded
                        : Icons.verified_rounded,
                    label: _payout == null
                        ? context.tr('No payout set')
                        : context.tr('Payout ready')),
              ],
            ),
            if (_loading)
              const Padding(padding: EdgeInsets.only(top: 40), child: LoadingView())
            else if (_error != null)
              Padding(
                  padding: const EdgeInsets.only(top: 32),
                  child: ErrorView(message: _error!, onRetry: _load))
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
                child: FreshSectionHeader(
                  title: context.tr('Payout destination'),
                  action: _payout == null
                      ? FreshPillButton(
                          icon: Icons.add_rounded, label: context.tr('Add'), onTap: _editPayout)
                      : FreshPillButton(
                          icon: Icons.edit_rounded, label: context.tr('Edit'), onTap: _editPayout),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: _payout == null
                    ? _EmptyPayout(onAdd: _editPayout)
                    : _PayoutCard(payout: _payout!),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
                child: _InfoNote(
                  text: context.tr(
                      'Payouts from completed escrow sales are sent to this account. '
                      'Mobile money releases are instant; bank transfers may take 1–2 business days.'),
                ),
              ),
            ],
          ],
          ),
        ),
      ),
    );
  }
}

class _PayoutCard extends StatelessWidget {
  final Map<String, dynamic> payout;
  const _PayoutCard({required this.payout});

  @override
  Widget build(BuildContext context) {
    final method = (pickString(payout, ['method']) ?? 'momo').toLowerCase();
    final isBank = method == 'bank';
    final name = pickString(payout, ['account_name']) ?? '—';
    final number = pickString(payout, ['account_number']) ?? '';
    final masked = number.length > 4
        ? '•••• ${number.substring(number.length - 4)}'
        : number;
    final extra = isBank
        ? (pickString(payout, ['account_bank', 'bank_name']) ?? 'Bank')
        : (pickString(payout, ['network']) ?? 'Mobile Money');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 14,
              offset: const Offset(0, 6))
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                gradient: AppColors.emeraldGrad,
                borderRadius: BorderRadius.circular(13)),
            child: Icon(
                isBank ? Icons.account_balance_rounded : Icons.smartphone_rounded,
                color: Colors.white,
                size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontFamily: 'Fraunces',
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: AppColors.inkWarm)),
                const SizedBox(height: 2),
                Text('$extra  ·  $masked',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12.5,
                        color: AppColors.slate600)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(999)),
            child: Text(isBank ? context.tr('Bank') : context.tr('MoMo'),
                style: const TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w800,
                    fontSize: 10.5,
                    color: Color(0xFF166534))),
          ),
        ],
      ),
    );
  }
}

class _EmptyPayout extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyPayout({required this.onAdd});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onAdd,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          children: [
            Container(
              width: 54,
              height: 54,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: const Color(0xFFE7F4EC),
                  borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.add_card_rounded,
                  color: Color(0xFF0F7A4B), size: 26),
            ),
            const SizedBox(height: 12),
            Text(context.tr('Add a payout account'),
                style: const TextStyle(
                    fontFamily: 'Fraunces',
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: AppColors.inkWarm)),
            const SizedBox(height: 4),
            Text(context.tr('Mobile money or bank — so sale proceeds reach you.'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontFamily: 'Inter', fontSize: 12.5, color: AppColors.slate500)),
          ],
        ),
      ),
    );
  }
}

class _InfoNote extends StatelessWidget {
  final String text;
  const _InfoNote({required this.text});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
          color: const Color(0xFFEAF7EC),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: AppColors.line)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF0F7A4B)),
          const SizedBox(width: 9),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    height: 1.45,
                    color: AppColors.slate600)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
class _PayoutSheet extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const _PayoutSheet({this.existing});
  @override
  State<_PayoutSheet> createState() => _PayoutSheetState();
}

class _PayoutSheetState extends State<_PayoutSheet> {
  late String _method =
      (pickString(widget.existing ?? {}, ['method']) ?? 'momo').toLowerCase();
  late final _name =
      TextEditingController(text: pickString(widget.existing ?? {}, ['account_name']) ?? '');
  late final _number =
      TextEditingController(text: pickString(widget.existing ?? {}, ['account_number']) ?? '');
  late String? _bankCode = pickString(widget.existing ?? {}, ['account_bank']);
  late String? _bankName = pickString(widget.existing ?? {}, ['bank_name']);
  String? _err;

  @override
  void dispose() {
    _name.dispose();
    _number.dispose();
    super.dispose();
  }

  Future<void> _pickBank() async {
    final picked = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _BankPickerSheet(),
    );
    if (picked != null) {
      setState(() {
        _bankCode = picked['code'];
        _bankName = picked['name'];
      });
    }
  }

  void _submit() {
    final name = _name.text.trim();
    final number = _number.text.trim();
    if (name.isEmpty || number.isEmpty) {
      setState(() => _err = 'Enter the account holder name and number.');
      return;
    }
    if (_method == 'bank' && (_bankCode == null || _bankCode!.isEmpty)) {
      setState(() => _err = 'Choose a bank.');
      return;
    }
    final data = <String, dynamic>{
      'method': _method,
      'account_name': name,
      'account_number': number,
    };
    if (_method == 'bank') data['account_bank'] = _bankCode;
    Navigator.pop(context, data);
  }

  @override
  Widget build(BuildContext context) {
    final isBank = _method == 'bank';
    return FreshSheet(
      title: widget.existing != null
          ? context.tr('Edit payout account')
          : context.tr('Add payout account'),
      error: _err,
      onSubmit: _submit,
      submitLabel: context.tr('Save payout account'),
      children: [
        SegTabs(
          tabs: [context.tr('Mobile money'), context.tr('Bank')],
          index: isBank ? 1 : 0,
          onTap: (i) => setState(() => _method = i == 1 ? 'bank' : 'momo'),
        ),
        const SizedBox(height: 14),
        FreshField(controller: _name, label: context.tr('Account holder name'), hint: context.tr('e.g. Jane Doe')),
        const SizedBox(height: 12),
        if (isBank) ...[
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 6),
            child: Text(context.tr('Bank'),
                style: const TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    color: AppColors.slate700)),
          ),
          GestureDetector(
            onTap: _pickBank,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: AppColors.line)),
              child: Row(children: [
                const Icon(Icons.account_balance_rounded, size: 18, color: AppColors.slate600),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(_bankName ?? context.tr('Choose a bank'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14,
                          color: _bankName == null ? AppColors.slate500 : AppColors.inkWarm)),
                ),
                const Icon(Icons.expand_more_rounded, size: 18, color: AppColors.slate500),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          FreshField(
              controller: _number, label: context.tr('Account number'), hint: context.tr('Bank account number'), number: true),
        ] else
          FreshField(
              controller: _number,
              label: context.tr('Mobile money number'),
              hint: context.tr('e.g. 0772123456'),
              number: true),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
class _BankPickerSheet extends StatefulWidget {
  const _BankPickerSheet();
  @override
  State<_BankPickerSheet> createState() => _BankPickerSheetState();
}

class _BankPickerSheetState extends State<_BankPickerSheet> {
  bool _loading = true;
  String? _error;
  String _query = '';
  List<Map<String, dynamic>> _banks = [];

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
      final res = await dio.get('${_payoutPath}banks/');
      if (!mounted) return;
      final data = res.data;
      final list = (data is Map && data['banks'] is List)
          ? (data['banks'] as List)
          : (data is List ? data : const []);
      setState(() {
        _banks = list.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
        _loading = false;
      });
    } catch (e) {
      logSwallowed('Wallet.loadBanks', e);
      if (!mounted) return;
      setState(() {
        _error = 'Could not load banks. Pull to retry.';
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _view {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _banks;
    return _banks
        .where((b) => (pickString(b, ['name']) ?? '').toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        height: MediaQuery.sizeOf(context).height * 0.7,
        decoration: const BoxDecoration(
            color: AppColors.cream,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
        child: Column(
          children: [
            Center(
                child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                        color: AppColors.line, borderRadius: BorderRadius.circular(99)))),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(context.tr('Choose a bank'),
                  style: const TextStyle(
                      fontFamily: 'Fraunces',
                      fontWeight: FontWeight.w800,
                      fontSize: 19,
                      color: AppColors.inkWarm)),
            ),
            const SizedBox(height: 12),
            TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                hintText: context.tr('Search banks…'),
                prefixIcon: const Icon(Icons.search, size: 20),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.line)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.line)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.green)),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _loading
                  ? const LoadingView()
                  : _error != null
                      ? ErrorView(message: _error!, onRetry: _load)
                      : _view.isEmpty
                          ? EmptyView(text: context.tr('No banks found.'), icon: Icons.account_balance_outlined)
                          : ListView.separated(
                              itemCount: _view.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1, color: AppColors.line),
                              itemBuilder: (_, i) {
                                final b = _view[i];
                                final name = pickString(b, ['name']) ?? 'Bank';
                                final code = pickString(b, ['code']) ?? '';
                                return ListTile(
                                  dense: true,
                                  title: Text(name,
                                      style: const TextStyle(
                                          fontFamily: 'Inter',
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                          color: AppColors.inkWarm)),
                                  trailing: const Icon(Icons.chevron_right_rounded,
                                      color: AppColors.slate500),
                                  onTap: () =>
                                      Navigator.pop(context, {'code': code, 'name': name}),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}
