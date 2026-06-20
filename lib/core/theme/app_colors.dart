import 'package:flutter/material.dart';

class AppColors {
  // ---- web theme tokens (onboarding.html) ----
  static const Color green = Color(0xFF10B981);   // g500
  static const Color g600 = Color(0xFF059669);
  static const Color g700 = Color(0xFF047857);
  static const Color g900 = Color(0xFF064E3B);
  static const Color heroBase = Color(0xFF22432C);
  static const Color footerBg = Color(0xFF0E2018);
  static const Color cream = Color(0xFFFAF6EE);
  static const Color line = Color(0xFFECE4D6);
  static const Color inkWarm = Color(0xFF16271C);
  static const Color gold = Color(0xFFFFE6A8);
  static const Color slate700 = Color(0xFF334155);
  static const Color slate600 = Color(0xFF475569);
  static const Color slate500 = Color(0xFF64748B);

  static const LinearGradient emeraldGrad = LinearGradient(
    colors: [green, g700], begin: Alignment.topLeft, end: Alignment.bottomRight);

  // ---- legacy aliases (kept for dashboard / older widgets) ----
  static const Color emerald = Color(0xFF34D399);
  static const Color emeraldDark = Color(0xFF059669);
  static const Color teal = Color(0xFF0D9488);
  static const Color cyan = Color(0xFF06D6A0);
  static const Color forest = Color(0xFF166534);
  static const Color ink = Color(0xFF0A1A0F);
  static const Color muted = Color(0xFF6B7280);
  static const Color bgTop = Color(0xFFE6F4EA);
  static const Color bgBottom = Color(0xFFC7E8D5);
  static const Color border = Color(0xFFD1FAE5);
  static const Color primary = green;
  static const Color primaryDark = g700;
  static const Color accent = green;
  static const Color surface = Colors.white;
  static const Color bgLight = bgTop;
  static const Color textDark = ink;
  static const Color textMuted = muted;
  static const LinearGradient gradient = emeraldGrad;
  static const LinearGradient bgGradient = LinearGradient(
    colors: [bgTop, bgBottom], begin: Alignment.topLeft, end: Alignment.bottomRight);
}

/// Semantic, brightness-aware surface/text tokens used for dark-mode support.
/// The light values are exactly the legacy AppColors, so converting a screen to
/// the palette never changes its light appearance — only dark mode differs.
/// Brand colours (green family, gold, gradients) stay constant in both modes.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  final Color surface; // scaffold / page background  (was AppColors.cream)
  final Color card; // elevated container fill          (was Colors.white)
  final Color ink; // primary text                       (was AppColors.inkWarm)
  final Color line; // borders / dividers                (was AppColors.line)
  final Color muted; // secondary text                   (was AppColors.slate500)
  final Color muted2; //                                  (was AppColors.slate600)
  final Color muted3; //                                  (was AppColors.slate700)
  final Color chipBg; // soft brand chip background       (was 0xFFE7F4EC)

  const AppPalette({
    required this.surface,
    required this.card,
    required this.ink,
    required this.line,
    required this.muted,
    required this.muted2,
    required this.muted3,
    required this.chipBg,
  });

  static const light = AppPalette(
    surface: AppColors.cream,
    card: Colors.white,
    ink: AppColors.inkWarm,
    line: AppColors.line,
    muted: AppColors.slate500,
    muted2: AppColors.slate600,
    muted3: AppColors.slate700,
    chipBg: Color(0xFFE7F4EC),
  );

  static const dark = AppPalette(
    surface: Color(0xFF0E1410),
    card: Color(0xFF18201A),
    ink: Color(0xFFEDF1EC),
    line: Color(0xFF2A352D),
    muted: Color(0xFF8C97A1),
    muted2: Color(0xFFA9B2BB),
    muted3: Color(0xFFC4CCD4),
    chipBg: Color(0xFF1E3A2B),
  );

  @override
  AppPalette copyWith({
    Color? surface,
    Color? card,
    Color? ink,
    Color? line,
    Color? muted,
    Color? muted2,
    Color? muted3,
    Color? chipBg,
  }) =>
      AppPalette(
        surface: surface ?? this.surface,
        card: card ?? this.card,
        ink: ink ?? this.ink,
        line: line ?? this.line,
        muted: muted ?? this.muted,
        muted2: muted2 ?? this.muted2,
        muted3: muted3 ?? this.muted3,
        chipBg: chipBg ?? this.chipBg,
      );

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      surface: Color.lerp(surface, other.surface, t)!,
      card: Color.lerp(card, other.card, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      line: Color.lerp(line, other.line, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      muted2: Color.lerp(muted2, other.muted2, t)!,
      muted3: Color.lerp(muted3, other.muted3, t)!,
      chipBg: Color.lerp(chipBg, other.chipBg, t)!,
    );
  }
}

/// `context.palette.surface` etc. — resolves to light/dark automatically.
extension AppPaletteX on BuildContext {
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.light;
}
