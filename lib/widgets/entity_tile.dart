import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import 'chip_styles.dart';

class EntityTile extends StatelessWidget {
  final IconData icon;
  final String tone;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  const EntityTile({
    super.key,
    required this.icon,
    required this.title,
    this.tone = 'green',
    this.subtitle,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.line)),
          child: Row(
            children: [
              ChipIcon(icon, tone: tone, size: 48),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontFamily: 'Fraunces',
                            fontWeight: FontWeight.w700,
                            fontSize: 16.5,
                            color: AppColors.inkWarm)),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 13.5,
                              height: 1.4,
                              color: AppColors.slate600)),
                    ],
                  ],
                ),
              ),
              trailing ?? const Icon(Icons.chevron_right_rounded, color: AppColors.slate500),
            ],
          ),
        ),
      ),
    );
  }
}
