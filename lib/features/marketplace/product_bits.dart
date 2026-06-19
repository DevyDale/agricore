import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../core/utils/json_utils.dart';

String _grp(num n) {
  final s = n.round().toString();
  final buf = StringBuffer();
  final len = s.length;
  for (int i = 0; i < len; i++) {
    if (i > 0 && (len - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

String money(num? n) => 'UGX ${_grp(n ?? 0)}';

int prodHue(String s) {
  int h = 0;
  for (final cu in s.codeUnits) {
    h = (h * 31 + cu) & 0x7fffffff;
  }
  return h % 360;
}

IconData catIcon(String c) {
  c = c.toLowerCase();
  if (RegExp(r'beef|cattle|cow|goat|sheep|pork|pig|lamb|meat|livestock|poultry|chicken|egg|animal').hasMatch(c)) {
    return Icons.pets;
  }
  if (RegExp(r'milk|dairy|yogurt|cheese|butter').hasMatch(c)) return Icons.local_drink;
  if (RegExp(r'tractor|machin|equip|tool|harvester|plough|plow').hasMatch(c)) return Icons.agriculture;
  if (RegExp(r'chemical|fertil|pesticide|herbicide|spray|input').hasMatch(c)) return Icons.science;
  if (RegExp(r'fruit|vegetable|tomato|mango|banana|apple|orange').hasMatch(c)) return Icons.local_florist;
  if (RegExp(r'maize|corn|grain|wheat|rice|cereal|sorghum|barley|millet|bean|sesame|seed|crop|produce').hasMatch(c)) {
    return Icons.grass;
  }
  return Icons.eco;
}

Color _hsl(double h, double s, double l) => HSLColor.fromAHSL(1, h, s, l).toColor();

class GenThumb extends StatelessWidget {
  final String title;
  final String category;
  final bool big;
  const GenThumb({super.key, required this.title, this.category = '', this.big = false});

  @override
  Widget build(BuildContext context) {
    final h = prodHue(title).toDouble();
    final h2 = (h + 38) % 360;
    final icon = catIcon('$title $category');
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: [_hsl(h, 0.48, 0.44), _hsl(h2, 0.52, 0.30)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white.withValues(alpha: 0.97), size: big ? 64 : 42),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(title,
                  textAlign: TextAlign.center,
                  maxLines: big ? 3 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontFamily: 'Fraunces',
                      fontWeight: FontWeight.w700,
                      fontSize: big ? 22 : 14.5,
                      height: 1.15,
                      color: Colors.white,
                      shadows: const [Shadow(color: Color(0x47000000), blurRadius: 5, offset: Offset(0, 1))])),
            ),
          ],
        ),
      ),
    );
  }
}

class ProductImage extends StatelessWidget {
  final Map<String, dynamic> product;
  final bool big;
  const ProductImage(this.product, {super.key, this.big = false});

  @override
  Widget build(BuildContext context) {
    final title = (product['title'] ?? 'Product').toString();
    final cat = (product['category'] ?? '').toString();
    final raw = (product['image_display'] ?? product['image'] ?? product['image_url'])?.toString();
    final url = (raw == null || raw.isEmpty) ? null : absoluteUrl(raw);
    return Stack(
      fit: StackFit.expand,
      children: [
        GenThumb(title: title, category: cat, big: big),
        if (url != null)
          CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            fadeInDuration: const Duration(milliseconds: 250),
            placeholder: (_, __) => const SizedBox.shrink(),
            errorWidget: (_, __, ___) => const SizedBox.shrink(),
          ),
      ],
    );
  }
}

Widget starsRow(num? rating, {double size = 14}) {
  final r = (rating ?? 0).round();
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: List.generate(
      5,
      (i) => Icon(i < r ? Icons.star_rounded : Icons.star_border_rounded,
          size: size, color: const Color(0xFFFBBF24)),
    ),
  );
}

class StockInfo {
  final String label;
  final Color bg;
  final Color fg;
  const StockInfo(this.label, this.bg, this.fg);
}

StockInfo stockInfo(int stock) {
  if (stock <= 0) return const StockInfo('Out of stock', Color(0xFFFEE2E2), Color(0xFFDC2626));
  if (stock <= 5) return StockInfo('Low · $stock left', const Color(0xFFFEF3C7), const Color(0xFF92400E));
  return const StockInfo('In stock', Color(0xFFDCFCE7), Color(0xFF047857));
}
