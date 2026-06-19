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
