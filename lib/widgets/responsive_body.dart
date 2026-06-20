import 'package:flutter/material.dart';
import '../core/responsive/responsive.dart';

class ResponsiveBody extends StatelessWidget {
  final Widget child;

  /// Optional explicit cap — useful for single-column forms (e.g. ~460) that
  /// would otherwise stretch on tablets/desktop. Defaults to the generic
  /// content width.
  final double? maxWidth;
  const ResponsiveBody({super.key, required this.child, this.maxWidth});

  @override
  Widget build(BuildContext context) {
    final maxW = maxWidth ?? Responsive.contentMaxWidth(context);
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: child,
      ),
    );
  }
}
