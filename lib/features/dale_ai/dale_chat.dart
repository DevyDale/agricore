import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_service.dart';
import '../../core/network/dio_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/json_utils.dart';

/// Floating assistant bubble. Tap to open the Dale chat panel.
class DaleOrb extends StatefulWidget {
  const DaleOrb({super.key});
  @override
  State<DaleOrb> createState() => _DaleOrbState();
}

class _DaleOrbState extends State<DaleOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showDaleChat(context),
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, child) {
          final glow = 0.30 + 0.20 * (0.5 + 0.5 * (1 - (2 * _c.value - 1).abs()));
          return Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                  colors: [AppColors.green, Color(0xFF0D9488)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              boxShadow: [
                BoxShadow(
                    color: AppColors.g700.withValues(alpha: 0.5),
                    blurRadius: 22,
                    offset: const Offset(0, 10)),
                BoxShadow(
                    color: AppColors.green.withValues(alpha: glow), blurRadius: 28, spreadRadius: 2),
              ],
            ),
            child: child,
          );
        },
        child: Center(
          child: SizedBox(
            width: 44,
            height: 44,
            child: Lottie.asset('assets/lottie/robot.json', fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}

Future<void> showDaleChat(BuildContext context) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dale',
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (_, __, ___) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim, _, __) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return Align(
        alignment: Alignment.bottomCenter,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(curved),
          child: const _DalePanel(),
        ),
      );
    },
  );
}

class _Msg {
  final String text;
  final bool fromUser;
  _Msg(this.text, this.fromUser);
}

class _DalePanel extends StatefulWidget {
  const _DalePanel();
  @override
  State<_DalePanel> createState() => _DalePanelState();
}

class _DalePanelState extends State<_DalePanel> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;
  final List<_Msg> _msgs = [
    _Msg("Hi, I'm Dale — your Agricore assistant. Ask me about pricing, your farms, or the marketplace.", false),
  ];

  static const _suggestions = [
    'Summarize what I should focus on today.',
    'Recommend products to promote.',
    'Suggest a fair price for my produce.',
    'Draft a friendly message to a buyer.',
  ];

  ApiService get _api => ApiService(context.read<DioClient>().dio);

  Future<void> _send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _msgs.add(_Msg(text, true));
      _sending = true;
      _input.clear();
    });
    _down();
    try {
      final reply = await _api.askDale(text);
      setState(() => _msgs.add(_Msg(reply.isEmpty ? 'No response received.' : reply, false)));
    } catch (e) {
      setState(() => _msgs.add(_Msg(friendlyError(e), false)));
    } finally {
      if (mounted) setState(() => _sending = false);
      _down();
    }
  }

  void _down() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final maxBubble = size.width * 0.78;
    return Material(
      color: Colors.transparent,
      child: Container(
        height: size.height * 0.9,
        decoration: const BoxDecoration(
          color: AppColors.cream,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                    color: AppColors.line, borderRadius: BorderRadius.circular(99)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 10, 12),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                          shape: BoxShape.circle, gradient: AppColors.emeraldGrad),
                      child: const Icon(Icons.smart_toy_rounded, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Dale AI',
                              style: TextStyle(
                                  fontFamily: 'Fraunces',
                                  fontWeight: FontWeight.w800,
                                  fontSize: 20,
                                  color: AppColors.inkWarm)),
                          Text('Your farming assistant',
                              style: TextStyle(
                                  fontFamily: 'Inter', fontSize: 12.5, color: AppColors.slate500)),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded, color: AppColors.slate600),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  children: [
                    ..._msgs.map((m) => _bubble(m, maxBubble)),
                    if (_sending) _bubble(_Msg('…', false), maxBubble),
                  ],
                ),
              ),
              if (_msgs.length <= 1)
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: _suggestions
                        .map((s) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: GestureDetector(
                                onTap: () => _send(s),
                                child: Container(
                                  alignment: Alignment.center,
                                  padding: const EdgeInsets.symmetric(horizontal: 14),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE7F4EC),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(color: const Color(0xFFCDE9D8)),
                                  ),
                                  child: Text(s,
                                      style: const TextStyle(
                                          fontFamily: 'Inter',
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF0F7A4B))),
                                ),
                              ),
                            ))
                        .toList(),
                  ),
                ),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: AppColors.line)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: _send,
                        decoration: InputDecoration(
                          hintText: 'Ask Dale…',
                          isDense: true,
                          fillColor: AppColors.cream,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(999),
                              borderSide: const BorderSide(color: AppColors.line)),
                          enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(999),
                              borderSide: const BorderSide(color: AppColors.line)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: _sending ? null : () => _send(_input.text),
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: const BoxDecoration(
                            shape: BoxShape.circle, gradient: AppColors.emeraldGrad),
                        child: _sending
                            ? const Padding(
                                padding: EdgeInsets.all(14),
                                child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                            : const Icon(Icons.arrow_upward_rounded, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bubble(_Msg m, double maxWidth) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: m.fromUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                gradient: m.fromUser ? AppColors.emeraldGrad : null,
                color: m.fromUser ? null : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: m.fromUser ? null : Border.all(color: AppColors.line),
              ),
              child: Text(m.text,
                  style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14.5,
                      height: 1.45,
                      color: m.fromUser ? Colors.white : AppColors.inkWarm)),
            ),
          ),
        ],
      ),
    );
  }
}
