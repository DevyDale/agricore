import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Lightweight markdown-ish renderer shared by both Dale entry points: handles
/// **bold** and bullet lines so replies read cleanly without a markdown package.
class DaleRichReply extends StatelessWidget {
  final String text;
  final Color color;
  const DaleRichReply({super.key, required this.text, required this.color});

  List<TextSpan> _inline(String line) {
    final spans = <TextSpan>[];
    final re = RegExp(r'\*\*(.+?)\*\*');
    var last = 0;
    for (final m in re.allMatches(line)) {
      if (m.start > last) spans.add(TextSpan(text: line.substring(last, m.start)));
      spans.add(TextSpan(text: m.group(1), style: const TextStyle(fontWeight: FontWeight.w800)));
      last = m.end;
    }
    if (last < line.length) spans.add(TextSpan(text: line.substring(last)));
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(fontFamily: 'Inter', fontSize: 14.5, height: 1.45, color: color);
    final lines = text.split('\n');
    final bulletRe = RegExp(r'^\s*[\-\*•]\s+');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final line in lines)
          if (line.trim().isEmpty)
            const SizedBox(height: 6)
          else if (bulletRe.hasMatch(line))
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2, right: 8),
                    child: Icon(Icons.circle, size: 5, color: color.withValues(alpha: 0.7)),
                  ),
                  Expanded(
                    child: Text.rich(
                        TextSpan(style: base, children: _inline(line.replaceFirst(bulletRe, '')))),
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text.rich(TextSpan(style: base, children: _inline(line))),
            ),
      ],
    );
  }
}

/// Animated three-dot "Dale is typing" indicator.
class DaleTypingDots extends StatefulWidget {
  const DaleTypingDots({super.key});
  @override
  State<DaleTypingDots> createState() => _DaleTypingDotsState();
}

class _DaleTypingDotsState extends State<DaleTypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final t = ((_c.value + i * 0.2) % 1.0);
            final o = 0.3 + 0.7 * (0.5 + 0.5 * (1 - (2 * t - 1).abs()));
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.5),
              child: Opacity(
                opacity: o,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(color: AppColors.g600, shape: BoxShape.circle),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
