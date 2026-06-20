import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import '../../core/i18n/app_translations.dart';
import '../../core/i18n/locale_provider.dart';
import '../../core/network/dio_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/json_utils.dart';
import '../../widgets/app_toast.dart';
import 'dale_ai_screen.dart';
import 'dale_models.dart';
import 'dale_service.dart';
import 'dale_voice.dart';
import 'dale_widgets.dart';

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

enum _Kind { user, bot, system }

class _Msg {
  final String text;
  final _Kind kind;
  _Msg(this.text, this.kind);
  bool get fromUser => kind == _Kind.user;
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

  // Voice
  final DaleVoice _voice = DaleVoice();
  bool _voiceAvailable = false;
  bool _listening = false;
  bool _speakReplies = false;
  bool _spokenInput = false; // the last message came from the mic
  bool _voiceLangHintShown = false;

  final List<_Msg> _msgs = [
    _Msg("Hi, I'm Dale — your Agricore assistant. Ask me about pricing, your farms, the marketplace, or tell me where to take you.",
        _Kind.bot),
  ];

  static const _suggestions = [
    'Summarize what I should focus on today.',
    'Recommend products to promote.',
    'Suggest a fair price for my produce.',
    'Take me to my wallet.',
  ];

  DaleService get _dale => DaleService(context.read<DioClient>().dio);

  @override
  void initState() {
    super.initState();
    _initVoice();
  }

  Future<void> _initVoice() async {
    await _voice.init(
      onStatus: (s) {
        if ((s == 'done' || s == 'notListening') && mounted) {
          setState(() => _listening = false);
        }
      },
      onError: (_) {
        if (mounted) setState(() => _listening = false);
      },
    );
    if (mounted) setState(() => _voiceAvailable = _voice.available);
  }

  List<Map<String, String>> _history() {
    final turns = _msgs.where((m) => m.kind != _Kind.system).toList();
    final recent = turns.length > 6 ? turns.sublist(turns.length - 6) : turns;
    return recent
        .map((m) => {'role': m.fromUser ? 'user' : 'assistant', 'content': m.text})
        .toList();
  }

