import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/network/api_service.dart';
import '../../core/network/dio_client.dart';
import '../../core/i18n/locale_provider.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/json_utils.dart';
import '../../providers/cart_model.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/farmland_background.dart';
import '../../widgets/state_views.dart';
import '../wallet/wallet_screen.dart';
import 'product_bits.dart';
import 'product_detail_sheet.dart';
import 'cart_sheet.dart';

const Color _heroDark = Color(0xFF22432C);

class _Cat {
  final String label;
  final String? match;
  const _Cat(this.label, this.match);
}

class MarketplaceScreen extends StatefulWidget {
  const MarketplaceScreen({super.key});
  @override
  State<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends State<MarketplaceScreen> {
  final _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _all = [];
  bool _loading = true;
  String? _error;

  String _query = '';
  String _cat = 'all';
  String _sort = 'relevance';
  double? _minRating;
  double? _min;
  double? _max;

  static const _cats = <_Cat>[
    _Cat('All', null),
    _Cat('Livestock', 'livestock'),
    _Cat('Crops', 'crop'),
    _Cat('Machinery', 'machin'),
    _Cat('Chemicals', 'chemical'),
  ];

  bool get _filterActive =>
      _sort != 'relevance' || _minRating != null || _min != null || _max != null;

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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ApiService(context.read<DioClient>().dio);
      final data = await api.list(Api.products);
      if (!mounted) return;
      setState(() {
        _all = data;
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
    var list = [..._all];
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list.where((p) => (pickString(p, ['title', 'name']) ?? '').toLowerCase().contains(q)).toList();
    }
    if (_cat != 'all') {
      list = list.where((p) => (pickString(p, ['category']) ?? '').toLowerCase().contains(_cat)).toList();
    }
    if (_minRating != null) {
      list = list.where((p) => (pickNum(p, ['average_rating']) ?? 0) >= _minRating!).toList();
    }
    if (_min != null) {
      list = list.where((p) => (pickNum(p, ['price']) ?? 0) >= _min!).toList();
    }
    if (_max != null) {
      list = list.where((p) => (pickNum(p, ['price']) ?? 0) <= _max!).toList();
    }
    if (_sort == 'price-asc') {
      list.sort((a, b) => (pickNum(a, ['price']) ?? 0).compareTo(pickNum(b, ['price']) ?? 0));
    } else if (_sort == 'price-desc') {
      list.sort((a, b) => (pickNum(b, ['price']) ?? 0).compareTo(pickNum(a, ['price']) ?? 0));
    } else if (_sort == 'rating') {
      list.sort((a, b) => (pickNum(b, ['average_rating']) ?? 0).compareTo(pickNum(a, ['average_rating']) ?? 0));
    }
    return list;
  }

  int get _sellers =>
      _all.map((p) => p['store'] ?? pickString(p, ['store_name'])).where((x) => x != null).toSet().length;

  void _add(Map<String, dynamic> p) {
    final ok = context.read<CartModel>().add(p);
    final stock = (pickNum(p, ['stock_quantity']) ?? 0).toInt();
    showToast(context,
        ok ? '${pickString(p, ['title']) ?? 'Item'} added to cart' : (stock <= 0 ? 'Out of stock' : 'Stock limit reached'));
  }

  void _openWallet() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WalletScreen()));
  }

  Future<void> _openFilters() async {
    final r = await showModalBottomSheet<_FilterResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FilterSheet(sort: _sort, minRating: _minRating, min: _min, max: _max),
    );
    if (r != null) {
      setState(() {
        _sort = r.sort;
        _minRating = r.minRating;
        _min = r.min;
        _max = r.max;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cols = Responsive.gridColumns(context, phone: 2, tablet: 3, desktop: 4);
    final cart = context.watch<CartModel>();
    final view = _view;

    return Stack(
      children: [
        Positioned.fill(
          child: MaxWidthBody(
            child: RefreshIndicator(
            onRefresh: _load,
            child: CustomScrollView(
              slivers: [
                SliverAppBar(
                  pinned: true,
                  expandedHeight: 168,
                  toolbarHeight: 56,
                  backgroundColor: _heroDark,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  automaticallyImplyLeading: false,
                  systemOverlayStyle: SystemUiOverlayStyle.light,
                  leading: IconButton(
                    tooltip: context.tr('Wallet'),
                    icon: const Icon(Icons.account_balance_wallet_rounded, color: Colors.white),
                    onPressed: _openWallet,
                  ),
                  // Always-visible title in the bar's toolbar.
                  flexibleSpace: FlexibleSpaceBar(
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
                        Padding(
                          padding: const EdgeInsets.only(top: 56, bottom: 56),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text.rich(
                                  TextSpan(
                                    style: const TextStyle(
                                        fontFamily: 'Fraunces',
                                        fontWeight: FontWeight.w900,
                                        fontSize: 28,
                                        height: 1.05,
                                        color: Colors.white),
                                    children: [
                                      const TextSpan(text: 'Agricore '),
                                      TextSpan(
                                        text: context.tr('Marketplace'),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontStyle: FontStyle.italic,
                                            color: AppColors.gold),
                                      ),
                                    ],
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 4),
                                Text(context.tr('Where Farmers and Markets Meet'),
                                    style: TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: 12.5,
                                        letterSpacing: 0.3,
                                        color: Colors.white.withValues(alpha: 0.9))),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  bottom: PreferredSize(
                    preferredSize: const Size.fromHeight(56),
                    child: _searchRow(cart.count),
                  ),
                ),
                SliverToBoxAdapter(child: _chipsRow()),
                SliverToBoxAdapter(child: _summary(view.length)),
                if (_loading)
                  const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.only(top: 60), child: LoadingView()))
                else if (_error != null)
                  SliverToBoxAdapter(
                      child: Padding(
                          padding: const EdgeInsets.only(top: 40), child: ErrorView(message: _error!, onRetry: _load)))
                else if (view.isEmpty)
                  SliverToBoxAdapter(
                      child: Padding(
                          padding: const EdgeInsets.only(top: 40),
                          child: EmptyView(text: context.tr('No products match your filters.'), icon: Icons.storefront_outlined)))
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(16, 4, 16, cart.count > 0 ? 88 : 24),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cols,
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 14,
                        mainAxisExtent: 350,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (_, i) => _ProductCard(
                          product: view[i],
                          onOpen: () => showProductDetail(context, view[i], onChanged: () => setState(() {})),
                          onAdd: () => _add(view[i]),
                        ),
                        childCount: view.length,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          ),
        ),
        if (cart.count > 0)
          Positioned(left: 12, right: 12, bottom: 12, child: _cartBar(cart)),
      ],
    );
  }

  // ---- translucent square icon button used on the dark bar ----
  Widget _barButton({required IconData icon, required VoidCallback onTap, int? badge, bool dot = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          if (badge != null && badge > 0)
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: const Color(0xFFF43F5E), borderRadius: BorderRadius.circular(99)),
                child: Text('$badge',
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
              ),
            ),
          if (dot)
            Positioned(
              top: -2,
              right: -2,
              child: Container(
                width: 11,
                height: 11,
                decoration: BoxDecoration(
                    color: const Color(0xFFFDE047), shape: BoxShape.circle, border: Border.all(color: _heroDark, width: 2)),
              ),
            ),
        ],
      ),
    );
  }

  // ---- pinned cart + search + filter (inside the dark bar) ----
  Widget _searchRow(int cartCount) {
    return Container(
      color: _heroDark,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          _barButton(
              icon: Icons.shopping_cart_rounded, onTap: () => showCartSheet(context), badge: cartCount),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 46,
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: context.palette.card,
                  hintText: context.tr('Search seeds, livestock, tractors…'),
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                        ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(13), borderSide: BorderSide.none),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(13), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(13), borderSide: BorderSide.none),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _barButton(icon: Icons.tune_rounded, onTap: _openFilters, dot: _filterActive),
        ],
      ),
    );
  }

  // ---- category chips, on the page just BELOW the bar (light theme) ----
  Widget _chipsRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 0, 0),
      child: SizedBox(
        height: 36,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: _cats.map((c) {
            final on = (c.match ?? 'all') == _cat;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _cat = c.match ?? 'all'),
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: on ? AppColors.g600 : context.palette.card,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: on ? AppColors.g600 : context.palette.line),
                  ),
                  child: Text(context.tr(c.label),
                      style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: on ? Colors.white : context.palette.muted3)),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _summary(int shown) {
    final total = _all.length;
    final sellers = _sellers == 0 ? total : _sellers;
    final filtered = shown != total;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
      child: Row(
        children: [
          Flexible(
            child: Text('$total product${total == 1 ? '' : 's'} · $sellers seller${sellers == 1 ? '' : 's'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFamily: 'Inter', fontSize: 12.5, color: context.palette.muted)),
          ),
          if (filtered) ...[
            const Spacer(),
            Text('showing $shown',
                style: const TextStyle(
                    fontFamily: 'Inter', fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.g700)),
          ],
        ],
      ),
    );
  }

  // ---- sticky "view cart" bar ----
  Widget _cartBar(CartModel cart) {
    return GestureDetector(
      onTap: () => showCartSheet(context),
      child: Container(
        height: 58,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          gradient: AppColors.emeraldGrad,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: const Color(0xFF047857).withValues(alpha: 0.45), blurRadius: 24, offset: const Offset(0, 10))],
        ),
        child: Row(
          children: [
            const Icon(Icons.shopping_cart_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Text(context.tr('View cart'),
                style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, color: Colors.white, fontSize: 15)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(99)),
              child: Text('${cart.count}',
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
            ),
            const Spacer(),
            Text(money(cart.subtotal),
                style: const TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w900, color: Colors.white, fontSize: 16)),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded, color: Colors.white),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Product card — your original design; only the image is now square.
