import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

class SectionHeader extends StatelessWidget {
  final String? eyebrow;
  final String title;
  final TextAlign align;
  const SectionHeader({super.key, this.eyebrow, required this.title, this.align = TextAlign.left});

  @override
  Widget build(BuildContext context) {
    final cross =
        align == TextAlign.center ? CrossAxisAlignment.center : CrossAxisAlignment.start;
    return Column(
      crossAxisAlignment: cross,
      children: [
        if (eyebrow != null) ...[
          Text(eyebrow!.toUpperCase(),
              style: const TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                  fontSize: 11.5,
                  letterSpacing: 1.5,
                  color: AppColors.g600)),
          const SizedBox(height: 6),
        ],
        Text(title,
            textAlign: align,
            style: TextStyle(
                fontFamily: 'Fraunces',
                fontWeight: FontWeight.w800,
                fontSize: 22,
                height: 1.12,
                color: context.palette.ink)),
      ],
    );
  }
}
