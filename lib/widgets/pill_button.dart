import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

class PillButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool ghost;
  final bool loading;
  final IconData? trailingIcon;
  final bool fullWidth;
  const PillButton({
    super.key,
    required this.label,
    this.onPressed,
    this.ghost = false,
    this.loading = false,
    this.trailingIcon,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = !loading && onPressed != null;
    final fg = ghost ? AppColors.g700 : Colors.white;
    final content = loading
        ? SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: fg))
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: TextStyle(
                      fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 16, color: fg)),
              if (trailingIcon != null) ...[
                const SizedBox(width: 8),
                Icon(trailingIcon, size: 18, color: fg),
              ],
            ],
          );
    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: GestureDetector(
        onTap: enabled ? onPressed : null,
        child: Container(
          height: 56,
          width: fullWidth ? double.infinity : null,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 26),
          decoration: BoxDecoration(
            gradient: ghost ? null : AppColors.emeraldGrad,
            color: ghost ? context.palette.card : null,
            borderRadius: BorderRadius.circular(999),
            boxShadow: ghost
                ? [BoxShadow(color: Colors.black.withValues(alpha: 0.16), blurRadius: 20, offset: const Offset(0, 8))]
                : [BoxShadow(color: AppColors.g700.withValues(alpha: 0.45), blurRadius: 30, offset: const Offset(0, 16))],
          ),
          child: content,
        ),
      ),
    );
  }
}