  Future<void> _send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || _sending) return;
    final loc = context.read<LocaleProvider>();
    final dale = context.read<DaleController>();
    final history = _history();
    setState(() {
      _msgs.add(_Msg(text, _Kind.user));
      _sending = true;
      _input.clear();
    });
    _down();
    try {
      final res = await _dale.ask(
        prompt: text,
        page: dale.currentPage,
        language: loc.language,
        currency: loc.currency,
        history: history,
      );
      if (!mounted) return;
      final reply = res.reply.isEmpty ? 'No response received.' : res.reply;
      setState(() => _msgs.add(_Msg(reply, _Kind.bot)));
      // Speak the reply back in the user's language when they spoke, or when
      // the speaker toggle is on — a hands-free conversation in their language.
      if (_speakReplies || _spokenInput) _voice.speak(reply, loc.language);
      _spokenInput = false;
      await _runAction(res.action, dale);
    } catch (e) {
      if (mounted) setState(() => _msgs.add(_Msg(friendlyError(e), _Kind.bot)));
    } finally {
      if (mounted) setState(() => _sending = false);
      _down();
    }
  }

  Future<void> _runAction(DaleAction? action, DaleController dale) async {
    if (action == null) return;
    if (action.type == 'show_message' && (action.message ?? '').isNotEmpty) {
      setState(() => _msgs.add(_Msg(action.message!, _Kind.bot)));
      return;
    }
    final confirmation = dale.handle(action);
    if (confirmation == null) return;
    setState(() => _msgs.add(_Msg(confirmation, _Kind.system)));
    _down();
    // Let the user read the confirmation, then reveal the section Dale opened.
    await Future.delayed(const Duration(milliseconds: 700));
    if (mounted) Navigator.of(context).maybePop();
  }

  /// One-time gentle hint if the device has no recogniser for the chosen
  /// language — we still listen (falling back to the default) so it degrades
  /// gracefully rather than silently.
  void _maybeWarnVoiceLanguage(String lang) {
    if (lang == 'en' || _voiceLangHintShown || _voice.supportsLanguage(lang)) return;
    _voiceLangHintShown = true;
    final name = kLanguages
        .firstWhere((l) => l.code == lang, orElse: () => kLanguages.first)
        .name;
    showToast(
        context,
        'Voice for $name isn\'t installed on this device — add it in your phone\'s '
        'language/voice settings. Using the default recogniser for now.',
        success: false);
  }

  Future<void> _toggleListen() async {
    if (!_voiceAvailable) return;
    if (_listening) {
      await _voice.stopListening();
      if (mounted) setState(() => _listening = false);
      return;
    }
    final loc = context.read<LocaleProvider>();
    _maybeWarnVoiceLanguage(loc.language);
    setState(() => _listening = true);
    await _voice.listen(
      lang: loc.language,
      onResult: (text, isFinal) {
        if (!mounted) return;
        setState(() => _input.text = text);
        if (isFinal && text.trim().isNotEmpty) {
          setState(() {
            _listening = false;
            _spokenInput = true; // speak Dale's reply back in the same language
          });
          _send(text);
        }
      },
    );
  }

  Future<void> _toggleSpeak() async {
    setState(() => _speakReplies = !_speakReplies);
    if (!_speakReplies) await _voice.stopSpeaking();
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
    _voice.dispose();
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
        decoration: BoxDecoration(
          color: context.palette.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
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
                    color: context.palette.line, borderRadius: BorderRadius.circular(99)),
              ),
              _header(),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  children: [
                    ..._msgs.map((m) => _bubble(m, maxBubble)),
                    if (_sending) _typing(maxBubble),
                  ],
                ),
              ),
              if (_msgs.length <= 1) _suggestionRow(),
              _composer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 8, 12),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.emeraldGrad),
            child: const Icon(Icons.smart_toy_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Dale AI',
                    style: TextStyle(
                        fontFamily: 'Fraunces',
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                        color: context.palette.ink)),
                Text('Your farming assistant',
                    style: TextStyle(fontFamily: 'Inter', fontSize: 12.5, color: context.palette.muted)),
              ],
            ),
          ),
          IconButton(
            tooltip: _speakReplies ? 'Mute voice' : 'Speak replies',
            onPressed: _toggleSpeak,
            icon: Icon(_speakReplies ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                color: _speakReplies ? AppColors.g600 : context.palette.muted),
          ),
          IconButton(
            tooltip: 'Open full screen',
            onPressed: () {
              final nav = Navigator.of(context);
              nav.pop();
              nav.push(MaterialPageRoute(builder: (_) => const DaleAiScreen()));
            },
            icon: Icon(Icons.open_in_full_rounded, color: context.palette.muted2, size: 20),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.close_rounded, color: context.palette.muted2),
          ),
        ],
      ),
    );
  }

  Widget _suggestionRow() {
    return SizedBox(
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
                        color: context.palette.chipBg,
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
    );
  }

  Widget _composer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: context.palette.card,
        border: Border(top: BorderSide(color: context.palette.line)),
      ),
      child: Row(
        children: [
          if (_voiceAvailable) ...[
            GestureDetector(
              onTap: _toggleListen,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _listening ? AppColors.green : const Color(0xFFEFF5F1),
                  border: Border.all(color: _listening ? AppColors.green : context.palette.line),
                ),
                child: Icon(_listening ? Icons.mic_rounded : Icons.mic_none_rounded,
                    color: _listening ? Colors.white : AppColors.g700),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: _send,
              decoration: InputDecoration(
                hintText: _listening ? 'Listening…' : 'Ask Dale…',
                isDense: true,
                filled: true,
                fillColor: context.palette.surface,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: BorderSide(color: context.palette.line)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: BorderSide(color: context.palette.line)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: const BorderSide(color: AppColors.green)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _sending ? null : () => _send(_input.text),
            child: Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.emeraldGrad),
              child: _sending
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                  : const Icon(Icons.arrow_upward_rounded, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble(_Msg m, double maxWidth) {
    if (m.kind == _Kind.system) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
                color: context.palette.chipBg, borderRadius: BorderRadius.circular(999)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.auto_awesome_rounded, size: 13, color: Color(0xFF0F7A4B)),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(m.text,
                      style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF0F7A4B))),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: m.fromUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: GestureDetector(
              onLongPress: () {
                Clipboard.setData(ClipboardData(text: m.text));
                showToast(context, 'Copied');
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  gradient: m.fromUser ? AppColors.emeraldGrad : null,
                  color: m.fromUser ? null : context.palette.card,
                  borderRadius: BorderRadius.circular(16),
                  border: m.fromUser ? null : Border.all(color: context.palette.line),
                ),
                child: DaleRichReply(
                  text: m.text,
                  color: m.fromUser ? Colors.white : context.palette.ink,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _typing(double maxWidth) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: context.palette.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.palette.line),
            ),
            child: const DaleTypingDots(),
          ),
        ],
      ),
    );
  }
}

