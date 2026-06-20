import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../core/network/dio_client.dart';
import '../../core/responsive/responsive.dart';
import '../../core/security/secure_screen.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/json_utils.dart';
import '../../core/utils/log.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/farmland_background.dart';
import '../../widgets/state_views.dart';
import 'store_bits.dart';
import 'store_repository.dart';
import '../wallet/wallet_screen.dart';

const Color _heroDark = Color(0xFF22432C);
const Color _green = Color(0xFF2E7D46);
const Color _gold = Color(0xFFC49A2E);

String _money(num? v) {
  final n = (v ?? 0).round();
  final neg = n < 0;
  final s = n.abs().toString();
  final b = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return 'UGX ${neg ? '-' : ''}$b';
}

List<Map<String, dynamic>> _listOf(dynamic d) {
  if (d is List) return d.whereType<Map<String, dynamic>>().toList();
  if (d is Map && d['results'] is List) return (d['results'] as List).whereType<Map<String, dynamic>>().toList();
  return [];
}

int _asId(dynamic v) {
  if (v is Map) return (pickNum(Map<String, dynamic>.from(v), ['id']) ?? 0).toInt();
  if (v is num) return v.toInt();
  return int.tryParse('$v') ?? 0;
}

class StoreDashboardScreen extends StatefulWidget {
  final Map<String, dynamic> store;
  const StoreDashboardScreen({super.key, required this.store});
  @override
  State<StoreDashboardScreen> createState() => _StoreDashboardScreenState();
}

class _StoreDashboardScreenState extends State<StoreDashboardScreen> with SecureScreenMixin {
  late Map<String, dynamic> _store;
  int _tab = 0;
  bool _tabLoading = false;
  final Set<int> _loaded = {};

  static const _tabs = ['Overview', 'Products', 'Orders', 'Wallet', 'Reviews', 'Ads', 'Sales', 'Performance'];
  static const _stages = ['pending', 'confirmed', 'packed', 'shipped', 'out_for_delivery', 'delivered'];
  static const _stageLabel = {
    'pending': 'Pending',
    'confirmed': 'Confirmed',
    'packed': 'Packed',
    'shipped': 'Shipped',
    'out_for_delivery': 'Out for delivery',
    'delivered': 'Delivered',
  };
  static const _fulfillStatuses = ['confirmed', 'packed', 'shipped', 'out_for_delivery', 'processing'];
  static const _attentionStatuses = ['pending', 'cancelled', 'canceled', 'refunded', 'failed', 'returned', 'disputed', 'rejected'];
  static const num _lowStock = 10;

  // shared data
  List<Map<String, dynamic>> _products = [];
  // products tab controls
  String _prodQuery = '';
  String _prodSort = 'recent';
  String _prodFilter = 'all';
  bool _prodSelect = false;
  final Set<int> _prodSelected = {};
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _escrows = [];
  List<Map<String, dynamic>> _deliveryJobs = [];
  List<Map<String, dynamic>> _storeReviews = [];
  List<Map<String, dynamic>> _productReviews = [];
  List<Map<String, dynamic>> _ads = [];
  Map<String, dynamic>? _farm;
  Map<String, dynamic>? _payout;
  bool _meLoaded = false;
  int? _meId;

  // payout form
  final _poName = TextEditingController();
  final _poPhone = TextEditingController();
  final _poAcct = TextEditingController();
  final _poBank = TextEditingController();
  String _poNetwork = 'MTN';
  String _poMethod = 'momo';
  bool _poSaving = false;
  // batch 4: bank picker + review controls
  List<Map<String, dynamic>> _banks = [];
  String _poBankCode = '';
  String _revFilter = 'all';
  String _revSort = 'recent';
  String _salesBucket = 'day';
  String _perfSort = 'revenue';

  int get _id => (pickNum(_store, ['id']) ?? 0).toInt();
  StoreRepository get _repo => StoreRepository(context.read<DioClient>().dio);

