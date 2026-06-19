import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

class BrandMark extends StatelessWidget {
  final double markSize;
  final double nameSize;
  final Color nameColor;
  final bool frosted;
  final bool showName;
  const BrandMark({
    super.key,
    this.markSize = 42,
    this.nameSize = 22,
    this.nameColor = Colors.white,
    this.frosted = true,
    this.showName = true,
  });

  @override
  Widget build(BuildContext context) {
    final mark = Container(
      width: markSize,
      height: markSize,
      decoration: BoxDecoration(
        color: frosted
            ? Colors.white.withValues(alpha: 0.16)
            : AppColors.green.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(markSize * 0.31),
        border: Border.all(
            color: frosted
                ? Colors.white.withValues(alpha: 0.30)
                : AppColors.green.withValues(alpha: 0.30)),
      ),
      child: Icon(Icons.eco_rounded,
          size: markSize * 0.55, color: frosted ? Colors.white : AppColors.g700),
    );
    if (!showName) return mark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        SizedBox(width: markSize * 0.28),
        Text('Agricore',
            style: TextStyle(
                fontFamily: 'Fraunces',
                fontWeight: FontWeight.w700,
                fontSize: nameSize,
                letterSpacing: -0.5,
                color: nameColor)),
      ],
    );
  }
}
