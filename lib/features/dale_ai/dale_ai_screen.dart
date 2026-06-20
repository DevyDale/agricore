import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/i18n/locale_provider.dart';
import '../../core/network/dio_client.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/json_utils.dart';
import '../../widgets/app_toast.dart';
import 'dale_models.dart';
import 'dale_service.dart';
import 'dale_voice.dart';
import 'dale_widgets.dart';

enum _Kind { user, bot, system }

class _Msg {
  final String text;
  final _Kind kind;
  _Msg(this.text, this.kind);
  bool get fromUser => kind == _Kind.user;
}

/// Full-screen Dale assistant. Shares the same brain as the floating Dale panel
/// (rich page/language/currency context, conversation history, UI actions and
/// voice I/O).
class DaleAiScreen extends StatefulWidget {
  const DaleAiScreen({super.key});
  @override
  State<DaleAiScreen> createState() => _DaleAiScreenState();
}

class _DaleAiScreenState extends State<DaleAiScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final List<_Msg> _messages = [
    _Msg("Hi, I'm Dale. Ask me about pricing, tasks, or your farm — or tell me where to go.", _Kind.bot),
  ];
  bool _sending = false;

  final DaleVoice _voice = DaleVoice();
  bool _voiceAvailable = false;
  bool _listening = false;
  bool _speakReplies = false;
  bool _spokenInput = false; // the last message came from the mic

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
    final turns = _messages.where((m) => m.kind != _Kind.system).toList();
    final recent = turns.length > 6 ? turns.sublist(turns.length - 6) : turns;
    return recent
        .map((m) => {'role': m.fromUser ? 'user' : 'assistant', 'content': m.text})
        .toList();
  }

  Future<void> _send([String? voiceText]) async {
    final text = (voiceText ?? _controller.text).trim();
    if (text.isEmpty || _sending) return;
    final loc = context.read<LocaleProvider>();
    final dale = context.read<DaleController>();
    final history = _history();
    setState(() {
      _messages.add(_Msg(text, _Kind.user));
      _sending = true;
      _controller.clear();
    });
    _scrollDown();
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
      setState(() => _messages.add(_Msg(reply, _Kind.bot)));
      // Hands-free: speak the reply back in the user's language when they spoke
      // (or when the speaker toggle is on).
      if (_speakReplies || _spokenInput) _voice.speak(reply, loc.language);
      _spokenInput = false;
      _runAction(res.action, dale);
    } catch (e) {
      if (mounted) setState(() => _messages.add(_Msg(friendlyError(e), _Kind.bot)));
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollDown();
    }
  }

  void _runAction(DaleAction? action, DaleController dale) {
    if (action == null) return;
    if (action.type == 'show_message' && (action.message ?? '').isNotEmpty) {
      setState(() => _messages.add(_Msg(action.message!, _Kind.bot)));
      return;
    }
    final confirmation = dale.handle(action);
    if (confirmation != null) {
      setState(() => _messages.add(_Msg(confirmation, _Kind.system)));
      _scrollDown();
    }
  }

  Future<void> _toggleListen() async {
    if (!_voiceAvailable) return;
    if (_listening) {
      await _voice.stopListening();
      if (mounted) setState(() => _listening = false);
      return;
    }
    final loc = context.read<LocaleProvider>();
    setState(() => _listening = true);
    await _voice.listen(
      lang: loc.language,
      onResult: (text, isFinal) {
        if (!mounted) return;
        setState(() => _controller.text = text);
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

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    _voice.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxW = Responsive.contentMaxWidth(context);
    return Scaffold(
      backgroundColor: context.palette.surface,
      appBar: AppBar(
        backgroundColor: context.palette.surface,
        foregroundColor: context.palette.ink,
        elevation: 0,
        titleSpacing: 0,
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.emeraldGrad),
              child: const Icon(Icons.smart_toy_rounded, color: Colors.white, size: 19),
            ),
            const SizedBox(width: 10),
            const Text('Dale AI',
                style: TextStyle(
                    fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 19)),
          ],
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW),
          child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length + (_sending ? 1 : 0),
                itemBuilder: (_, i) {
                  if (i >= _messages.length) return const _TypingRow();
                  return _Bubble(
                    _messages[i],
                    onCopy: () {
                      Clipboard.setData(ClipboardData(text: _messages[i].text));
                      showToast(context, 'Copied');
                    },
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: Row(
                  children: [
                    if (_voiceAvailable) ...[
                      _CircleButton(
                        icon: _listening ? Icons.mic_rounded : Icons.mic_none_rounded,
                        active: _listening,
                        onTap: _toggleListen,
                      ),
                      const SizedBox(width: 8),
                    ],
                    _CircleButton(
                      icon: _speakReplies ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                      active: _speakReplies,
                      onTap: _toggleSpeak,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(
                          hintText: _listening ? 'Listening…' : 'Message Dale…',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FloatingActionButton(
                      onPressed: _sending ? null : () => _send(),
                      backgroundColor: AppColors.primary,
                      elevation: 0,
                      child: const Icon(Icons.send_rounded, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _CircleButton({required this.icon, required this.active, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? AppColors.green : const Color(0xFFEFF5F1),
          border: Border.all(color: active ? AppColors.green : context.palette.line),
        ),
        child: Icon(icon, color: active ? Colors.white : AppColors.g700),
      ),
    );
  }
}

class _TypingRow extends StatelessWidget {
  const _TypingRow();
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: context.palette.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.palette.line),
        ),
        child: const DaleTypingDots(),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final _Msg msg;
  final VoidCallback onCopy;
  const _Bubble(this.msg, {required this.onCopy});

  @override
  Widget build(BuildContext context) {
    if (msg.kind == _Kind.system) {
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
                  child: Text(msg.text,
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
    final fromUser = msg.fromUser;
    return Align(
      alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onCopy,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
          decoration: BoxDecoration(
            gradient: fromUser ? AppColors.emeraldGrad : null,
            color: fromUser ? null : context.palette.card,
            borderRadius: BorderRadius.circular(16),
            border: fromUser ? null : Border.all(color: context.palette.line),
          ),
          child: DaleRichReply(
            text: msg.text,
            color: fromUser ? Colors.white : context.palette.ink,
          ),
        ),
      ),
    );
  }
}
