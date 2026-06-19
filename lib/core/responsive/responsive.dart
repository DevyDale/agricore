import 'package:flutter/widgets.dart';

enum DeviceType { phone, tablet, desktop }

/// Breakpoint helpers so layouts adapt across phone and tablet sizes.
class Responsive {
  static const double tabletBreakpoint = 600;
  static const double desktopBreakpoint = 1024;

  static DeviceType deviceType(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= desktopBreakpoint) return DeviceType.desktop;
    if (w >= tabletBreakpoint) return DeviceType.tablet;
    return DeviceType.phone;
  }

  static bool isPhone(BuildContext c) => deviceType(c) == DeviceType.phone;
  static bool isWide(BuildContext c) =>
      MediaQuery.sizeOf(c).width >= tabletBreakpoint;

  /// Responsive grid column count.
  static int gridColumns(BuildContext context,
      {int phone = 2, int tablet = 3, int desktop = 4}) {
    switch (deviceType(context)) {
      case DeviceType.desktop:
        return desktop;
      case DeviceType.tablet:
        return tablet;
      case DeviceType.phone:
        return phone;
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
