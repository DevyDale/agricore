import 'package:flutter/material.dart';

class ChipStyle {
  final Color bg;
  final Color fg;
  const ChipStyle(this.bg, this.fg);
}

const Map<String, ChipStyle> kChips = {
  'green': ChipStyle(Color(0xFFE7F4EC), Color(0xFF0F7A4B)),
  'gold': ChipStyle(Color(0xFFF7EED6), Color(0xFFA9791D)),
  'clay': ChipStyle(Color(0xFFF6E6DF), Color(0xFFB15A36)),
  'sage': ChipStyle(Color(0xFFEEF2E2), Color(0xFF5C7A2E)),
  'amber': ChipStyle(Color(0xFFFDECD2), Color(0xFFB45309)),
  'teal': ChipStyle(Color(0xFFD9F2EE), Color(0xFF0F766E)),
  'plum': ChipStyle(Color(0xFFEFE7F4), Color(0xFF7C4FA0)),
  'sky': ChipStyle(Color(0xFFE4EEF6), Color(0xFF2F6F9E)),
  'rose': ChipStyle(Color(0xFFFBE7EE), Color(0xFFB13A63)),
};

class ChipIcon extends StatelessWidget {
  final IconData icon;
  final String tone;
  final double size;
  const ChipIcon(this.icon, {super.key, this.tone = 'green', this.size = 50});
  @override
  Widget build(BuildContext context) {
    final c = kChips[tone] ?? kChips['green']!;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(size * 0.28)),
      child: Icon(icon, color: c.fg, size: size * 0.5),
    );
  }
}
