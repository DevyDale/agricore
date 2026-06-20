import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/dio_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/json_utils.dart';
import '../../providers/cart_model.dart';
import '../../widgets/app_toast.dart';
import 'product_bits.dart';

Future<void> showProductDetail(BuildContext context, Map<String, dynamic> product,
    {VoidCallback? onChanged}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _DetailSheet(product: product, onChanged: onChanged),
  );
}

class _DetailSheet extends StatefulWidget {
  final Map<String, dynamic> product;
  final VoidCallback? onChanged;
  const _DetailSheet({required this.product, this.onChanged});
  @override
  State<_DetailSheet> createState() => _DetailSheetState();
}

class _DetailSheetState extends State<_DetailSheet> {
  late final _dio = context.read<DioClient>().dio;
  final _comment = TextEditingController();
  List<Map<String, dynamic>> _reviews = [];
  bool _loading = true;
  bool _posting = false;
  String? _error;
  int _myRating = 0;

  Map<String, dynamic> get p => widget.product;
  int get _id => (p['id'] is num) ? (p['id'] as num).toInt() : int.tryParse('${p['id']}') ?? 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await _dio.get('/product-reviews/', queryParameters: {'product': _id});
      setState(() {
        _reviews = asList(res.data);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = friendlyError(e);
        _loading = false;
      });
    }
  }

  double get _avg {
    if (_reviews.isEmpty) return 0;
    final s = _reviews.fold<num>(0, (a, r) => a + (pickNum(r, ['rating']) ?? 0));
    return s / _reviews.length;
  }

  Future<void> _post() async {
    if (_myRating == 0) {
      setState(() => _error = 'Tap a star rating first.');
      return;
    }
    setState(() {
      _posting = true;
      _error = null;
    });
    try {
      await _dio.post('/product-reviews/',
          data: {'product': _id, 'rating': _myRating, 'comment': _comment.text.trim()});
      // optimistic local bump on the product
      final oldN = (pickNum(p, ['reviews_count']) ?? 0).toInt();
      final oldAvg = (pickNum(p, ['average_rating']) ?? 0).toDouble();
      p['reviews_count'] = oldN + 1;
      p['average_rating'] = ((oldAvg * oldN) + _myRating) / (oldN + 1);
      _comment.clear();
      _myRating = 0;
      widget.onChanged?.call();
      if (mounted) showToast(context, 'Thanks for your review!');
      await _load();
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final price = pickNum(p, ['price', 'unit_price', 'amount']);
    final storeName = pickString(p, ['store_name']) ?? 'Agricore Seller';
    final verified = p['store_verified'] == true;
    final unit = pickString(p, ['unit']) ?? 'unit';
    final desc = pickString(p, ['description']) ?? 'Quality farm product';
    final count = (pickNum(p, ['reviews_count']) ?? _reviews.length).toInt();

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        height: size.height * 0.9,
        decoration: BoxDecoration(
            color: context.palette.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(color: context.palette.line, borderRadius: BorderRadius.circular(99))),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: SizedBox(height: 200, child: ProductImage(p, big: true)),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Icon(Icons.storefront_rounded, size: 15, color: Color(0xFF0F7A4B)),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(storeName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                                color: Color(0xFF0F7A4B))),
                      ),
                      if (verified) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.verified_rounded, size: 14, color: Color(0xFF0EA5E9)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(pickString(p, ['title', 'name']) ?? 'Product',
                      style: TextStyle(
                          fontFamily: 'Fraunces',
                          fontWeight: FontWeight.w800,
                          fontSize: 24,
                          height: 1.1,
                          color: context.palette.ink)),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Flexible(
                        child: Text(money(price),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontFamily: 'Fraunces',
                                fontWeight: FontWeight.w900,
                                fontSize: 26,
                                color: AppColors.g600)),
                      ),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('per $unit',
                            style: TextStyle(fontFamily: 'Inter', color: context.palette.muted, fontSize: 12.5)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(desc,
                      style: TextStyle(
                          fontFamily: 'Inter', fontSize: 14, height: 1.55, color: context.palette.muted2)),
                  const SizedBox(height: 18),
                  _ratingSummary(count),
                  const SizedBox(height: 16),
                  _writeReview(),
                  const SizedBox(height: 20),
                  Text('Customer reviews',
                      style: TextStyle(
                          fontFamily: 'Fraunces',
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                          color: context.palette.ink)),
                  const SizedBox(height: 10),
                  if (_loading)
                    const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(
                            child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.g600))))
                  else if (_reviews.isEmpty)
                    _emptyReviews()
                  else
                    ..._reviews.map(_reviewCard),
                ],
              ),
            ),
            _bottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _ratingSummary(int count) {
    final counts = [0, 0, 0, 0, 0];
    for (final r in _reviews) {
      final k = (pickNum(r, ['rating']) ?? 0).round();
      if (k >= 1 && k <= 5) counts[k - 1]++;
    }
    final n = _reviews.length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: context.palette.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: context.palette.line)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Text(_avg.toStringAsFixed(1),
                  style: const TextStyle(
                      fontFamily: 'Fraunces',
                      fontWeight: FontWeight.w900,
                      fontSize: 36,
                      height: 1,
                      color: AppColors.g600)),
              const SizedBox(height: 4),
              starsRow(_avg, size: 15),
              const SizedBox(height: 4),
              Text('$count review${count == 1 ? '' : 's'}',
                  style: TextStyle(fontFamily: 'Inter', fontSize: 11.5, color: context.palette.muted)),
            ],
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              children: [5, 4, 3, 2, 1].map((st) {
                final c = counts[st - 1];
                final pct = n == 0 ? 0.0 : c / n;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      SizedBox(
                          width: 22,
                          child: Text('$st★',
                              style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: context.palette.muted))),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                            value: pct,
                            minHeight: 7,
                            backgroundColor: const Color(0xFFEEF0EC),
                            valueColor: const AlwaysStoppedAnimation(AppColors.g600),
                          ),
                        ),
                      ),
                      SizedBox(
                          width: 22,
                          child: Text('$c',
                              textAlign: TextAlign.right,
                              style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: context.palette.muted))),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _writeReview() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: context.palette.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: context.palette.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Write a review',
              style: TextStyle(
                  fontFamily: 'Fraunces', fontWeight: FontWeight.w700, fontSize: 16, color: context.palette.ink)),
          const SizedBox(height: 10),
          Row(
            children: List.generate(5, (i) {
              final on = i < _myRating;
              return GestureDetector(
                onTap: () => setState(() => _myRating = i + 1),
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(on ? Icons.star_rounded : Icons.star_border_rounded,
                      size: 34, color: on ? const Color(0xFFFBBF24) : const Color(0xFFCBD5C5)),
                ),
              );
            }),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _comment,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(hintText: 'Share your experience with this product…'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Color(0xFFDC2626), fontSize: 12.5)),
          ],
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _posting ? null : _post,
            child: Container(
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(gradient: AppColors.emeraldGrad, borderRadius: BorderRadius.circular(13)),
              child: _posting
                  ? const SizedBox(
                      width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                  : const Text('Post review',
                      style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyReviews() {
    return Container(
      padding: const EdgeInsets.all(22),
      alignment: Alignment.center,
      child: Column(
        children: [
          const Icon(Icons.reviews_outlined, size: 34, color: Color(0xFFCBD5C5)),
          const SizedBox(height: 8),
          Text('No reviews yet — be the first.',
              style: TextStyle(fontFamily: 'Inter', color: context.palette.muted)),
        ],
      ),
    );
  }

  Widget _reviewCard(Map<String, dynamic> r) {
    final name = pickString(r, ['user_name', 'user', 'username']) ?? 'Buyer';
    final ini = (name.trim().isNotEmpty ? name.trim()[0] : 'B').toUpperCase();
    final comment = pickString(r, ['comment', 'text']) ?? '';
    String when = '';
    final created = pickString(r, ['created_at', 'created']);
    if (created != null) {
      final dt = DateTime.tryParse(created);
      if (dt != null) when = '${dt.day}/${dt.month}/${dt.year}';
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: context.palette.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: context.palette.line)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.emeraldGrad),
            child: Text(ini, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontFamily: 'Inter', fontWeight: FontWeight.w700, color: context.palette.ink)),
                    ),
                    Text(when,
                        style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: context.palette.muted)),
                  ],
                ),
                const SizedBox(height: 2),
                starsRow(pickNum(r, ['rating']), size: 13),
                if (comment.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(comment,
                      style: TextStyle(
                          fontFamily: 'Inter', fontSize: 13.5, height: 1.45, color: context.palette.muted2)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomBar() {
    final stock = (pickNum(p, ['stock_quantity']) ?? 0).toInt();
    final out = stock <= 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(
          color: context.palette.card, border: Border(top: BorderSide(color: context.palette.line))),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: out
                    ? null
                    : () {
                        final ok = context.read<CartModel>().add(p);
                        showToast(context, ok ? 'Added to cart' : 'Stock limit reached');
                      },
                child: Opacity(
                  opacity: out ? 0.5 : 1,
                  child: Container(
                    height: 50,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(gradient: AppColors.emeraldGrad, borderRadius: BorderRadius.circular(13)),
                    child: const Text('Add to cart',
                        style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, color: Colors.white)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