  @override
  void initState() {
    super.initState();
    _store = Map<String, dynamic>.from(widget.store);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshStore();
      _loadTab(0);
    });
  }

  @override
  void dispose() {
    _poName.dispose();
    _poPhone.dispose();
    _poAcct.dispose();
    _poBank.dispose();
    super.dispose();
  }

  Future<void> _refreshStore() async {
    try {
      final data = await _repo.fetchStore(_id);
      if (!mounted) return;
      if (data is Map) setState(() => _store = Map<String, dynamic>.from(data));
    } catch (e) {
      logSwallowed('StoreDashboard.refreshStore', e);
    }
  }

  // ---- fetchers ----
  Future<void> _fetchProducts() async {
    try {
      final data = await _repo.fetchProducts(_id);
      _products = _listOf(data);
    } catch (_) {
      _products = [];
    }
  }

  Future<void> _fetchOrders() async {
    try {
      final data = await _repo.fetchOrders();
      _orders = _listOf(data);
    } catch (_) {
      _orders = [];
    }
    try {
      final data = await _repo.fetchOrderItems();
      _items = _listOf(data);
    } catch (_) {
      _items = [];
    }
  }

  Future<void> _fetchEscrows() async {
    try {
      final data = await _repo.fetchEscrows();
      _escrows = _listOf(data);
    } catch (_) {
      _escrows = [];
    }
  }

  Future<void> _fetchDeliveryJobs() async {
    try {
      final data = await _repo.fetchDeliveryJobs();
      _deliveryJobs = _listOf(data);
    } catch (_) {
      _deliveryJobs = [];
    }
  }

  Future<void> _fetchStoreReviews() async {
    try {
      final data = await _repo.fetchStoreReviews(_id);
      _storeReviews = _listOf(data);
    } catch (_) {
      _storeReviews = [];
    }
  }

  Future<void> _fetchProductReviews() async {
    final targets = _products.take(40).toList();
    final out = <Map<String, dynamic>>[];
    await Future.wait(targets.map((p) async {
      final pid = (pickNum(p, ['id']) ?? 0).toInt();
      try {
        final data = await _repo.fetchProductReviews(pid);
        for (final x in _listOf(data)) {
          out.add({...x, '_product': pickString(p, ['title']) ?? 'Product'});
        }
      } catch (e) {
        logSwallowed('StoreDashboard.fetchProductReviews', e);
      }
    }));
    _productReviews = out;
  }

  Future<void> _fetchFarm() async {
    final f = _store['farm'];
    if (f == null) {
      _farm = null;
      return;
    }
    try {
      final data = await _repo.fetchFarm(_asId(f));
      _farm = (data is Map) ? Map<String, dynamic>.from(data) : null;
    } catch (_) {
      _farm = null;
    }
  }

  Future<void> _fetchMe() async {
    if (_meLoaded) return;
    try {
      final data = await _repo.fetchMe();
      if (data is Map) _meId = (pickNum(Map<String, dynamic>.from(data), ['id']) ?? 0).toInt();
    } catch (e) {
      logSwallowed('StoreDashboard.fetchMe', e);
    }
    _meLoaded = true;
  }

  Future<void> _fetchPayout() async {
    try {
      final data = await _repo.fetchPayout();
      final list = _listOf(data);
      _payout = list.isNotEmpty ? list.first : null;
      _syncPayoutForm();
    } catch (_) {
      _payout = null;
    }
  }

  Future<void> _fetchBanks() async {
    try {
      final data = await _repo.fetchPayoutBanks();
      _banks = _listOf(data);
    } catch (_) {
      _banks = []; // endpoint absent -> form falls back to free-text bank code
    }
  }

  Future<void> _fetchAds() async {
    try {
      final data = await _repo.fetchAds(_id);
      _ads = _listOf(data);
    } catch (_) {
      _ads = [];
    }
  }

  void _syncPayoutForm() {
    final a = _payout;
    if (a == null) return;
    _poName.text = pickString(a, ['account_name']) ?? '';
    final isMomo = (pickString(a, ['method']) == 'momo') || (pickString(a, ['account_bank']) == 'MPS');
    if (isMomo) {
      _poMethod = 'momo';
      _poNetwork = pickString(a, ['network']) ?? 'MTN';
      _poPhone.text = pickString(a, ['account_number']) ?? '';
    } else {
      _poMethod = 'bank';
      _poBank.text = pickString(a, ['account_bank']) ?? '';
      _poBankCode = pickString(a, ['account_bank']) ?? '';
      _poAcct.text = pickString(a, ['account_number']) ?? '';
    }
  }

  Future<void> _loadTab(int i, {bool force = false}) async {
    if (_loaded.contains(i) && !force) return;
    setState(() => _tabLoading = true);
    try {
      switch (i) {
        case 0:
          await Future.wait([_fetchProducts(), _fetchOrders(), _fetchStoreReviews(), _fetchFarm()]);
          break;
        case 1:
          await _fetchProducts();
          break;
        case 2:
          await Future.wait([_fetchProducts(), _fetchOrders(), _fetchEscrows(), _fetchMe(), _fetchDeliveryJobs()]);
          break;
        case 3:
          await Future.wait([_fetchEscrows(), _fetchOrders(), _fetchPayout(), _fetchBanks()]);
          break;
        case 4:
          await _fetchStoreReviews();
          await _fetchProductReviews();
          break;
        case 5:
          await _fetchAds();
          break;
        case 6:
        case 7:
          await Future.wait([_fetchOrders(), _fetchProducts()]);
          break;
      }
      _loaded.add(i);
    } catch (e) {
      logSwallowed('StoreDashboard.loadTab', e);
    }
    if (mounted) setState(() => _tabLoading = false);
  }

  void _select(int i) {
    setState(() => _tab = i);
    _loadTab(i);
  }

  // ---- order helpers ----
  String _ordStatus(Map o) => (pickString(o, ['status']) ?? '').toLowerCase().replaceAll(' ', '_');
  double _ordTotal(Map o) => (pickNum(o, ['total_amount']) ?? pickNum(o, ['total']) ?? 0).toDouble();
  int _ordStore(Map o) => _asId(o['store']);
  int _ordBuyer(Map o) => _asId(o['buyer']);
  bool _cancelled(String s) => ['cancelled', 'canceled', 'refunded', 'failed', 'rejected'].contains(s);
  String? _nextStage(String s) {
    final idx = _stages.indexOf(s);
    if (idx == -1) return 'confirmed';
    if (idx >= _stages.length - 1) return null;
    return _stages[idx + 1];
  }

  String _itemSummary(int orderId) {
    final its = _items.where((it) => _asId(it['order']) == orderId).toList();
    if (its.isEmpty) return '';
    final names = its.take(3).map((it) {
      final pid = _asId(it['product']);
      final prod = _products.firstWhere((p) => (pickNum(p, ['id']) ?? -1).toInt() == pid, orElse: () => {});
      final name = pickString(prod, ['title']) ?? 'Item';
      final q = (pickNum(it, ['quantity']) ?? 0);
      return '$name ×${q % 1 == 0 ? q.toInt() : q}';
    });
    var out = names.join(', ');
    if (its.length > 3) out += ' +${its.length - 3} more';
    return out;
  }

  Map<String, dynamic>? _escrowOf(int orderId) {
    for (final e in _escrows) {
      if (_asId(e['order']) == orderId) return e;
    }
    return null;
  }

  bool _hasValue(dynamic v) => v != null && '$v'.trim().isNotEmpty;

  // ---- actions ----
  Future<bool> _confirm(String title, String message, {bool danger = false}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title, style: const TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800)),
        content: Text(message, style: const TextStyle(fontFamily: 'Inter', fontSize: 14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(danger ? 'Delete' : 'Confirm', style: TextStyle(color: danger ? const Color(0xFFDC2626) : _green))),
        ],
      ),
    );
    return ok == true;
  }

  Future<String?> _promptText(String title, String hint, {bool number = false, String okLabel = 'OK'}) async {
    final c = TextEditingController();
    final r = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title, style: const TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 17)),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: number ? TextInputType.number : TextInputType.text,
          decoration: InputDecoration(
            hintText: hint,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(11)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, c.text), child: Text(okLabel, style: const TextStyle(color: _green))),
        ],
      ),
    );
    c.dispose();
    return r;
  }

  Future<void> _togglePublish(Map<String, dynamic> p, bool pub) async {
    final id = (pickNum(p, ['id']) ?? 0).toInt();
    setState(() => p['is_published'] = pub);
    try {
      await _repo.updateProductPublished(id, pub);
    } catch (e) {
      if (!mounted) return;
      setState(() => p['is_published'] = !pub);
      showToast(context, friendlyError(e), success: false);
    }
  }

  Future<void> _deleteProduct(Map<String, dynamic> p) async {
    if (!await _confirm('Delete product?', 'This permanently removes it from your store.', danger: true)) return;
    final id = (pickNum(p, ['id']) ?? 0).toInt();
    try {
      await _repo.deleteProduct(id);
      if (!mounted) return;
      setState(() => _products.removeWhere((x) => (pickNum(x, ['id']) ?? -1).toInt() == id));
      showToast(context, 'Product deleted');
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), success: false);
    }
  }

  Future<void> _openProductSheet({Map<String, dynamic>? existing}) async {
    final r = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProductSheet(existing: existing),
    );
    if (r == null) return;
    final imagePath = r.remove('_imagePath') as String?;
    dynamic body(Map<String, dynamic> fields) {
      if (imagePath == null) return fields;
      return FormData.fromMap({
        ...fields.map((k, v) => MapEntry(k, v is bool ? '$v' : v)),
        'image': MultipartFile.fromFileSync(imagePath, filename: imagePath.split('/').last),
      });
    }

    try {
      if (existing == null) {
        r['store'] = _id;
        await _repo.createProduct(body(r));
      } else {
        final id = (pickNum(existing, ['id']) ?? 0).toInt();
        await _repo.updateProduct(id, body(r));
      }
      if (!mounted) return;
      showToast(context, existing == null ? 'Product added' : 'Product updated');
      _loadTab(1, force: true);
      _loaded.remove(0);
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), success: false);
    }
  }

  Future<void> _saveQty(Map<String, dynamic> p, num qty) async {
    final id = (pickNum(p, ['id']) ?? 0).toInt();
    final before = pickNum(p, ['stock_quantity']) ?? 0;
    if (qty == before) return;
    setState(() => p['stock_quantity'] = qty);
    try {
      await _repo.updateProductStock(id, qty);
    } catch (e) {
      if (!mounted) return;
      setState(() => p['stock_quantity'] = before);
      showToast(context, friendlyError(e), success: false);
    }
  }

  Future<void> _duplicateProduct(Map<String, dynamic> p) async {
    final copy = <String, dynamic>{
      'store': _id,
      'title': '${pickString(p, ['title']) ?? 'Product'} (copy)',
      'category': pickString(p, ['category']) ?? 'Other',
      'price': pickNum(p, ['price']) ?? 0,
      'stock_quantity': pickNum(p, ['stock_quantity']) ?? 0,
      'unit': pickString(p, ['unit']) ?? '',
      'description': pickString(p, ['description']) ?? '',
      'is_published': false,
    };
    try {
      await _repo.createProduct(copy);
      if (!mounted) return;
      showToast(context, 'Duplicated as a draft.');
      _loadTab(1, force: true);
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), success: false);
    }
  }

  Future<void> _bulkPublish(bool pub) async {
    final ids = _prodSelected.toList();
    if (ids.isEmpty) return;
    var ok = 0;
    for (final id in ids) {
      try {
        await _repo.updateProductPublished(id, pub);
        final p = _products.firstWhere((x) => (pickNum(x, ['id']) ?? -1).toInt() == id, orElse: () => {});
        if (p.isNotEmpty) p['is_published'] = pub;
        ok++;
      } catch (e) {
        logSwallowed('StoreDashboard.bulkPublish', e);
      }
    }
    if (!mounted) return;
    setState(() {
      _prodSelect = false;
      _prodSelected.clear();
    });
    showToast(context, '${pub ? 'Published' : 'Unpublished'} $ok product${ok == 1 ? '' : 's'}.', success: ok > 0);
  }

  Future<void> _bulkDelete() async {
    final ids = _prodSelected.toList();
    if (ids.isEmpty) return;
    if (!await _confirm('Delete ${ids.length} product${ids.length == 1 ? '' : 's'}?', 'This permanently removes them from your store.', danger: true)) return;
    var ok = 0;
    for (final id in ids) {
      try {
        await _repo.deleteProduct(id);
        ok++;
      } catch (e) {
        logSwallowed('StoreDashboard.bulkDelete', e);
      }
    }
    if (!mounted) return;
    setState(() {
      _products.removeWhere((x) => ids.contains((pickNum(x, ['id']) ?? -1).toInt()));
      _prodSelect = false;
      _prodSelected.clear();
    });
    showToast(context, 'Deleted $ok product${ok == 1 ? '' : 's'}.', success: ok > 0);
  }

  Future<void> _advance(Map<String, dynamic> o) async {
    final id = (pickNum(o, ['id']) ?? 0).toInt();
    final ns = _nextStage(_ordStatus(o));
    if (ns == null) return;
    try {
      await _repo.updateOrderStatus(id, ns);
      if (!mounted) return;
      setState(() => o['status'] = ns);
      showToast(context, 'Order #$id → ${_stageLabel[ns]}');
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), success: false);
    }
  }

  Future<void> _cancelOrder(Map<String, dynamic> o) async {
    if (!await _confirm('Cancel this order?', 'The order will be marked cancelled.', danger: true)) return;
    final id = (pickNum(o, ['id']) ?? 0).toInt();
    final before = pickString(o, ['status']) ?? '';
    setState(() => o['status'] = 'cancelled');
    try {
      await _repo.updateOrderStatus(id, 'cancelled');
      if (mounted) showToast(context, 'Order #$id cancelled');
    } catch (e) {
      if (!mounted) return;
      setState(() => o['status'] = before);
      showToast(context, friendlyError(e), success: false);
    }
  }

  // ---- seller escrow: dispatch (issue OTP) / confirm delivery / transporter ----
  Future<void> _dispatchOrder(Map<String, dynamic> esc) async {
    final qty = await _promptText('Dispatch order', 'Quantity / weight sent (optional)', okLabel: 'Dispatch');
    if (qty == null) return;
    final eid = (pickNum(esc, ['id']) ?? 0).toInt();
    try {
      final fd = FormData.fromMap({if (qty.trim().isNotEmpty) 'dispatch_quantity': qty.trim()});
      await _repo.issueOtp(eid, fd);
      if (!mounted) return;
      showToast(context, 'Dispatched. The buyer now has a delivery code.');
      _loadTab(2, force: true);
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), success: false);
    }
  }

  Future<void> _confirmDeliverySeller(Map<String, dynamic> esc) async {
    final otp = await _promptText('Confirm delivery', "Enter the buyer's delivery code", number: true, okLabel: 'Confirm');
    if (otp == null || otp.trim().isEmpty) return;
    final eid = (pickNum(esc, ['id']) ?? 0).toInt();
    try {
      await _repo.confirmDelivery(eid, otp.trim());
      if (!mounted) return;
      showToast(context, 'Delivery confirmed. Payout follows the dispute window.');
      _loadTab(2, force: true);
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), success: false);
    }
  }

  Future<void> _requestTransporter(int orderId) async {
    final existing = _deliveryJobs.firstWhere((j) => _asId(j['order']) == orderId, orElse: () => {});
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TransporterSheet(orderId: orderId, existingJob: existing.isEmpty ? null : existing),
    );
    if (mounted) _loadTab(2, force: true);
  }

  Future<void> _payOrder(Map<String, dynamic> o) async {
    final oid = (pickNum(o, ['id']) ?? 0).toInt();
    try {
      var esc = _escrowOf(oid);
      if (esc == null) {
        final data = await _repo.createEscrow({
          'order': oid,
          'amount': _ordTotal(o),
          'currency': (pickString(o, ['currency']) ?? 'UGX'),
        });
        esc = (data is Map) ? Map<String, dynamic>.from(data) : null;
        if (esc != null) _escrows.add(esc);
      }
      if (esc == null) return;
      final eid = (pickNum(esc, ['id']) ?? 0).toInt();
      final payData = await _repo.payEscrow(eid);
      final link = (payData is Map) ? pickString(Map<String, dynamic>.from(payData), ['checkout_link']) : null;
      if (!mounted) return;
      if (link != null && link.isNotEmpty) {
        await Clipboard.setData(ClipboardData(text: link));
        if (!mounted) return;
        showToast(context, 'Checkout link copied — open it in your browser to pay.');
      } else {
        showToast(context, 'Escrow created, but no checkout link was returned.', success: false);
      }
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), success: false);
    }
  }

  Future<void> _releaseEscrow(Map<String, dynamic> esc) async {
    if (!await _confirm('Confirm delivery?', 'This releases the held funds to the seller. Only do this once you have received your order.')) {
      return;
    }
    final eid = (pickNum(esc, ['id']) ?? 0).toInt();
    try {
      await _repo.releaseEscrow(eid);
      if (!mounted) return;
      showToast(context, 'Funds release initiated.');
      _loadTab(2, force: true);
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), success: false);
    }
  }

  Future<void> _savePayout() async {
    final name = _poName.text.trim();
    if (name.isEmpty) {
      showToast(context, 'Enter the account holder name.', success: false);
      return;
    }
    Map<String, dynamic> payload;
    if (_poMethod == 'momo') {
      final phone = _poPhone.text.trim();
      if (phone.isEmpty) {
        showToast(context, 'Enter your mobile money number.', success: false);
        return;
      }
      payload = {'method': 'momo', 'account_bank': 'MPS', 'network': _poNetwork, 'account_number': phone, 'account_name': name};
    } else {
      final code = (_banks.isNotEmpty ? _poBankCode : _poBank.text).trim();
      final acct = _poAcct.text.trim();
      if (code.isEmpty || acct.isEmpty) {
        showToast(context, _banks.isNotEmpty ? 'Pick your bank and enter the account number.' : 'Enter your bank code and account number.', success: false);
        return;
      }
      payload = {'method': 'bank', 'account_bank': code, 'account_number': acct, 'account_name': name, 'network': ''};
    }
    setState(() => _poSaving = true);
    try {
      final a = _payout;
      if (a != null && a['id'] != null) {
        await _repo.updatePayoutAccount(_asId(a['id']), payload);
      } else {
        await _repo.createPayoutAccount(payload);
      }
      if (!mounted) return;
      setState(() => _poSaving = false);
      showToast(context, 'Payout destination saved.');
      _loadTab(3, force: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _poSaving = false);
      showToast(context, friendlyError(e), success: false);
    }
  }

  Future<void> _toggleAd(Map<String, dynamic> a, bool active) async {
    final id = (pickNum(a, ['id']) ?? 0).toInt();
    setState(() => a['is_active'] = active);
    try {
      await _repo.updateAdActive(id, active);
      if (mounted) showToast(context, active ? 'Ad activated' : 'Ad paused');
    } catch (e) {
      if (!mounted) return;
      setState(() => a['is_active'] = !active);
      showToast(context, friendlyError(e), success: false);
    }
  }

  Future<void> _deleteAd(Map<String, dynamic> a) async {
    if (!await _confirm('Delete this ad?', 'It will be removed from the marketplace.', danger: true)) return;
    final id = (pickNum(a, ['id']) ?? 0).toInt();
    try {
      await _repo.deleteAd(id);
      if (!mounted) return;
      setState(() => _ads.removeWhere((x) => (pickNum(x, ['id']) ?? -1).toInt() == id));
      showToast(context, 'Ad deleted');
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), success: false);
    }
  }

  Future<void> _openAdSheet() async {
    final r = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AdSheet(),
    );
    if (r == null) return;
    final imagePath = r.remove('_imagePath') as String?;
    try {
      r['store'] = _id;
      r['is_active'] = true;
      dynamic data = r;
      if (imagePath != null) {
        data = FormData.fromMap({
          ...r.map((k, v) => MapEntry(k, v is bool ? '$v' : v)),
          'image': MultipartFile.fromFileSync(imagePath, filename: imagePath.split('/').last),
        });
      }
      await _repo.createAd(data);
      if (!mounted) return;
      showToast(context, 'Advertisement is live.');
      _loadTab(5, force: true);
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), success: false);
    }
  }

  // ---- build ----
  @override
  Widget build(BuildContext context) {
    final name = pickString(_store, ['name', 'store_name', 'title']) ?? 'Store';
    final verified = _store['is_verified'] == true;
    final value = pickNum(_store, ['total_value']);
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: MaxWidthBody(
        child: CustomScrollView(
          slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 168,
            toolbarHeight: 56,
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
                RepaintBoundary(child: FarmlandBackground(showPins: false, child: const SizedBox.expand())),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                        begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x330E2018), Color(0xE60E2018)]),
                  ),
                ),
                LayoutBuilder(
                  builder: (context, c) {
                    final top = MediaQuery.of(context).padding.top;
                    final maxH = 168.0 + top;
                    final minH = kToolbarHeight + 50.0 + top;
                    final t = ((c.maxHeight - minH) / (maxH - minH)).clamp(0.0, 1.0);
                    final titleOpacity = ((0.4 - t) / 0.4).clamp(0.0, 1.0);
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        Positioned.fill(
                          child: IgnorePointer(child: Opacity(opacity: titleOpacity, child: const ColoredBox(color: _heroDark))),
                        ),
                        Positioned(
                          left: 18,
                          right: 18,
                          bottom: 58,
                          child: Opacity(opacity: t, child: _heroContent(name, verified, value)),
                        ),
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
                                child: Text(name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 18, color: Colors.white)),
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
            bottom: PreferredSize(preferredSize: const Size.fromHeight(50), child: _tabStrip()),
          ),
          SliverToBoxAdapter(child: _section()),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
        ),
      ),
    );
  }

  Widget _heroContent(String name, bool verified, num? value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w900, fontSize: 25, height: 1.05, color: Colors.white)),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: verified ? const Color(0x3334D399) : Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: verified ? const Color(0xFF9FE1CB) : Colors.white24),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(verified ? Icons.verified_rounded : Icons.schedule_rounded,
                    size: 12, color: verified ? const Color(0xFFBBF7D0) : Colors.white70),
                const SizedBox(width: 4),
                Text(verified ? 'Verified' : 'Pending',
                    style: TextStyle(fontFamily: 'Inter', fontSize: 10.5, fontWeight: FontWeight.w700, color: verified ? const Color(0xFFBBF7D0) : Colors.white70)),
              ]),
            ),
          ],
        ),
        const SizedBox(height: 7),
        Row(children: [
          Icon(Icons.sell_rounded, size: 14, color: Colors.white.withValues(alpha: 0.82)),
          const SizedBox(width: 6),
          Text('Store value ${_money(value)}',
              style: TextStyle(fontFamily: 'Inter', fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.9))),
        ]),
      ],
    );
  }

  Widget _tabStrip() {
    return Container(
      color: _heroDark,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final on = i == _tab;
          return GestureDetector(
            onTap: () => _select(i),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: on ? Colors.white : Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: on ? Colors.white : Colors.white24),
              ),
              child: Text(_tabs[i],
                  style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13, color: on ? _heroDark : Colors.white)),
            ),
          );
        },
      ),
    );
  }

  Widget _section() {
    if (_tabLoading && !_loaded.contains(_tab)) {
      return const Padding(padding: EdgeInsets.only(top: 50), child: LoadingView());
    }
    switch (_tab) {
      case 0:
        return _overview();
      case 1:
        return _productsSection();
      case 2:
        return _ordersSection();
      case 3:
        return _walletSection();
      case 4:
        return _reviewsSection();
      case 5:
        return _adsSection();
      case 6:
        return _salesSection();
      case 7:
        return _performanceSection();
    }
    return const SizedBox();
  }

  // ---- shared small UI ----
  Widget _card({required Widget child, EdgeInsets? padding}) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
      child: child,
    );
  }

  Widget _sectionHeader(String title, {Widget? action}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                style: const TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.inkWarm)),
          ),
          if (action != null) action,
        ],
      ),
    );
  }

  Widget _addButton(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.circular(11)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.add_rounded, color: Colors.white, size: 16),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 12.5, color: Colors.white)),
        ]),
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(height: 10),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.inkWarm)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.slate500)),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 15, color: _green),
        const SizedBox(width: 10),
        Text('$label  ', style: const TextStyle(fontFamily: 'Inter', fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.slate500)),
        Expanded(
          child: Text(value,
              style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppColors.slate700)),
        ),
      ]),
    );
  }

  Widget _statusBadge(String st) {
    final s = st.toLowerCase().replaceAll(' ', '_');
    Color bg = const Color(0xFFF1EFE8), fg = AppColors.slate600;
    if (['delivered', 'completed', 'paid', 'released'].contains(s)) {
      bg = const Color(0xFFDCFCE7);
      fg = const Color(0xFF166534);
    } else if (['shipped', 'out_for_delivery', 'packed', 'confirmed', 'processing', 'held'].contains(s)) {
      bg = const Color(0xFFE0F2FE);
      fg = const Color(0xFF075985);
    } else if (s == 'pending') {
      bg = const Color(0xFFFAEEDA);
      fg = const Color(0xFF854F0B);
    } else if (_cancelled(s) || s == 'disputed') {
      bg = const Color(0xFFFEE2E2);
      fg = const Color(0xFFB91C1C);
    }
    final label = _stageLabel[s] ?? (st.isEmpty ? 'Unknown' : st[0].toUpperCase() + st.substring(1));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(fontFamily: 'Inter', fontSize: 10.5, fontWeight: FontWeight.w700, color: fg)),
    );
  }

  Widget _smallBtn(IconData icon, String label, VoidCallback onTap, {Color? color, bool danger = false}) {
    final fg = danger ? const Color(0xFFDC2626) : (color ?? AppColors.slate600);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: danger ? const Color(0xFFFEF2F2) : const Color(0xFFFAF7EF),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: danger ? const Color(0xFFFCA5A5) : AppColors.line),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
        ]),
      ),
    );
  }

  // ---- Overview ----
  Widget _overview() {
    final incoming = _orders.where((o) => _ordStore(o) == _id).toList();
    final active = incoming.where((o) => !_cancelled(_ordStatus(o))).toList();
    final revenue = active.fold<double>(0, (s, o) => s + _ordTotal(o));
    final liveProducts = _products.where((p) => p['is_published'] != false).length;
    final rating = _storeReviews.isEmpty
        ? 0.0
        : _storeReviews.fold<double>(0, (s, r) => s + (pickNum(r, ['rating']) ?? 0).toDouble()) / _storeReviews.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: _statCard('Revenue', _money(revenue), Icons.payments_rounded, _green)),
            const SizedBox(width: 10),
            Expanded(child: _statCard('Orders', incoming.length.toString(), Icons.shopping_cart_rounded, const Color(0xFF0F7A4B))),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _statCard('Products live', liveProducts.toString(), Icons.inventory_2_rounded, const Color(0xFF6AA83A))),
            const SizedBox(width: 10),
            Expanded(child: _statCard('Rating', rating.toStringAsFixed(1), Icons.star_rounded, _gold)),
          ]),
          const SizedBox(height: 18),
          _sectionHeader('Store details'),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _detailRow(Icons.person_rounded, 'Owner', pickString(_store, ['owner_name']) ?? '—'),
                _detailRow(Icons.email_rounded, 'Email', pickString(_store, ['owner_email']) ?? '—'),
                _detailRow(Icons.phone_rounded, 'Contact', pickString(_store, ['owner_phone']) ?? '—'),
                _detailRow(Icons.public_rounded, 'Countries',
                    normCountries(_store['countries_of_operation']).isEmpty ? 'Not specified' : normCountries(_store['countries_of_operation']).join(', ')),
                const SizedBox(height: 6),
                Text(pickString(_store, ['description']) ?? 'No description provided',
                    style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppColors.slate600, height: 1.4)),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _sectionHeader('Attached farm'),
          if (_farm == null)
            _card(child: const Text('No farm attached to this store.', style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppColors.slate600)))
          else
            _card(
              child: Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.circular(11)),
                  child: const Icon(Icons.agriculture_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(pickString(_farm!, ['name', 'farm_name']) ?? 'Farm',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.inkWarm)),
                ),
              ]),
            ),
        ],
      ),
    );
  }

  // ---- Products ----
  List<Map<String, dynamic>> _filteredProducts() {
    final q = _prodQuery.trim().toLowerCase();
    final list = _products.where((p) {
      final pub = p['is_published'] != false;
      final stock = (pickNum(p, ['stock_quantity']) ?? 0);
      switch (_prodFilter) {
        case 'live':
          if (!pub) return false;
          break;
        case 'low':
          if (stock > _lowStock) return false;
          break;
        case 'draft':
          if (pub) return false;
          break;
      }
      if (q.isEmpty) return true;
      final t = (pickString(p, ['title']) ?? '').toLowerCase();
      final c = (pickString(p, ['category']) ?? '').toLowerCase();
      return t.contains(q) || c.contains(q);
    }).toList();
    int byNum(num? a, num? b) => (a ?? 0).compareTo(b ?? 0);
    switch (_prodSort) {
      case 'price_asc':
        list.sort((a, b) => byNum(pickNum(a, ['price']), pickNum(b, ['price'])));
        break;
      case 'price_desc':
        list.sort((a, b) => byNum(pickNum(b, ['price']), pickNum(a, ['price'])));
        break;
      case 'stock_asc':
        list.sort((a, b) => byNum(pickNum(a, ['stock_quantity']), pickNum(b, ['stock_quantity'])));
        break;
      case 'name':
        list.sort((a, b) => (pickString(a, ['title']) ?? '').toLowerCase().compareTo((pickString(b, ['title']) ?? '').toLowerCase()));
        break;
      default:
        list.sort((a, b) => byNum(pickNum(b, ['id']), pickNum(a, ['id'])));
    }
    return list;
  }

  Widget _productsSection() {
    final total = _products.length;
    final live = _products.where((p) => p['is_published'] != false).length;
    final low = _products.where((p) => (pickNum(p, ['stock_quantity']) ?? 0) <= _lowStock).length;
    final draft = total - live;
    final list = _filteredProducts();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader('Products', action: _addButton('Add', () => _openProductSheet())),
          Row(children: [
            Expanded(child: _statCard('All', total.toString(), Icons.inventory_2_rounded, _green)),
            const SizedBox(width: 10),
            Expanded(child: _statCard('Live', live.toString(), Icons.storefront_rounded, const Color(0xFF0F7A4B))),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _statCard('Low stock', low.toString(), Icons.trending_down_rounded, _gold)),
            const SizedBox(width: 10),
            Expanded(child: _statCard('Drafts', draft.toString(), Icons.edit_note_rounded, const Color(0xFF64748B))),
          ]),
          const SizedBox(height: 16),
          if (_products.isNotEmpty) ...[
            TextField(
              onChanged: (v) => setState(() => _prodQuery = v),
              decoration: InputDecoration(
                hintText: 'Search products…',
                prefixIcon: const Icon(Icons.search_rounded, size: 19, color: AppColors.slate500),
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.line)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.line)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _green)),
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    _filterChip('all', 'All'),
                    _filterChip('live', 'Live'),
                    _filterChip('low', 'Low'),
                    _filterChip('draft', 'Drafts'),
                  ]),
                ),
              ),
              const SizedBox(width: 8),
              _sortMenu(),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => setState(() {
                  _prodSelect = !_prodSelect;
                  _prodSelected.clear();
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                  decoration: BoxDecoration(
                    color: _prodSelect ? _green : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _prodSelect ? _green : AppColors.line),
                  ),
                  child: Text(_prodSelect ? 'Done' : 'Select',
                      style: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w700, color: _prodSelect ? Colors.white : AppColors.slate600)),
                ),
              ),
            ]),
            if (_prodSelect) _bulkBar(),
            const SizedBox(height: 12),
          ],
          if (_products.isEmpty)
            _card(child: const Text('No products yet. Tap "Add" to list your first one.', style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppColors.slate600)))
          else if (list.isEmpty)
            _card(child: const Text('No products match your search or filter.', style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppColors.slate600)))
          else
            ...list.map(_productCard),
        ],
      ),
    );
  }

  Widget _filterChip(String key, String label) {
    final on = _prodFilter == key;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _prodFilter = key),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: on ? _green : Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: on ? _green : AppColors.line),
          ),
          child: Text(label,
              style: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, color: on ? Colors.white : AppColors.slate600)),
        ),
      ),
    );
  }

  Widget _sortMenu() {
    const opts = {
      'recent': 'Recent',
      'price_asc': 'Price up',
      'price_desc': 'Price down',
      'stock_asc': 'Stock up',
      'name': 'Name',
    };
    return PopupMenuButton<String>(
      onSelected: (v) => setState(() => _prodSort = v),
      itemBuilder: (_) => opts.entries
          .map((e) => PopupMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontFamily: 'Inter', fontSize: 13))))
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.line)),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.swap_vert_rounded, size: 15, color: AppColors.slate600),
          SizedBox(width: 4),
          Text('Sort', style: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.slate600)),
        ]),
      ),
    );
  }

  Widget _bulkBar() {
    final n = _prodSelected.length;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: const Color(0xFFF3F8F4), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFCDE8D5))),
        child: Row(children: [
          Text('$n selected', style: const TextStyle(fontFamily: 'Inter', fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF166534))),
          const Spacer(),
          if (n > 0) ...[
            _smallBtn(Icons.visibility_rounded, 'Publish', () => _bulkPublish(true), color: _green),
            const SizedBox(width: 8),
            _smallBtn(Icons.visibility_off_rounded, 'Hide', () => _bulkPublish(false)),
            const SizedBox(width: 8),
            _smallBtn(Icons.delete_outline_rounded, 'Delete', _bulkDelete, danger: true),
          ] else
            const Text('Tap products to select', style: TextStyle(fontFamily: 'Inter', fontSize: 11.5, color: AppColors.slate500)),
        ]),
      ),
    );
  }

  Widget _productCard(Map<String, dynamic> p) {
    final pid = (pickNum(p, ['id']) ?? 0).toInt();
    final title = pickString(p, ['title']) ?? 'Product';
    final cat = pickString(p, ['category']) ?? 'Other';
    final price = pickNum(p, ['price']);
    final stock = pickNum(p, ['stock_quantity']) ?? 0;
    final unit = pickString(p, ['unit']) ?? '';
    final published = p['is_published'] != false;
    final selected = _prodSelected.contains(pid);
    return GestureDetector(
      onTap: _prodSelect
          ? () => setState(() {
                if (selected) {
                  _prodSelected.remove(pid);
                } else {
                  _prodSelected.add(pid);
                }
              })
          : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? _green : AppColors.line, width: selected ? 1.5 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (_prodSelect) ...[
                  Icon(selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                      size: 20, color: selected ? _green : AppColors.slate500),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 15.5, color: AppColors.inkWarm)),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: const Color(0xFFEAF7EC), borderRadius: BorderRadius.circular(999)),
                  child: Text(cat, style: const TextStyle(fontFamily: 'Inter', fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF166534))),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(children: [
              Text(_money(price), style: const TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w900, fontSize: 14, color: _green)),
              const SizedBox(width: 12),
              const Icon(Icons.inventory_2_outlined, size: 13, color: AppColors.slate500),
              const SizedBox(width: 4),
              Flexible(
                child: Text('${stock % 1 == 0 ? stock.toInt() : stock} $unit',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'Inter', fontSize: 12.5, color: AppColors.slate600)),
              ),
              if (stock <= _lowStock) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xFFFAEEDA), borderRadius: BorderRadius.circular(999)),
                  child: const Text('Low', style: TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF854F0B))),
                ),
              ],
            ]),
            if (!_prodSelect) ...[
              const SizedBox(height: 10),
              Row(children: [
                const Text('Stock', style: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.slate500)),
                const SizedBox(width: 8),
                _qtyStepper(p),
              ]),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Text('In marketplace', style: TextStyle(fontFamily: 'Inter', fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.slate600)),
                  const SizedBox(width: 2),
                  Transform.scale(
                    scale: 0.85,
                    child: Switch(
                      value: published,
                      activeThumbColor: _green,
                      onChanged: (v) => _togglePublish(p, v),
                    ),
                  ),
                  const Spacer(),
                  _smallBtn(Icons.edit_rounded, 'Edit', () => _openProductSheet(existing: p), color: _green),
                  const SizedBox(width: 6),
                  _smallBtn(Icons.copy_rounded, 'Copy', () => _duplicateProduct(p)),
                  const SizedBox(width: 6),
                  _smallBtn(Icons.delete_outline_rounded, 'Delete', () => _deleteProduct(p), danger: true),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _qtyStepper(Map<String, dynamic> p) {
    final stock = (pickNum(p, ['stock_quantity']) ?? 0);
    return Container(
      decoration: BoxDecoration(color: const Color(0xFFFAF7EF), borderRadius: BorderRadius.circular(9), border: Border.all(color: AppColors.line)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _qtyBtn(Icons.remove_rounded, () => _saveQty(p, (stock - 1) < 0 ? 0 : (stock - 1))),
        Container(
          constraints: const BoxConstraints(minWidth: 40),
          alignment: Alignment.center,
          child: Text('${stock % 1 == 0 ? stock.toInt() : stock}',
              style: const TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.inkWarm)),
        ),
        _qtyBtn(Icons.add_rounded, () => _saveQty(p, stock + 1)),
      ]),
    );
  }

  Widget _qtyBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(padding: const EdgeInsets.all(7), child: Icon(icon, size: 16, color: _green)),
    );
  }

  // ---- Orders ----
  Widget _ordersSection() {
    final incoming = _orders.where((o) => _ordStore(o) == _id).toList()
      ..sort((a, b) => (pickString(b, ['created_at']) ?? '').compareTo(pickString(a, ['created_at']) ?? ''));
    final purchases = _orders.where((o) => _meId != null && _ordBuyer(o) == _meId && _ordStore(o) != _id).toList()
      ..sort((a, b) => (pickString(b, ['created_at']) ?? '').compareTo(pickString(a, ['created_at']) ?? ''));
    final fulfilling = incoming.where((o) => _fulfillStatuses.contains(_ordStatus(o))).toList();
    final attention = incoming.where((o) => _attentionStatuses.contains(_ordStatus(o))).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: _statCard('Incoming', incoming.length.toString(), Icons.inbox_rounded, _green)),
            const SizedBox(width: 10),
            Expanded(child: _statCard('My purchases', purchases.length.toString(), Icons.shopping_cart_rounded, const Color(0xFF075985))),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _statCard('Being fulfilled', fulfilling.length.toString(), Icons.local_shipping_rounded, const Color(0xFF0F7A4B))),
            const SizedBox(width: 10),
            Expanded(child: _statCard('Needs attention', attention.length.toString(), Icons.warning_amber_rounded, _gold)),
          ]),
          const SizedBox(height: 18),
          _sectionHeader('Incoming orders'),
          if (incoming.isEmpty)
            _card(child: const Text('No incoming orders yet.', style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppColors.slate600)))
          else
            ...incoming.map((o) => _orderCard(o, seller: true)),
          const SizedBox(height: 18),
          _sectionHeader('My purchases'),
          if (purchases.isEmpty)
            _card(child: const Text('No purchases yet.', style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppColors.slate600)))
          else
            ...purchases.map((o) => _orderCard(o, seller: false)),
          if (fulfilling.isNotEmpty) ...[
            const SizedBox(height: 18),
            _sectionHeader('Outgoing — fulfilment'),
            ...fulfilling.map(_outgoingCard),
          ],
        ],
      ),
    );
  }

  Widget _orderCard(Map<String, dynamic> o, {required bool seller}) {
    final oid = (pickNum(o, ['id']) ?? 0).toInt();
    final st = _ordStatus(o);
    final terminal = ['delivered', 'cancelled', 'canceled', 'refunded'].contains(st);
    final summary = _itemSummary(oid);
    final esc = _escrowOf(oid);
    final ns = _nextStage(st);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text('Order #$oid',
                  style: const TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.inkWarm)),
            ),
            _statusBadge(st),
          ]),
          const SizedBox(height: 3),
          Text(_money(_ordTotal(o)), style: const TextStyle(fontFamily: 'Inter', fontSize: 12.5, fontWeight: FontWeight.w600, color: _green)),
          if (summary.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(summary, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppColors.slate600)),
          ],
          if (seller) ...[
            if (!terminal) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (ns != null) _smallBtn(Icons.arrow_forward_rounded, 'Mark ${_stageLabel[ns]}', () => _advance(o), color: _green),
                _smallBtn(Icons.close_rounded, 'Cancel', () => _cancelOrder(o), danger: true),
              ]),
            ],
            _sellerEscrowBlock(o),
          ],
          if (!seller) ...[
            const SizedBox(height: 10),
            if (esc == null)
              Align(alignment: Alignment.centerLeft, child: _smallBtn(Icons.shield_rounded, 'Pay with escrow', () => _payOrder(o), color: _green))
            else if ((pickString(esc, ['status']) ?? '').toLowerCase() == 'pending')
              Align(alignment: Alignment.centerLeft, child: _smallBtn(Icons.credit_card_rounded, 'Pay now', () => _payOrder(o), color: _green))
            else if ((pickString(esc, ['status']) ?? '').toLowerCase() == 'held')
              Align(alignment: Alignment.centerLeft, child: _smallBtn(Icons.check_circle_rounded, 'Confirm delivery', () => _releaseEscrow(esc), color: _green))
            else
              Row(children: [const Text('Escrow: ', style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppColors.slate500)), _statusBadge(pickString(esc, ['status']) ?? '')]),
          ],
        ],
      ),
    );
  }

  Widget _sellerEscrowBlock(Map<String, dynamic> o) {
    final oid = (pickNum(o, ['id']) ?? 0).toInt();
    final esc = _escrowOf(oid);
    if (esc == null) return const SizedBox.shrink();
    final es = (pickString(esc, ['status']) ?? '').toLowerCase();
    final otpIssued = _hasValue(esc['otp_issued_at']);
    final delivered = _hasValue(esc['delivered_confirmed_at']);
    if (es == 'held' && !otpIssued) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          _smallBtn(Icons.local_shipping_rounded, 'Dispatch myself', () => _dispatchOrder(esc), color: _green),
          _smallBtn(Icons.two_wheeler_rounded, 'Request a transporter', () => _requestTransporter(oid), color: const Color(0xFF075985)),
        ]),
      );
    }
    if (es == 'held' && otpIssued && !delivered) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Align(
          alignment: Alignment.centerLeft,
          child: _smallBtn(Icons.key_rounded, 'Confirm delivery (buyer code)', () => _confirmDeliverySeller(esc), color: const Color(0xFF075985)),
        ),
      );
    }
    if (es == 'held' && delivered) {
      return const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text('Delivered — you are paid automatically after the dispute window if no dispute.',
            style: TextStyle(fontFamily: 'Inter', fontSize: 11.5, color: Color(0xFF166534))),
      );
    }
    if (es == 'disputed') {
      return const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text('Buyer reported a problem — under review.',
            style: TextStyle(fontFamily: 'Inter', fontSize: 11.5, color: Color(0xFFB91C1C))),
      );
    }
    if (es == 'released') {
      return const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text('Paid out.', style: TextStyle(fontFamily: 'Inter', fontSize: 11.5, color: Color(0xFF166534))),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _outgoingCard(Map<String, dynamic> o) {
    final oid = (pickNum(o, ['id']) ?? 0).toInt();
    final cur = _stages.indexOf(_ordStatus(o));
    const steps = ['confirmed', 'packed', 'shipped', 'out_for_delivery', 'delivered'];
    final summary = _itemSummary(oid);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text('Order #$oid',
                  style: const TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.inkWarm)),
            ),
            _statusBadge(_ordStatus(o)),
          ]),
          const SizedBox(height: 3),
          Text(_money(_ordTotal(o)), style: const TextStyle(fontFamily: 'Inter', fontSize: 12.5, fontWeight: FontWeight.w600, color: _green)),
          if (summary.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(summary, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppColors.slate600)),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: steps.map((s) {
              final reached = _stages.indexOf(s) <= cur;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: reached ? const Color(0xFFEAF7EC) : const Color(0xFFF6F4ED),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: reached ? const Color(0xFFBBF0CC) : AppColors.line),
                ),
                child: Text(_stageLabel[s] ?? s,
                    style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700, color: reached ? const Color(0xFF166534) : AppColors.slate500)),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ---- Wallet ----
  Widget _walletSection() {
    final storeOrderIds = _orders.where((o) => _ordStore(o) == _id).map((o) => (pickNum(o, ['id']) ?? 0).toInt()).toSet();
    final mine = _escrows.where((e) => storeOrderIds.contains(_asId(e['order']))).toList();
    double sum(String status) =>
        mine.where((e) => (pickString(e, ['status']) ?? '').toLowerCase() == status).fold<double>(0, (s, e) => s + (pickNum(e, ['amount']) ?? 0).toDouble());
    final settlements = mine.where((e) => (pickString(e, ['status']) ?? '').toLowerCase() == 'released').toList()
      ..sort((a, b) => (pickString(b, ['released_at']) ?? pickString(b, ['updated_at']) ?? '').compareTo(pickString(a, ['released_at']) ?? pickString(a, ['updated_at']) ?? ''));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const WalletScreen())),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                  gradient: AppColors.emeraldGrad, borderRadius: BorderRadius.circular(14)),
              child: Row(children: const [
                Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text('Open my wallet',
                      style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: Colors.white)),
                ),
                Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
              ]),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFBFD8F5))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.shield_rounded, size: 18, color: Color(0xFF075985)),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Buyer payments are held in escrow until delivery is confirmed, then released to your payout destination below.',
                    style: const TextStyle(fontFamily: 'Inter', fontSize: 12, height: 1.4, color: Color(0xFF075985))),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: _statCard('Held in escrow', _money(sum('held')), Icons.lock_rounded, const Color(0xFF075985))),
            const SizedBox(width: 10),
            Expanded(child: _statCard('Released', _money(sum('released')), Icons.check_circle_rounded, _green)),
          ]),
          const SizedBox(height: 10),
          _statCard('Awaiting funding', _money(sum('pending')), Icons.hourglass_bottom_rounded, _gold),
          const SizedBox(height: 18),
          _sectionHeader('Payout destination'),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: _payoutTab('momo', 'Mobile Money', Icons.smartphone_rounded)),
                  const SizedBox(width: 10),
                  Expanded(child: _payoutTab('bank', 'Bank', Icons.account_balance_rounded)),
                ]),
                const SizedBox(height: 12),
                _formField(_poName, 'Account holder name'),
                const SizedBox(height: 10),
                if (_poMethod == 'momo') ...[
                  Row(children: [
                    SizedBox(
                      width: 110,
                      child: _dropdown(_poNetwork, const ['MTN', 'AIRTEL'], (v) => setState(() => _poNetwork = v)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: _formField(_poPhone, 'Mobile number', number: true)),
                  ]),
                ] else ...[
                  if (_banks.isNotEmpty) ...[
                    _bankPicker(),
                    const SizedBox(height: 10),
                    _formField(_poAcct, 'Account number', number: true),
                  ] else
                    Row(children: [
                      SizedBox(width: 120, child: _formField(_poBank, 'Bank code')),
                      const SizedBox(width: 10),
                      Expanded(child: _formField(_poAcct, 'Account number', number: true)),
                    ]),
                ],
                const SizedBox(height: 14),
                GestureDetector(
                  onTap: _poSaving ? null : _savePayout,
                  child: Container(
                    height: 46,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.circular(12)),
                    child: Text(_poSaving ? 'Saving…' : 'Save destination',
                        style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 14, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _sectionHeader('Settlements'),
          if (settlements.isEmpty)
            _card(child: const Text('No released payouts yet. Funds appear here once delivery is confirmed.', style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppColors.slate600)))
          else
            ...settlements.map((e) {
              final amt = (pickNum(e, ['amount']) ?? 0).toDouble();
              final when = pickString(e, ['released_at']) ?? pickString(e, ['updated_at']) ?? '';
              final day = when.length >= 10 ? when.substring(0, 10) : when;
              final order = _asId(e['order']);
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
                child: Row(children: [
                  Container(
                    width: 36, height: 36, alignment: Alignment.center,
                    decoration: BoxDecoration(color: const Color(0xFFEAF7EC), borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.south_west_rounded, size: 17, color: Color(0xFF166534)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Order #$order', style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.inkWarm)),
                      if (day.isNotEmpty)
                        Text(day, style: const TextStyle(fontFamily: 'Inter', fontSize: 11.5, color: AppColors.slate500)),
                    ]),
                  ),
                  Text(_money(amt), style: const TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w900, fontSize: 14, color: _green)),
                ]),
              );
            }),
        ],
      ),
    );
  }

  Widget _bankPicker() {
    final items = _banks;
    String labelOf(Map<String, dynamic> b) => pickString(b, ['name', 'bank_name', 'label']) ?? 'Bank';
    String codeOf(Map<String, dynamic> b) => pickString(b, ['code', 'bank_code', 'id']) ?? '';
    final values = items.map(codeOf).where((c) => c.isNotEmpty).toList();
    final current = values.contains(_poBankCode) ? _poBankCode : null;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(11), border: Border.all(color: AppColors.line)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: current,
          hint: const Text('Select your bank', style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppColors.slate500)),
          items: items.where((b) => codeOf(b).isNotEmpty).map((b) {
            return DropdownMenuItem(
              value: codeOf(b),
              child: Text(labelOf(b), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'Inter', fontSize: 14)),
            );
          }).toList(),
          onChanged: (v) => setState(() => _poBankCode = v ?? ''),
        ),
      ),
    );
  }

  Widget _payoutTab(String m, String label, IconData icon) {
    final on = _poMethod == m;
    return GestureDetector(
      onTap: () => setState(() => _poMethod = m),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? const Color(0xFFEAF7EC) : Colors.white,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: on ? _green : AppColors.line, width: on ? 1.5 : 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: on ? _green : AppColors.slate600),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 12.5, color: on ? _green : AppColors.slate600)),
        ]),
      ),
    );
  }

  Widget _dropdown(String value, List<String> options, ValueChanged<String> onChanged) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(11), border: Border.all(color: AppColors.line)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: value,
          items: options
              .map((o) => DropdownMenuItem(value: o, child: Text(o, style: const TextStyle(fontFamily: 'Inter', fontSize: 14))))
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }

  Widget _formField(TextEditingController c, String hint, {bool number = false}) {
    return TextField(
      controller: c,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: AppColors.line)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: AppColors.line)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: _green)),
      ),
    );
  }

  // ---- Reviews ----
  List<Map<String, dynamic>> _applyReviewControls(List<Map<String, dynamic>> src) {
    final list = src.where((r) {
      final rt = (pickNum(r, ['rating']) ?? 0).round();
      switch (_revFilter) {
        case '5':
          return rt == 5;
        case '4':
          return rt == 4;
        case '3':
          return rt == 3;
        case 'low':
          return rt <= 2;
        default:
          return true;
      }
    }).toList();
    switch (_revSort) {
      case 'high':
        list.sort((a, b) => (pickNum(b, ['rating']) ?? 0).compareTo(pickNum(a, ['rating']) ?? 0));
        break;
      case 'low':
        list.sort((a, b) => (pickNum(a, ['rating']) ?? 0).compareTo(pickNum(b, ['rating']) ?? 0));
        break;
      default:
        list.sort((a, b) => (pickString(b, ['created_at']) ?? '').compareTo(pickString(a, ['created_at']) ?? ''));
    }
    return list;
  }

  String _csvCell(String v) {
    if (v.contains(',') || v.contains('"') || v.contains('\n')) {
      const q = '"';
      final escaped = v.replaceAll('"', '""');
      return '$q$escaped$q';
    }
    return v;
  }

  Future<void> _exportReviews() async {
    final rows = <String>['type,product,reviewer,rating,comment'];
    for (final r in _storeReviews) {
      rows.add([
        'store',
        '',
        _csvCell(pickString(r, ['user_name']) ?? 'Anonymous'),
        '${(pickNum(r, ['rating']) ?? 0).round()}',
        _csvCell(pickString(r, ['comment']) ?? ''),
      ].join(','));
    }
    for (final r in _productReviews) {
      rows.add([
        'product',
        _csvCell(pickString(r, ['_product']) ?? ''),
        _csvCell(pickString(r, ['user_name']) ?? 'Anonymous'),
        '${(pickNum(r, ['rating']) ?? 0).round()}',
        _csvCell(pickString(r, ['comment']) ?? ''),
      ].join(','));
    }
    await Clipboard.setData(ClipboardData(text: rows.join('\n')));
    if (mounted) showToast(context, 'Reviews CSV copied to clipboard.');
  }

  Widget _reviewsSection() {
    final all = [..._storeReviews, ..._productReviews];
    final avg = all.isEmpty ? 0.0 : all.fold<double>(0, (s, r) => s + (pickNum(r, ['rating']) ?? 0).toDouble()) / all.length;
    final positive = all.where((r) => (pickNum(r, ['rating']) ?? 0) >= 4).length;
    final positivePct = all.isEmpty ? 0 : (positive * 100 / all.length).round();
    final dist = <int, int>{for (var i = 1; i <= 5; i++) i: 0};
    for (final r in all) {
      final rt = (pickNum(r, ['rating']) ?? 0).round().clamp(1, 5);
      dist[rt] = (dist[rt] ?? 0) + 1;
    }
    final maxBar = dist.values.fold<int>(1, (m, v) => v > m ? v : m);
    final sr = _applyReviewControls(_storeReviews);
    final pr = _applyReviewControls(_productReviews);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(avg.toStringAsFixed(1),
                        style: const TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w900, fontSize: 34, color: AppColors.inkWarm)),
                    Row(children: List.generate(5, (i) => Icon(i < avg.round() ? Icons.star_rounded : Icons.star_border_rounded, size: 16, color: _gold))),
                  ]),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      children: [5, 4, 3, 2, 1].map((star) {
                        final n = dist[star] ?? 0;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(children: [
                            Text('$star', style: const TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.slate500)),
                            const Icon(Icons.star_rounded, size: 11, color: _gold),
                            const SizedBox(width: 6),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(99),
                                child: LinearProgressIndicator(
                                  value: maxBar == 0 ? 0 : n / maxBar,
                                  minHeight: 6,
                                  backgroundColor: const Color(0xFFF1EFE8),
                                  valueColor: const AlwaysStoppedAnimation(_gold),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            SizedBox(width: 18, child: Text('$n', textAlign: TextAlign.right, style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppColors.slate500))),
                          ]),
                        );
                      }).toList(),
                    ),
                  ),
                ]),
                const Divider(height: 22, color: AppColors.line),
                Row(children: [
                  _insight('${all.length}', 'Total reviews'),
                  _insight('$positivePct%', 'Positive (4★+)'),
                  _insight('${_storeReviews.length}', 'On the store'),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  _revChip('all', 'All'),
                  _revChip('5', '5★'),
                  _revChip('4', '4★'),
                  _revChip('3', '3★'),
                  _revChip('low', '≤2★'),
                ]),
              ),
            ),
            const SizedBox(width: 8),
            _revSortMenu(),
            const SizedBox(width: 6),
            if (_storeReviews.isNotEmpty || _productReviews.isNotEmpty)
              GestureDetector(
                onTap: _exportReviews,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.line)),
                  child: const Icon(Icons.ios_share_rounded, size: 16, color: AppColors.slate600),
                ),
              ),
          ]),
          const SizedBox(height: 14),
          _sectionHeader('Store reviews'),
          if (sr.isEmpty)
            _card(child: const Text('No store reviews match.', style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppColors.slate600)))
          else
            ...sr.map((r) => _reviewCard(r, null)),
          const SizedBox(height: 18),
          _sectionHeader('Product reviews'),
          if (pr.isEmpty)
            _card(child: const Text('No product reviews match.', style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppColors.slate600)))
          else
            ...pr.map((r) => _reviewCard(r, pickString(r, ['_product']))),
        ],
      ),
    );
  }

  Widget _insight(String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: const TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w900, fontSize: 17, color: AppColors.inkWarm)),
          const SizedBox(height: 2),
          Text(label, textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'Inter', fontSize: 10.5, color: AppColors.slate500)),
        ],
      ),
    );
  }

  Widget _revChip(String key, String label) {
    final on = _revFilter == key;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _revFilter = key),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: on ? _green : Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: on ? _green : AppColors.line),
          ),
          child: Text(label,
              style: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, color: on ? Colors.white : AppColors.slate600)),
        ),
      ),
    );
  }

  Widget _revSortMenu() {
    const opts = {'recent': 'Recent', 'high': 'Highest', 'low': 'Lowest'};
    return PopupMenuButton<String>(
      onSelected: (v) => setState(() => _revSort = v),
      itemBuilder: (_) => opts.entries
          .map((e) => PopupMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontFamily: 'Inter', fontSize: 13))))
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.line)),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.swap_vert_rounded, size: 15, color: AppColors.slate600),
          SizedBox(width: 4),
          Text('Sort', style: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.slate600)),
        ]),
      ),
    );
  }

  Widget _reviewCard(Map<String, dynamic> r, String? product) {
    final name = pickString(r, ['user_name']) ?? 'Anonymous';
    final rating = (pickNum(r, ['rating']) ?? 0).round();
    final comment = pickString(r, ['comment']) ?? 'No comment provided';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(name,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 13.5, color: AppColors.inkWarm)),
            ),
            Row(children: List.generate(5, (i) => Icon(i < rating ? Icons.star_rounded : Icons.star_border_rounded, size: 13, color: _gold))),
          ]),
          if (product != null) ...[
            const SizedBox(height: 2),
            Text(product, style: const TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF075985))),
          ],
          const SizedBox(height: 6),
          Text(comment, style: const TextStyle(fontFamily: 'Inter', fontSize: 12.5, color: AppColors.slate600, height: 1.4)),
        ],
      ),
    );
  }

  // ---- Ads ----
  Widget _adsSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader('Advertisements', action: _addButton('Create', _openAdSheet)),
          if (_ads.isEmpty)
            _card(child: const Text('No ads yet. Tap "Create" to launch one.', style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppColors.slate600)))
          else
            ..._ads.map(_adCard),
        ],
      ),
    );
  }

  Widget _adCard(Map<String, dynamic> a) {
    final title = pickString(a, ['title']) ?? 'Untitled';
    final active = a['is_active'] != false;
    final views = (pickNum(a, ['impressions']) ?? 0).toInt();
    final clicks = (pickNum(a, ['clicks']) ?? 0).toInt();
    final bgHex = pickString(a, ['background_color']) ?? '#10b981';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: _hexColor(bgHex), borderRadius: BorderRadius.circular(11)),
            child: const Text('Aa', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(title,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 14.5, color: AppColors.inkWarm)),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: active ? const Color(0xFFDCFCE7) : const Color(0xFFF1EFE8),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(active ? 'Live' : 'Paused',
                        style: TextStyle(fontFamily: 'Inter', fontSize: 10.5, fontWeight: FontWeight.w700, color: active ? const Color(0xFF166534) : AppColors.slate600)),
                  ),
                ]),
                const SizedBox(height: 2),
                Text('$views views · $clicks clicks', style: const TextStyle(fontFamily: 'Inter', fontSize: 11.5, color: AppColors.slate500)),
              ],
            ),
          ),
          IconButton(
            icon: Icon(active ? Icons.pause_rounded : Icons.play_arrow_rounded, color: AppColors.slate600, size: 20),
            onPressed: () => _toggleAd(a, !active),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFDC2626), size: 20),
            onPressed: () => _deleteAd(a),
          ),
        ],
      ),
    );
  }

  Color _hexColor(String hex) {
    var h = hex.replaceAll('#', '').trim();
    if (h.length == 6) h = 'FF$h';
    final v = int.tryParse(h, radix: 16);
    return v == null ? _green : Color(v);
  }

  // ---- Sales Statistics ----
  String _shortMoney(num v) {
    final n = v.round();
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}k';
    return '$n';
  }

  List<List<dynamic>> _revenueBuckets() {
    final now = DateTime.now();
    final orders = _orders.where((o) => _ordStore(o) == _id && !_cancelled(_ordStatus(o))).toList();
    double sumWhere(bool Function(DateTime) test) {
      double s = 0;
      for (final o in orders) {
        final dt = DateTime.tryParse(pickString(o, ['created_at']) ?? '');
        if (dt != null && test(dt)) s += _ordTotal(o);
      }
      return s;
    }

    final out = <List<dynamic>>[];
    if (_salesBucket == 'day') {
      final base = DateTime(now.year, now.month, now.day);
      for (int i = 6; i >= 0; i--) {
        final d = base.subtract(Duration(days: i));
        out.add(['${d.day}/${d.month}', sumWhere((dt) => dt.year == d.year && dt.month == d.month && dt.day == d.day)]);
      }
    } else if (_salesBucket == 'week') {
      final monday = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
      for (int w = 5; w >= 0; w--) {
        final start = monday.subtract(Duration(days: w * 7));
        final end = start.add(const Duration(days: 7));
        out.add(['${start.day}/${start.month}', sumWhere((dt) => !dt.isBefore(start) && dt.isBefore(end))]);
      }
    } else {
      const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      for (int m = 5; m >= 0; m--) {
        final d0 = DateTime(now.year, now.month - m, 1);
        out.add([months[d0.month], sumWhere((dt) => dt.year == d0.year && dt.month == d0.month)]);
      }
    }
    return out;
  }

  Widget _salesSection() {
    final active = _orders.where((o) => _ordStore(o) == _id && !_cancelled(_ordStatus(o))).toList();
    final revenue = active.fold<double>(0, (s, o) => s + _ordTotal(o));
    final count = active.length;
    final aov = count == 0 ? 0.0 : revenue / count;
    final buckets = _revenueBuckets();
    final maxV = buckets.fold<double>(1, (m, b) => (b[1] as double) > m ? b[1] as double : m);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: _statCard('Revenue', _money(revenue), Icons.payments_rounded, _green)),
            const SizedBox(width: 10),
            Expanded(child: _statCard('Orders', count.toString(), Icons.receipt_long_rounded, const Color(0xFF075985))),
          ]),
          const SizedBox(height: 10),
          _statCard('Average order', _money(aov), Icons.bar_chart_rounded, _gold),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: _sectionHeader('Revenue trend')),
            _bucketChip('day', 'Day'),
            const SizedBox(width: 6),
            _bucketChip('week', 'Week'),
            const SizedBox(width: 6),
            _bucketChip('month', 'Month'),
          ]),
          _card(
            child: SizedBox(
              height: 168,
              child: revenue == 0
                  ? const Center(child: Text('No revenue in this period yet.', style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppColors.slate500)))
                  : Row(crossAxisAlignment: CrossAxisAlignment.end, children: buckets.map((b) => _bar(b[0] as String, b[1] as double, maxV)).toList()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bucketChip(String key, String label) {
    final on = _salesBucket == key;
    return GestureDetector(
      onTap: () => setState(() => _salesBucket = key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: on ? _green : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: on ? _green : AppColors.line),
        ),
        child: Text(label, style: TextStyle(fontFamily: 'Inter', fontSize: 11.5, fontWeight: FontWeight.w600, color: on ? Colors.white : AppColors.slate600)),
      ),
    );
  }

  Widget _bar(String label, double value, double maxV) {
    final ratio = maxV <= 0 ? 0.0 : (value / maxV).clamp(0.0, 1.0);
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(value > 0 ? _shortMoney(value) : '',
              maxLines: 1, overflow: TextOverflow.visible,
              style: const TextStyle(fontFamily: 'Inter', fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.slate600)),
          const SizedBox(height: 4),
          SizedBox(
            height: 108,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: ratio <= 0 ? 0.02 : ratio,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: const BoxDecoration(color: _green, borderRadius: BorderRadius.vertical(top: Radius.circular(6))),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'Inter', fontSize: 9.5, color: AppColors.slate500)),
        ],
      ),
    );
  }

  // ---- Product Performance ----
  Widget _performanceSection() {
    final storeOrderIds = _orders
        .where((o) => _ordStore(o) == _id && !_cancelled(_ordStatus(o)))
        .map((o) => (pickNum(o, ['id']) ?? 0).toInt())
        .toSet();
    final stats = <int, Map<String, dynamic>>{};
    for (final it in _items) {
      if (!storeOrderIds.contains(_asId(it['order']))) continue;
      final pid = _asId(it['product']);
      final qty = (pickNum(it, ['quantity']) ?? 0).toDouble();
      final prod = _products.firstWhere((p) => (pickNum(p, ['id']) ?? -1).toInt() == pid, orElse: () => {});
      final price = (pickNum(prod, ['price']) ?? 0).toDouble();
      final rev = (pickNum(it, ['subtotal']) ?? pickNum(it, ['total']) ?? (qty * price)).toDouble();
      final s = stats.putIfAbsent(pid, () => {'name': pickString(prod, ['title']) ?? 'Product #$pid', 'units': 0.0, 'revenue': 0.0});
      s['units'] = (s['units'] as double) + qty;
      s['revenue'] = (s['revenue'] as double) + rev;
    }
    final rows = stats.values.toList();
    if (_perfSort == 'units') {
      rows.sort((a, b) => (b['units'] as double).compareTo(a['units'] as double));
    } else {
      rows.sort((a, b) => (b['revenue'] as double).compareTo(a['revenue'] as double));
    }
    final totalUnits = rows.fold<double>(0, (s, r) => s + (r['units'] as double));
    final maxRev = rows.fold<double>(1, (m, r) => (r['revenue'] as double) > m ? r['revenue'] as double : m);
    final best = rows.isEmpty ? '—' : (rows.first['name'] as String);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: _statCard('Units sold', (totalUnits % 1 == 0 ? totalUnits.toInt() : totalUnits).toString(), Icons.sell_rounded, _green)),
            const SizedBox(width: 10),
            Expanded(child: _statCard('Products sold', rows.length.toString(), Icons.category_rounded, const Color(0xFF075985))),
          ]),
          const SizedBox(height: 10),
          _card(
            child: Row(children: [
              Container(
                width: 36, height: 36, alignment: Alignment.center,
                decoration: BoxDecoration(color: _gold, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.emoji_events_rounded, size: 18, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Best seller', style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppColors.slate500)),
                  Text(best, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.inkWarm)),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: _sectionHeader('Breakdown')),
            _perfChip('revenue', 'Revenue'),
            const SizedBox(width: 6),
            _perfChip('units', 'Units'),
          ]),
          if (rows.isEmpty)
            _card(child: const Text('No sales yet — performance appears once orders come in.', style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppColors.slate600)))
          else
            ...rows.map((r) {
              final rev = r['revenue'] as double;
              final units = r['units'] as double;
              final ratio = maxRev <= 0 ? 0.0 : (rev / maxRev).clamp(0.0, 1.0);
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text(r['name'] as String,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 14.5, color: AppColors.inkWarm)),
                      ),
                      Text(_money(rev), style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 13, color: _green)),
                    ]),
                    const SizedBox(height: 3),
                    Text('${units % 1 == 0 ? units.toInt() : units} sold',
                        style: const TextStyle(fontFamily: 'Inter', fontSize: 11.5, color: AppColors.slate500)),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 7,
                        backgroundColor: const Color(0xFFF1EFE8),
                        valueColor: const AlwaysStoppedAnimation(_green),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _perfChip(String key, String label) {
    final on = _perfSort == key;
    return GestureDetector(
      onTap: () => setState(() => _perfSort = key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: on ? _green : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: on ? _green : AppColors.line),
        ),
        child: Text(label, style: TextStyle(fontFamily: 'Inter', fontSize: 11.5, fontWeight: FontWeight.w600, color: on ? Colors.white : AppColors.slate600)),
      ),
    );
  }
}

