import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

class AnimatedNavItem {
  final IconData icon;
  final String label;
  const AnimatedNavItem(this.icon, this.label);
}

/// A bottom navigation bar with an animated "pill" that expands under the
/// selected tab (icon scales in, label slides open). Pure-Flutter, no deps.
class AnimatedBottomNav extends StatelessWidget {
  final List<AnimatedNavItem> items;
  final int index;
  final ValueChanged<int> onTap;
  const AnimatedBottomNav({super.key, required this.items, required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.palette.card,
        border: Border(top: BorderSide(color: context.palette.line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: List.generate(items.length, (i) {
              final on = i == index;
              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onTap(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    height: 48,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: on ? context.palette.chipBg : Colors.transparent,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedScale(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutBack,
                          scale: on ? 1.12 : 1.0,
                          child: Icon(items[i].icon,
                              size: 22, color: on ? AppColors.g700 : context.palette.muted),
                        ),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOut,
                          child: on
                              ? Padding(
                                  padding: const EdgeInsets.only(left: 7),
                                  child: Text(items[i].label,
                                      style: const TextStyle(
                                          fontFamily: 'Inter',
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12.5,
                                          color: AppColors.g700)),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
