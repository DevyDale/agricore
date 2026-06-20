import 'package:flutter/widgets.dart';

enum DeviceType { compact, phone, tablet, desktop }

/// Breakpoint helpers so layouts adapt across flip phones, regular phones,
/// tablets/iPads and the web without overflowing.
class Responsive {
  /// Very narrow phones / flip phones in cover mode.
  static const double compactBreakpoint = 360;
  static const double tabletBreakpoint = 600;
  static const double desktopBreakpoint = 1024;

  static DeviceType deviceType(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= desktopBreakpoint) return DeviceType.desktop;
    if (w >= tabletBreakpoint) return DeviceType.tablet;
    if (w < compactBreakpoint) return DeviceType.compact;
    return DeviceType.phone;
  }

  static bool isCompact(BuildContext c) =>
      MediaQuery.sizeOf(c).width < compactBreakpoint;
  static bool isPhone(BuildContext c) {
    final t = deviceType(c);
    return t == DeviceType.phone || t == DeviceType.compact;
  }

  static bool isWide(BuildContext c) =>
      MediaQuery.sizeOf(c).width >= tabletBreakpoint;

  /// Responsive grid column count. Flip phones drop to a single column.
  static int gridColumns(BuildContext context,
      {int compact = 1, int phone = 2, int tablet = 3, int desktop = 4}) {
    switch (deviceType(context)) {
      case DeviceType.desktop:
        return desktop;
      case DeviceType.tablet:
        return tablet;
      case DeviceType.phone:
        return phone;
      case DeviceType.compact:
        return compact;
    }
  }

  /// Column count derived from a minimum item width — never overflows because
  /// it always fits at least one column and grows only when there's room.
  static int columnsForWidth(BuildContext context, double minItemWidth,
      {double spacing = 12, double? maxWidth}) {
    final w = (maxWidth ?? contentMaxWidth(context)).clamp(0.0, double.infinity);
    if (w <= 0) return 1;
    final n = ((w + spacing) / (minItemWidth + spacing)).floor();
    return n < 1 ? 1 : n;
  }

  /// Horizontal screen padding that grows a little on larger screens.
  static double bodyPadding(BuildContext context) {
    switch (deviceType(context)) {
      case DeviceType.desktop:
        return 24;
      case DeviceType.tablet:
        return 20;
      default:
        return 16;
    }
  }

  /// Caps content width so it doesn't stretch awkwardly on large screens.
  static double contentMaxWidth(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= desktopBreakpoint) return 1100;
    if (w >= tabletBreakpoint) return 820;
    return w;
  }
}

/// Centres a screen's content and caps its width on tablets/iPads/web so phone
/// layouts don't stretch edge-to-edge. On phones it's a transparent pass-through.
class MaxWidthBody extends StatelessWidget {
  final Widget child;
  final double? maxWidth;
  const MaxWidthBody({super.key, required this.child, this.maxWidth});

  @override
  Widget build(BuildContext context) {
    final cap = maxWidth ?? Responsive.contentMaxWidth(context);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: cap),
        child: child,
      ),
    );
  }
}
