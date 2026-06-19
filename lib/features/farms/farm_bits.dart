import 'package:flutter/material.dart';
import '../../core/utils/json_utils.dart';

const Color cCrops = Color(0xFF4F8438);
const Color cLivestock = Color(0xFFC39A48);
const Color cMixed = Color(0xFF7C8C42);

String farmTypeKey(String? raw) {
  final t = (raw ?? '').toLowerCase();
  if (t.contains('crop')) return 'crops';
  if (t.contains('livestock') || t.contains('animal')) return 'livestock';
  return 'mixed';
}

String farmTypeLabel(String key) {
  switch (key) {
    case 'crops':
      return 'Crops';
    case 'livestock':
      return 'Livestock';
    default:
      return 'Mixed';
  }
}

IconData farmTypeIcon(String key) {
  switch (key) {
    case 'crops':
      return Icons.grass_rounded;
    case 'livestock':
      return Icons.pets_rounded;
    default:
      return Icons.agriculture_rounded;
  }
}

Color farmTypeColor(String key) {
  switch (key) {
    case 'crops':
      return cCrops;
    case 'livestock':
      return cLivestock;
    default:
      return cMixed;
  }
}

LinearGradient _bannerGrad(String key) {
  switch (key) {
    case 'crops':
      return const LinearGradient(colors: [Color(0xFF549040), Color(0xFF3C7330)], begin: Alignment.topLeft, end: Alignment.bottomRight);
    case 'livestock':
      return const LinearGradient(colors: [Color(0xFFC9A24E), Color(0xFF9C7430)], begin: Alignment.topLeft, end: Alignment.bottomRight);
    default:
      return const LinearGradient(colors: [Color(0xFF7E9046), Color(0xFF5F722D)], begin: Alignment.topLeft, end: Alignment.bottomRight);
  }
}

LinearGradient farmEmblemGrad(String key) {
  switch (key) {
    case 'crops':
      return const LinearGradient(colors: [Color(0xFF4F8438), Color(0xFF3C7330)], begin: Alignment.topLeft, end: Alignment.bottomRight);
    case 'livestock':
      return const LinearGradient(colors: [Color(0xFFC39A48), Color(0xFFA9772E)], begin: Alignment.topLeft, end: Alignment.bottomRight);
    default:
      return const LinearGradient(colors: [Color(0xFF7C8C42), Color(0xFF5C6B1F)], begin: Alignment.topLeft, end: Alignment.bottomRight);
  }
}

LinearGradient farmShareGrad(String key) {
  switch (key) {
    case 'livestock':
      return const LinearGradient(colors: [Color(0xFFD3AB57), Color(0xFFA9772E)]);
    case 'mixed':
      return const LinearGradient(colors: [Color(0xFF94A05A), Color(0xFF5C6B1F)]);
    default:
      return const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF047857)]);
  }
}

const Map<String, double> _unitToHa = {'acres': 0.404686, 'hectares': 1.0, 'square_meters': 0.0001};

double farmToHa(Map f) {
  final n = pickNum(f, ['total_size', 'size']);
  if (n == null || n <= 0) return 0;
  final u = (pickString(f, ['size_unit', 'unit']) ?? 'acres').toLowerCase();
  return n.toDouble() * (_unitToHa[u] ?? 1.0);
}

String farmAreaText(Map f) {
  final ha = farmToHa(f);
  if (ha > 0) return '${ha.toStringAsFixed(ha < 100 ? 1 : 0)} ha';
  final raw = pickNum(f, ['total_size', 'size']);
  if (raw != null) return '${raw % 1 == 0 ? raw.toInt() : raw} ${pickString(f, ['size_unit', 'unit']) ?? ''}'.trim();
  return '—';
}

// ---- textured banner ----
class FarmBanner extends StatelessWidget {
  final String typeKey;
  final double height;
  const FarmBanner({super.key, required this.typeKey, this.height = 88});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(decoration: BoxDecoration(gradient: _bannerGrad(typeKey))),
          CustomPaint(painter: _BannerTexture(typeKey)),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x24FFFFFF), Color(0x4D000000)]),
            ),
          ),
          Positioned(
            top: 10,
            left: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(color: const Color(0x5C000000), borderRadius: BorderRadius.circular(999)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(farmTypeIcon(typeKey), size: 11, color: Colors.white),
                  const SizedBox(width: 5),
                  Text(farmTypeLabel(typeKey).toUpperCase(),
                      style: const TextStyle(
                          fontFamily: 'Inter', fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: Colors.white)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BannerTexture extends CustomPainter {
  final String typeKey;
  _BannerTexture(this.typeKey);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..strokeWidth = 2;
    if (typeKey == 'livestock') {
      p
        ..style = PaintingStyle.fill
        ..color = Colors.white.withValues(alpha: 0.20);
      for (double y = 6; y < size.height; y += 14) {
        for (double x = 6; x < size.width; x += 14) {
          canvas.drawCircle(Offset(x, y), 1.5, p);
        }
      }
    } else if (typeKey == 'crops') {
      p
        ..style = PaintingStyle.stroke
        ..color = Colors.black.withValues(alpha: 0.10);
      for (double x = -size.height; x < size.width; x += 9) {
        canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), p);
      }
    } else {
      p
        ..style = PaintingStyle.stroke
        ..color = Colors.black.withValues(alpha: 0.10);
      for (double x = -size.height; x < size.width; x += 12) {
        canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), p);
      }
      p.color = Colors.white.withValues(alpha: 0.07);
      for (double x = 0; x < size.width + size.height; x += 12) {
        canvas.drawLine(Offset(x, 0), Offset(x - size.height, size.height), p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BannerTexture old) => old.typeKey != typeKey;
}

class FarmEmblem extends StatelessWidget {
  final String typeKey;
  final double size;
  const FarmEmblem({super.key, required this.typeKey, this.size = 46});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: farmEmblemGrad(typeKey),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 14, offset: Offset(0, 8))],
      ),
      child: Icon(farmTypeIcon(typeKey), color: Colors.white, size: size * 0.42),
    );
  }
}

class ShareBar extends StatelessWidget {
  final double pct; // 0..1
  final String typeKey;
  const ShareBar({super.key, required this.pct, required this.typeKey});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 7,
        color: const Color(0xFFEEE7D8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: pct.clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => FractionallySizedBox(
              widthFactor: v <= 0 ? 0.02 : v,
              child: Container(decoration: BoxDecoration(gradient: farmShareGrad(typeKey))),
            ),
          ),
        ),
      ),
    );
  }
}