// ----- Add / edit product sheet -----
class _ProductSheet extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const _ProductSheet({this.existing});
  @override
  State<_ProductSheet> createState() => _ProductSheetState();
}

class _ProductSheetState extends State<_ProductSheet> {
  final _title = TextEditingController();
  final _price = TextEditingController();
  final _stock = TextEditingController();
  final _desc = TextEditingController();
  String _category = 'Produce';
  String _unit = 'kg';
  bool _published = true;
  String? _err;
  final ImagePicker _picker = ImagePicker();
  String? _imagePath;
  String? _existingImage;

  static const _cats = ['Crops', 'Livestock', 'Produce', 'Equipment', 'Other'];
  static const _units = ['kg', 'g', 'lbs', 'pcs', 'boxes', 'bags', 'liters'];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _title.text = pickString(e, ['title']) ?? '';
      _price.text = (pickNum(e, ['price']) ?? '').toString();
      _stock.text = (pickNum(e, ['stock_quantity']) ?? '').toString();
      _desc.text = pickString(e, ['description']) ?? '';
      final c = pickString(e, ['category']);
      if (c != null && _cats.contains(c)) _category = c;
      final u = pickString(e, ['unit']);
      if (u != null && _units.contains(u)) _unit = u;
      _published = e['is_published'] != false;
      _existingImage = pickString(e, ['image', 'image_url']);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _price.dispose();
    _stock.dispose();
    _desc.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _title.text.trim();
    final price = double.tryParse(_price.text.trim());
    final stock = double.tryParse(_stock.text.trim());
    if (title.isEmpty || price == null || stock == null) {
      setState(() => _err = 'Fill title, price and stock.');
      return;
    }
    Navigator.pop(context, <String, dynamic>{
      'title': title,
      'category': _category,
      'price': price,
      'stock_quantity': stock,
      'unit': _unit,
      'description': _desc.text.trim(),
      'is_published': _published,
      '_imagePath': _imagePath,
    });
  }

  Future<void> _pickImage() async {
    try {
      final x = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 82);
      if (x != null) setState(() => _imagePath = x.path);
    } catch (e) {
      logSwallowed('ProductSheet.pickImage', e);
    }
  }

  Widget _imgPlaceholder() => Container(
        width: 64,
        height: 64,
        alignment: Alignment.center,
        color: const Color(0xFFF1EFE8),
        child: const Icon(Icons.inventory_2_outlined, size: 22, color: AppColors.slate500),
      );

  Widget _imageRow() {
    Widget thumb;
    if (_imagePath != null) {
      thumb = Image.file(File(_imagePath!), width: 64, height: 64, fit: BoxFit.cover);
    } else if (_existingImage != null && _existingImage!.startsWith('http')) {
      thumb = Image.network(_existingImage!, width: 64, height: 64, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _imgPlaceholder());
    } else {
      thumb = _imgPlaceholder();
    }
    final hasImage = _imagePath != null || (_existingImage?.isNotEmpty ?? false);
    return Row(children: [
      ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(width: 64, height: 64, child: thumb)),
      const SizedBox(width: 12),
      Expanded(
        child: GestureDetector(
          onTap: _pickImage,
          child: Container(
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(11), border: Border.all(color: AppColors.line)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.image_rounded, size: 16, color: _green),
              const SizedBox(width: 6),
              Text(hasImage ? 'Change photo' : 'Add photo',
                  style: const TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w700, color: _green)),
            ]),
          ),
        ),
      ),
      if (_imagePath != null) ...[
        const SizedBox(width: 8),
        GestureDetector(onTap: () => setState(() => _imagePath = null), child: const Icon(Icons.close_rounded, size: 20, color: AppColors.slate500)),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: const BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 42, height: 4, decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(99)))),
              const SizedBox(height: 14),
              Text(widget.existing == null ? 'Add product' : 'Edit product',
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
              _imageRow(),
              const SizedBox(height: 12),
              _field(_title, 'Product title'),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _pick(_category, _cats, (v) => setState(() => _category = v))),
                const SizedBox(width: 10),
                Expanded(child: _pick(_unit, _units, (v) => setState(() => _unit = v))),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _field(_price, 'Price', number: true)),
                const SizedBox(width: 10),
                Expanded(child: _field(_stock, 'Stock', number: true)),
              ]),
              const SizedBox(height: 10),
              _field(_desc, 'Description (optional)', lines: 2),
              const SizedBox(height: 12),
              Row(children: [
                const Text('Publish to marketplace', style: TextStyle(fontFamily: 'Inter', fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.slate700)),
                const Spacer(),
                Switch(value: _published, activeThumbColor: _green, onChanged: (v) => setState(() => _published = v)),
              ]),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: _submit,
                child: Container(
                  height: 50,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.circular(13)),
                  child: Text(widget.existing == null ? 'Add product' : 'Save changes',
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
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: _green)),
      ),
    );
  }

  Widget _pick(String value, List<String> options, ValueChanged<String> onChanged) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(11), border: Border.all(color: AppColors.line)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: value,
          items: options.map((o) => DropdownMenuItem(value: o, child: Text(o, style: const TextStyle(fontFamily: 'Inter', fontSize: 14)))).toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

