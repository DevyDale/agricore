import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/json_utils.dart';
import 'chat_models.dart';

const List<String> _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String initialsOf(String name) {
  final cleaned = name.replaceAll(RegExp(r'[^A-Za-z0-9 ]'), '').trim();
  if (cleaned.isEmpty) return 'C';
  final parts = cleaned.split(RegExp(r'\s+'));
  final s = parts.map((p) => p.isNotEmpty ? p[0] : '').join();
  return (s.isEmpty ? 'C' : s).substring(0, s.length >= 2 ? 2 : 1).toUpperCase();
}

String timeAgo(DateTime? d) {
  if (d == null) return '';
  final s = DateTime.now().difference(d).inSeconds;
  if (s < 60) return 'just now';
  final m = s ~/ 60;
  if (m < 60) return '${m}m ago';
  final h = m ~/ 60;
  if (h < 24) return '${h}h ago';
  final dd = h ~/ 24;
  if (dd < 7) return '${dd}d ago';
  return '${d.day} ${_months[d.month - 1]}';
}

String _two(int n) => n < 10 ? '0$n' : '$n';
String clock(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';
String dayLabel(DateTime d) {
  final now = DateTime.now();
  if (d.year == now.year && d.month == now.month && d.day == now.day) return 'Today';
  final y = now.subtract(const Duration(days: 1));
  if (d.year == y.year && d.month == y.month && d.day == y.day) return 'Yesterday';
  return '${_months[d.month - 1]} ${d.day}, ${d.year}';
}

class ConvAvatar extends StatelessWidget {
  final String name;
  final bool online;
  final double size;
  const ConvAvatar({super.key, required this.name, this.online = false, this.size = 46});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: online ? const [AppColors.green, AppColors.g600] : const [Color(0xFF94A3B8), Color(0xFF64748B)],
              ),
            ),
            child: Text(initialsOf(name),
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: size * 0.34)),
          ),
          if (online)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: const Color(0xFF22C55E),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.cream, width: 2.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Inline player for an audio attachment.
class AudioAttachment extends StatefulWidget {
  final String url;
  final bool mine;
  const AudioAttachment({super.key, required this.url, required this.mine});
  @override
  State<AudioAttachment> createState() => _AudioAttachmentState();
}

class _AudioAttachmentState extends State<AudioAttachment> {
  final _player = AudioPlayer();
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _player.onPlayerStateChanged.listen((s) {
      if (!mounted) return;
      setState(() => _playing = s == PlayerState.playing);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
    } else {
      await _player.play(UrlSource(absoluteUrl(widget.url) ?? widget.url));
    }
  }

  @override
  Widget build(BuildContext context) {
    final fg = widget.mine ? Colors.white : AppColors.g700;
    return GestureDetector(
      onTap: _toggle,
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: widget.mine ? Colors.white.withValues(alpha: 0.18) : Colors.white,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded, color: fg, size: 26),
            const SizedBox(width: 8),
            Icon(Icons.graphic_eq_rounded, color: fg, size: 18),
            const SizedBox(width: 6),
            Text('Voice note', style: TextStyle(color: fg, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

Widget attachmentWidget(ChatMessage m) {
  final url = m.attachmentUrl;
  if (url == null || url.isEmpty) return const SizedBox.shrink();
  final abs = absoluteUrl(url) ?? url;
  final mine = false; // colour handled by caller for audio; others neutral
  switch (m.messageType) {
    case 'image':
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: CachedNetworkImage(
            imageUrl: abs,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(height: 120, color: Colors.black12),
            errorWidget: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      );
    case 'audio':
      return AudioAttachment(url: url, mine: mine);
    default:
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: InkWell(
          onTap: () async {
            final uri = Uri.parse(abs);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.attach_file_rounded, size: 15),
              SizedBox(width: 6),
              Text('Open attachment', style: TextStyle(fontSize: 12.5, decoration: TextDecoration.underline)),
            ],
          ),
        ),
      );
  }
}
