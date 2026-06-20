import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

/// Shared building blocks for the newer mobile-native screens (Wallet,
/// Finances, Transporter, Professional profile). They reuse the app's colour
/// and type tokens so the look stays cohesive, but adopt a bolder, phone-first
/// layout language (gradient hero, pill segments, soft metric cards) that is
/// deliberately distinct from the Django web layouts.

/// Formats a money amount with thousands separators and an optional code.
String money(num? value, {String? code, int decimals = 0}) {
  final v = value ?? 0;
  final neg = v < 0;
  final fixed = v.abs().toStringAsFixed(decimals);
  final parts = fixed.split('.');
  final intPart = parts[0];
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
    buf.write(intPart[i]);
  }
  final body = parts.length > 1 ? '$buf.${parts[1]}' : buf.toString();
  final prefix = code == null || code.isEmpty ? '' : '$code ';
  return '$prefix${neg ? '-' : ''}$body';
}

/// A rounded gradient header used at the top of the new screens. Pass a sliver
/// host via [GradientHero.sliver] for CustomScrollView, or use it inline.
class GradientHero extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? bigValue;
  final String? bigLabel;
  final IconData icon;
  final Widget? trailing;
  final List<Widget> chips;
  final VoidCallback? onBack;

  const GradientHero({
    super.key,
    required this.title,
    this.subtitle,
    this.bigValue,
    this.bigLabel,
    this.icon = Icons.dashboard_rounded,
    this.trailing,
    this.chips = const [],
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20, top + 16, 20, 22),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.g700, AppColors.green],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (onBack != null) ...[
                _RoundIconButton(icon: Icons.arrow_back_rounded, onTap: onBack!),
                const SizedBox(width: 10),
              ],
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontFamily: 'Fraunces',
                            fontWeight: FontWeight.w800,
                            fontSize: 20,
                            color: Colors.white)),
                    if (subtitle != null)
                      Text(subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12.5,
                              color: Colors.white.withValues(alpha: 0.85))),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          if (bigValue != null) ...[
            const SizedBox(height: 20),
            if (bigLabel != null)
              Text(bigLabel!.toUpperCase(),
                  style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 11,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.8))),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(bigValue!,
                  style: const TextStyle(
                      fontFamily: 'Fraunces',
                      fontWeight: FontWeight.w800,
                      fontSize: 34,
                      color: Colors.white)),
            ),
          ],
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(children: chips),
          ],
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _RoundIconButton({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

/// A frosted chip shown inside a [GradientHero] (e.g. a count or status).
class HeroChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const HeroChip({super.key, required this.icon, required this.label});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: Colors.white),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white)),
      ]),
    );
  }
}

/// Soft white metric card with a coloured icon chip.
class MetricCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  const MetricCard(
      {super.key,
      required this.icon,
      required this.value,
      required this.label,
      required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.palette.line),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                maxLines: 1,
                style: TextStyle(
                    fontFamily: 'Fraunces',
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: context.palette.ink)),
          ),
          const SizedBox(height: 2),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontFamily: 'Inter', fontSize: 11, color: context.palette.muted)),
        ],
      ),
    );
  }
}

/// Pill segmented control.
class SegTabs extends StatelessWidget {
  final List<String> tabs;
  final int index;
  final ValueChanged<int> onTap;
  const SegTabs({super.key, required this.tabs, required this.index, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
          color: context.palette.card,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: context.palette.line)),
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onTap(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    gradient: i == index ? AppColors.emeraldGrad : null,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(tabs[i],
                      style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                          color: i == index ? Colors.white : context.palette.muted2)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Bottom-sheet scaffold with grab handle, title, optional error banner and a
/// gradient submit button.
class FreshSheet extends StatelessWidget {
  final String title;
  final String? error;
  final VoidCallback onSubmit;
  final String submitLabel;
  final bool submitting;
  final List<Widget> children;
  const FreshSheet({
    super.key,
    required this.title,
    required this.error,
    required this.onSubmit,
    required this.submitLabel,
    required this.children,
    this.submitting = false,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: BoxDecoration(
            color: context.palette.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                  child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                          color: context.palette.line,
                          borderRadius: BorderRadius.circular(99)))),
              const SizedBox(height: 14),
              Text(title,
                  style: TextStyle(
                      fontFamily: 'Fraunces',
                      fontWeight: FontWeight.w800,
                      fontSize: 19,
                      color: context.palette.ink)),
              const SizedBox(height: 14),
              if (error != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFCA5A5))),
                  child: Text(error!,
                      style: const TextStyle(
                          fontFamily: 'Inter', fontSize: 12.5, color: Color(0xFFDC2626))),
                ),
                const SizedBox(height: 12),
              ],
              ...children,
              const SizedBox(height: 16),
              GestureDetector(
                onTap: submitting ? null : onSubmit,
                child: Container(
                  height: 50,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      gradient: AppColors.emeraldGrad,
                      borderRadius: BorderRadius.circular(13)),
                  child: submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.4, color: Colors.white))
                      : Text(submitLabel,
                          style: const TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Labelled text field used inside [FreshSheet].
class FreshField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final String? label;
  final bool number;
  final int lines;
  const FreshField({
    super.key,
    required this.controller,
    required this.hint,
    this.label,
    this.number = false,
    this.lines = 1,
  });

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: controller,
      maxLines: lines,
      keyboardType:
          number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: context.palette.card,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(11),
            borderSide: BorderSide(color: context.palette.line)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(11),
            borderSide: BorderSide(color: context.palette.line)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(11),
            borderSide: const BorderSide(color: AppColors.green)),
      ),
    );
    if (label == null) return field;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 6),
          child: Text(label!,
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  color: context.palette.muted3)),
        ),
        field,
      ],
    );
  }
}

/// Section title with an optional trailing action.
class FreshSectionHeader extends StatelessWidget {
  final String title;
  final Widget? action;
  const FreshSectionHeader({super.key, required this.title, this.action});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title,
              style: TextStyle(
                  fontFamily: 'Fraunces',
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                  color: context.palette.ink)),
        ),
        if (action != null) action!,
      ],
    );
  }
}

/// Small gradient "add" / action button used next to section headers.
class FreshPillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const FreshPillButton({super.key, required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
            gradient: AppColors.emeraldGrad, borderRadius: BorderRadius.circular(12)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  color: Colors.white)),
        ]),
      ),
    );
  }
}