// ----- Create ad sheet (basic) -----
class _AdSheet extends StatefulWidget {
  const _AdSheet();
  @override
  State<_AdSheet> createState() => _AdSheetState();
}

class _AdSheetState extends State<_AdSheet> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _cta = TextEditingController(text: 'Shop Now');
  int _days = 7;
  String _bg = '#2E7D46';
  String _textMode = 'auto'; // auto | light | dark
  String? _err;
  final ImagePicker _picker = ImagePicker();
  String? _imagePath;

  static const _durations = [
    [1, '1 day'],
    [7, '1 week'],
    [14, '2 weeks'],
    [30, '1 month'],
  ];

  static const _swatches = [
    '#2E7D46', '#0F7A4B', '#22432C', '#075985',
    '#C49A2E', '#B45309', '#B91C1C', '#7C3AED', '#1F2937',
  ];

  // name, headline, description, cta, bg
  static const _templates = [
    ['Harvest Sale', 'Harvest Sale', 'Fresh stock just in — save while it lasts.', 'Shop Now', '#2E7D46'],
    ['New Arrival', 'New Arrival', 'Be the first to grab our latest produce.', 'Discover', '#075985'],
    ['Limited Offer', 'Limited Offer', 'Special pricing for a short time only.', 'Grab It', '#C49A2E'],
    ['Bulk Deal', 'Bulk Deal', 'Buy more, pay less on wholesale orders.', 'Get Quote', '#22432C'],
  ];

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _cta.dispose();
    super.dispose();
  }

  Color _hex(String h) {
    var s = h.replaceAll('#', '').trim();
    if (s.length == 6) s = 'FF$s';
    final v = int.tryParse(s, radix: 16);
    return v == null ? _green : Color(v);
  }

  bool get _bgIsDark => _hex(_bg).computeLuminance() < 0.5;

  String get _textHex {
    switch (_textMode) {
      case 'light':
        return '#ffffff';
      case 'dark':
        return '#1f2937';
      default:
        return _bgIsDark ? '#ffffff' : '#1f2937';
    }
  }

  void _applyTemplate(List<String> t) {
    setState(() {
      _title.text = t[1];
      _desc.text = t[2];
      _cta.text = t[3];
      _bg = t[4];
      _textMode = 'auto';
    });
  }

  void _submit() {
    final title = _title.text.trim();
    final desc = _desc.text.trim();
    if (title.isEmpty || desc.isEmpty) {
      setState(() => _err = 'Add a headline and a description.');
      return;
    }
    Navigator.pop(context, <String, dynamic>{
      'title': title,
      'description': desc,
      'cta_text': _cta.text.trim().isEmpty ? 'Shop Now' : _cta.text.trim(),
      'duration_days': _days,
      'background_color': _bg,
      'text_color': _textHex,
      '_imagePath': _imagePath,
    });
  }

  Future<void> _pickImage() async {
    try {
      final x = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 82);
      if (x != null) setState(() => _imagePath = x.path);
    } catch (e) {
      logSwallowed('AdSheet.pickImage', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: const BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 42, height: 4, decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(99)))),
              const SizedBox(height: 14),
              const Text('Advertisement studio',
                  style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 19, color: AppColors.inkWarm)),
              const SizedBox(height: 12),
              _preview(),
              const SizedBox(height: 16),
              if (_err != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFFCA5A5))),
                  child: Text(_err!, style: const TextStyle(fontFamily: 'Inter', fontSize: 12.5, color: Color(0xFFDC2626))),
                ),
                const SizedBox(height: 12),
              ],
              _label('Quick start'),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _templates.map((t) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => _applyTemplate(t),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: AppColors.line),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Container(width: 12, height: 12, decoration: BoxDecoration(color: _hex(t[4]), shape: BoxShape.circle)),
                            const SizedBox(width: 7),
                            Text(t[0], style: const TextStyle(fontFamily: 'Inter', fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.slate700)),
                          ]),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 14),
              _field(_title, 'Headline'),
              const SizedBox(height: 10),
              _field(_desc, 'Description', lines: 2),
              const SizedBox(height: 10),
              _field(_cta, 'Button text'),
              const SizedBox(height: 14),
              _label('Background colour'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _swatches.map((s) {
                  final on = _bg.toLowerCase() == s.toLowerCase();
                  return GestureDetector(
                    onTap: () => setState(() => _bg = s),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: _hex(s),
                        shape: BoxShape.circle,
                        border: Border.all(color: on ? AppColors.inkWarm : Colors.white, width: on ? 2.5 : 2),
                        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 4, offset: Offset(0, 1))],
                      ),
                      child: on ? const Icon(Icons.check_rounded, size: 16, color: Colors.white) : null,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              _label('Text colour'),
              const SizedBox(height: 8),
              Row(children: [
                _textModeChip('auto', 'Auto'),
                const SizedBox(width: 8),
                _textModeChip('light', 'Light'),
                const SizedBox(width: 8),
                _textModeChip('dark', 'Dark'),
              ]),
              const SizedBox(height: 14),
              _label('Duration'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _durations.map((d) {
                  final on = _days == d[0];
                  return GestureDetector(
                    onTap: () => setState(() => _days = d[0] as int),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                      decoration: BoxDecoration(
                        color: on ? _green : Colors.white,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: on ? _green : AppColors.line),
                      ),
                      child: Text(d[1] as String,
                          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 12.5, color: on ? Colors.white : AppColors.slate700)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              _label('Image (optional)'),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _pickImage,
                child: Container(
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(11), border: Border.all(color: AppColors.line)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_imagePath == null ? Icons.add_photo_alternate_rounded : Icons.check_circle_rounded, size: 16, color: _green),
                    const SizedBox(width: 6),
                    Text(_imagePath == null ? 'Add image' : 'Image added — tap to change',
                        style: const TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w700, color: _green)),
                    if (_imagePath != null) ...[
                      const SizedBox(width: 10),
                      GestureDetector(onTap: () => setState(() => _imagePath = null), child: const Icon(Icons.close_rounded, size: 18, color: AppColors.slate500)),
                    ],
                  ]),
                ),
              ),
              const SizedBox(height: 18),
              GestureDetector(
                onTap: _submit,
                child: Container(
                  height: 50,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.circular(13)),
                  child: const Text('Launch advertisement',
                      style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, color: Colors.white, fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _preview() {
    final bg = _hex(_bg);
    final txt = _hex(_textHex);
    final headline = _title.text.trim().isEmpty ? 'Your headline' : _title.text.trim();
    final desc = _desc.text.trim().isEmpty ? 'Your advertisement description shows here.' : _desc.text.trim();
    final cta = _cta.text.trim().isEmpty ? 'Shop Now' : _cta.text.trim();
    final ctaBg = _textHex == '#ffffff' ? Colors.white.withValues(alpha: 0.18) : Colors.black.withValues(alpha: 0.10);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_imagePath != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(File(_imagePath!), height: 96, width: double.infinity, fit: BoxFit.cover),
            ),
            const SizedBox(height: 12),
          ],
          Text('SPONSORED', style: TextStyle(fontFamily: 'Inter', fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 1.5, color: txt.withValues(alpha: 0.7))),
          const SizedBox(height: 8),
          Text(headline,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w900, fontSize: 21, height: 1.1, color: txt)),
          const SizedBox(height: 6),
          Text(desc,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'Inter', fontSize: 13, height: 1.35, color: txt.withValues(alpha: 0.9))),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(color: ctaBg, borderRadius: BorderRadius.circular(999), border: Border.all(color: txt.withValues(alpha: 0.35))),
            child: Text(cta, style: TextStyle(fontFamily: 'Inter', fontSize: 12.5, fontWeight: FontWeight.w700, color: txt)),
          ),
        ],
      ),
    );
  }

  Widget _textModeChip(String key, String label) {
    final on = _textMode == key;
    return GestureDetector(
      onTap: () => setState(() => _textMode = key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: on ? _green : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: on ? _green : AppColors.line),
        ),
        child: Text(label,
            style: TextStyle(fontFamily: 'Inter', fontSize: 12.5, fontWeight: FontWeight.w600, color: on ? Colors.white : AppColors.slate700)),
      ),
    );
  }

  Widget _label(String t) => Text(t, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 12.5, color: AppColors.slate700));

  Widget _field(TextEditingController c, String hint, {int lines = 1}) {
    return TextField(
      controller: c,
      maxLines: lines,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: AppColors.line)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: AppColors.line)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: _green)),
      ),
    );
  }
}