// ===========================================================================
class _ProductCard extends StatelessWidget {
  final Map<String, dynamic> product;
  final VoidCallback onOpen;
  final VoidCallback onAdd;
  const _ProductCard({required this.product, required this.onOpen, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final p = product;
    final price = pickNum(p, ['price', 'unit_price', 'amount']);
    final rating = pickNum(p, ['average_rating']) ?? 0;
    final rc = (pickNum(p, ['reviews_count']) ?? 0).toInt();
    final stock = (pickNum(p, ['stock_quantity']) ?? 0).toInt();
    final si = stockInfo(stock);
    final storeName = pickString(p, ['store_name']) ?? 'Agricore Seller';
    final verified = p['store_verified'] == true;
    final unit = pickString(p, ['unit']) ?? 'unit';
    final tag = (pickString(p, ['category']) ?? '').split(' ').first;
    final out = stock <= 0;

    return Material(
      color: context.palette.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration:
              BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: context.palette.line)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 160,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ProductImage(p),
                    if (tag.isNotEmpty)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(999)),
                          child: Text(tag.toUpperCase(),
                              style: const TextStyle(
                                  fontFamily: 'Inter', fontSize: 8.5, fontWeight: FontWeight.w800, color: AppColors.g700)),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(11, 9, 11, 11),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.storefront_rounded, size: 11, color: Color(0xFF0F7A4B)),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(storeName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF0F7A4B))),
                          ),
                          if (verified) ...[
                            const SizedBox(width: 2),
                            const Icon(Icons.verified_rounded, size: 10, color: Color(0xFF0EA5E9)),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(pickString(p, ['title', 'name']) ?? 'Product',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontFamily: 'Fraunces',
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              height: 1.12,
                              color: context.palette.ink)),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          starsRow(rating, size: 12),
                          const SizedBox(width: 4),
                          Text('$rc',
                              style: TextStyle(fontFamily: 'Inter', fontSize: 10.5, color: context.palette.muted)),
                        ],
                      ),
                      const Spacer(),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(money(price),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontFamily: 'Fraunces', fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.g600)),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(color: si.bg, borderRadius: BorderRadius.circular(999)),
                            child: Text(si.label,
                                style: TextStyle(
                                    fontFamily: 'Inter', fontSize: 8.5, fontWeight: FontWeight.w700, color: si.fg)),
                          ),
                        ],
                      ),
                      Text('per $unit',
                          style: TextStyle(fontFamily: 'Inter', fontSize: 9.5, color: context.palette.muted)),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: out ? null : onAdd,
                        child: Opacity(
                          opacity: out ? 0.5 : 1,
                          child: Container(
                            height: 38,
                            alignment: Alignment.center,
                            decoration:
                                BoxDecoration(gradient: AppColors.emeraldGrad, borderRadius: BorderRadius.circular(11)),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.add_shopping_cart_rounded, color: Colors.white, size: 15),
                                const SizedBox(width: 6),
                                Text(context.tr('Add to cart'),
                                    style: const TextStyle(
                                        fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 12.5, color: Colors.white)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// Sort + filter bottom sheet
// ===========================================================================
class _FilterResult {
  final String sort;
  final double? minRating;
  final double? min;
  final double? max;
  const _FilterResult(this.sort, this.minRating, this.min, this.max);
}

class _FilterSheet extends StatefulWidget {
  final String sort;
  final double? minRating;
  final double? min;
  final double? max;
  const _FilterSheet({required this.sort, required this.minRating, required this.min, required this.max});
  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late String _sort = widget.sort;
  late double? _rating = widget.minRating;
  late final _minCtrl = TextEditingController(text: widget.min == null ? '' : widget.min!.toStringAsFixed(0));
  late final _maxCtrl = TextEditingController(text: widget.max == null ? '' : widget.max!.toStringAsFixed(0));

  static const _sorts = {
    'relevance': 'Relevance',
    'price-asc': 'Price ↑',
    'price-desc': 'Price ↓',
    'rating': 'Top rated',
  };
  static final _ratings = <double?, String>{null: 'Any', 4.5: '4.5+', 4.0: '4.0+', 3.5: '3.5+'};

  @override
  void dispose() {
    _minCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  void _apply() {
    Navigator.pop(
      context,
      _FilterResult(
        _sort,
        _rating,
        double.tryParse(_minCtrl.text.trim()),
        double.tryParse(_maxCtrl.text.trim()),
      ),
    );
  }

  void _reset() {
    setState(() {
      _sort = 'relevance';
      _rating = null;
      _minCtrl.clear();
      _maxCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
            color: context.palette.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(color: context.palette.line, borderRadius: BorderRadius.circular(99))),
                ),
                const SizedBox(height: 14),
                Text(context.tr('Sort & filter'),
                    style: TextStyle(
                        fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 20, color: context.palette.ink)),
                const SizedBox(height: 16),
                _label(context.tr('Sort by')),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _sorts.entries
                      .map((e) => _chip(context.tr(e.value), _sort == e.key, () => setState(() => _sort = e.key)))
                      .toList(),
                ),
                const SizedBox(height: 18),
                _label(context.tr('Minimum rating')),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _ratings.entries
                      .map((e) => _chip(context.tr(e.value), _rating == e.key, () => setState(() => _rating = e.key)))
                      .toList(),
                ),
                const SizedBox(height: 18),
                _label(context.tr('Price range (UGX)')),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _numField(_minCtrl, context.tr('Min'))),
                    const Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('–')),
                    Expanded(child: _numField(_maxCtrl, context.tr('Max'))),
                  ],
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _reset,
                        style: OutlinedButton.styleFrom(
                            foregroundColor: context.palette.muted2,
                            side: BorderSide(color: context.palette.line),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13))),
                        child: Text(context.tr('Reset')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: GestureDetector(
                        onTap: _apply,
                        child: Container(
                          height: 50,
                          alignment: Alignment.center,
                          decoration:
                              BoxDecoration(gradient: AppColors.emeraldGrad, borderRadius: BorderRadius.circular(13)),
                          child: Text(context.tr('Apply'),
                              style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, color: Colors.white)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String t) => Text(t,
      style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 13, color: context.palette.muted3));

  Widget _chip(String label, bool on, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: on ? AppColors.g600 : context.palette.card,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: on ? AppColors.g600 : context.palette.line),
        ),
        child: Text(label,
            style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: on ? Colors.white : context.palette.muted3)),
      ),
    );
  }

  Widget _numField(TextEditingController c, String hint) {
    return TextField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: context.palette.card,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: BorderSide(color: context.palette.line)),
        enabledBorder:
            OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: BorderSide(color: context.palette.line)),
      ),
    );
  }
}
