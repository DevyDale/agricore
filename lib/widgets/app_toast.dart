import 'dart:async';
import 'package:flutter/material.dart';

enum ToastType { success, error, info }

OverlayEntry? _active;

/// Shows a lively, animated toast. Keeps the legacy `success` flag (false ->
/// error styling, as before); pass an explicit [type] for info/neutral toasts.
void showToast(BuildContext context, String message, {bool success = false, ToastType? type}) {
  final t = type ?? (success ? ToastType.success : ToastType.error);
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _active?.remove();
  _active = null;
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _ToastView(
      message: message,
      type: t,
      onGone: () {
        if (identical(_active, entry)) _active = null;
        entry.remove();
      },
    ),
  );
  _active = entry;
  overlay.insert(entry);
}

class _ToastStyle {
  final Color bg;
  final IconData icon;
  const _ToastStyle(this.bg, this.icon);
}

_ToastStyle _styleFor(ToastType t) {
  switch (t) {
    case ToastType.success:
      return const _ToastStyle(Color(0xFF0F7A4B), Icons.check_circle_rounded);
    case ToastType.error:
      return const _ToastStyle(Color(0xFFDC2626), Icons.error_rounded);
    case ToastType.info:
      return const _ToastStyle(Color(0xFF1F2937), Icons.info_rounded);
  }
}

class _ToastView extends StatefulWidget {
  final String message;
  final ToastType type;
  final VoidCallback onGone;
  const _ToastView({required this.message, required this.type, required this.onGone});
  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 280));
  Timer? _hold;

  @override
  void initState() {
    super.initState();
    _c.forward();
    _hold = Timer(const Duration(milliseconds: 2600), _dismiss);
  }

  Future<void> _dismiss() async {
    _hold?.cancel();
    if (!mounted) {
      widget.onGone();
      return;
    }
    await _c.reverse();
    widget.onGone();
  }

  @override
  void dispose() {
    _hold?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _styleFor(widget.type);
    return Positioned(
      left: 16,
      right: 16,
      bottom: 28 + MediaQuery.of(context).viewInsets.bottom,
      child: SafeArea(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, child) {
            final v = _c.value;
            final slide = (1 - Curves.easeOutCubic.transform(v)) * 26;
            return Opacity(
              opacity: v.clamp(0.0, 1.0),
              child: Transform.translate(offset: Offset(0, slide), child: child),
            );
          },
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: _dismiss,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: s.bg,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 18,
                        offset: const Offset(0, 8)),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(s.icon, color: Colors.white, size: 20),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        widget.message,
                        style: const TextStyle(
                            fontFamily: 'Inter',
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