// ----- Request-transporter sheet (create job -> show pickup code -> SMS link / cancel) -----
class _TransporterSheet extends StatefulWidget {
  final int orderId;
  final Map<String, dynamic>? existingJob;
  const _TransporterSheet({required this.orderId, this.existingJob});
  @override
  State<_TransporterSheet> createState() => _TransporterSheetState();
}

class _TransporterSheetState extends State<_TransporterSheet> {
  Map<String, dynamic>? _job;
  final _pickup = TextEditingController();
  final _drop = TextEditingController();
  final _fee = TextEditingController();
  final _phone = TextEditingController();
  final _riderName = TextEditingController();
  String _vehicle = '';
  bool _busy = false;
  String _linkOut = '';

  static const _vehicles = [
    ['', 'Any'],
    ['boda', 'Boda boda'],
    ['pickup', 'Pickup'],
    ['truck', 'Truck'],
    ['taxi', 'Taxi / van'],
    ['bicycle', 'Bicycle'],
  ];

  StoreRepository get _repo => StoreRepository(context.read<DioClient>().dio);

  @override
  void initState() {
    super.initState();
    _job = widget.existingJob;
  }

  @override
  void dispose() {
    _pickup.dispose();
    _drop.dispose();
    _fee.dispose();
    _phone.dispose();
    _riderName.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() => _busy = true);
    try {
      final data = await _repo.createDeliveryJob({
        'order': widget.orderId,
        'pickup_location': _pickup.text.trim(),
        'drop_location': _drop.text.trim(),
        'vehicle_type_required': _vehicle,
        'offered_fee': num.tryParse(_fee.text.trim()) ?? 0,
      });
      if (!mounted) return;
      setState(() {
        _job = (data is Map) ? Map<String, dynamic>.from(data) : null;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showToast(context, friendlyError(e), success: false);
    }
  }

  Future<void> _sendLink() async {
    final ph = _phone.text.trim();
    if (ph.isEmpty) {
      setState(() => _linkOut = 'Enter the rider phone number.');
      return;
    }
    setState(() {
      _busy = true;
      _linkOut = 'Sending…';
    });
    final jid = (pickNum(_job!, ['id']) ?? 0).toInt();
    try {
      await _repo.sendRiderLink(jid, {'phone': ph, 'name': _riderName.text.trim()});
      if (!mounted) return;
      setState(() {
        _busy = false;
        _linkOut = 'Link sent. Give the rider the pickup code above.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _linkOut = friendlyError(e);
      });
    }
  }

  Future<void> _cancelJob() async {
    final jid = (pickNum(_job!, ['id']) ?? 0).toInt();
    try {
      await _repo.cancelDeliveryJob(jid);
      if (!mounted) return;
      showToast(context, 'Request cancelled.');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), success: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: const BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 42, height: 4, decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(99)))),
              const SizedBox(height: 14),
              _job == null ? _createView() : _jobView(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _createView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Request a transporter',
            style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 19, color: AppColors.inkWarm)),
        const SizedBox(height: 4),
        const Text('A registered rider will pick up and deliver. You will get a pickup code to read at hand-over.',
            style: TextStyle(fontFamily: 'Inter', fontSize: 12.5, color: AppColors.slate600)),
        const SizedBox(height: 14),
        _field(_pickup, 'Pickup location'),
        const SizedBox(height: 10),
        _field(_drop, 'Drop location'),
        const SizedBox(height: 10),
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(11), border: Border.all(color: AppColors.line)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: _vehicle,
              items: _vehicles
                  .map((v) => DropdownMenuItem(value: v[0], child: Text(v[1], style: const TextStyle(fontFamily: 'Inter', fontSize: 14))))
                  .toList(),
              onChanged: (v) => setState(() => _vehicle = v ?? ''),
            ),
          ),
        ),
        const SizedBox(height: 10),
        _field(_fee, 'Offered fee (UGX, optional)', number: true),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: _busy ? null : _create,
          child: Container(
            height: 50,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.circular(13)),
            child: Text(_busy ? 'Requesting…' : 'Request',
                style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, color: Colors.white, fontSize: 15)),
          ),
        ),
      ],
    );
  }

  Widget _jobView() {
    final code = pickString(_job!, ['pickup_code']);
    final status = pickString(_job!, ['status']) ?? 'open';
    final cancellable = status == 'open' || status == 'accepted';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Transporter request',
            style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 19, color: AppColors.inkWarm)),
        const SizedBox(height: 4),
        Text('Status: $status', style: const TextStyle(fontFamily: 'Inter', fontSize: 12.5, color: AppColors.slate600)),
        const SizedBox(height: 14),
        if (code != null && code.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF7EC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFA7F3CC)),
            ),
            child: Column(
              children: [
                const Text('PICKUP CODE',
                    style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: Color(0xFF166534))),
                const SizedBox(height: 4),
                Text(code,
                    style: const TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w900, fontSize: 30, letterSpacing: 4, color: Color(0xFF166534))),
                const SizedBox(height: 4),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text('Read this to the rider at pickup. Do not share it before they collect the goods.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppColors.slate600)),
                ),
              ],
            ),
          )
        else
          const Text('No rider assigned yet, or pickup is already complete.',
              style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppColors.slate600)),
        const SizedBox(height: 16),
        const Text('Send a one-time link to a rider by SMS',
            style: TextStyle(fontFamily: 'Inter', fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.slate700)),
        const SizedBox(height: 8),
        _field(_phone, 'Rider phone (07xx xxx xxx)', number: true),
        const SizedBox(height: 10),
        _field(_riderName, 'Rider name (optional)'),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: _busy ? null : _sendLink,
          child: Container(
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: const Color(0xFF075985), borderRadius: BorderRadius.circular(12)),
            child: const Text('Send SMS link',
                style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, color: Colors.white, fontSize: 14)),
          ),
        ),
        if (_linkOut.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(_linkOut, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppColors.slate600)),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            if (cancellable)
              Expanded(
                child: GestureDetector(
                  onTap: _cancelJob,
                  child: Container(
                    height: 46,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFCA5A5)),
                    ),
                    child: const Text('Cancel request',
                        style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, color: Color(0xFFDC2626), fontSize: 14)),
                  ),
                ),
              ),
            if (cancellable) const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.circular(12)),
                  child: const Text('Done',
                      style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, color: Colors.white, fontSize: 14)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _field(TextEditingController c, String hint, {bool number = false}) {
    return TextField(
      controller: c,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: AppColors.line)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: AppColors.line)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: _green)),
      ),
    );
  }
}

