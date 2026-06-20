import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../core/config/app_config.dart';
import '../../core/utils/log.dart';

/// Live chat socket. Emits decoded JSON frames (messages + presence/_update).
/// Reconnects once after a short delay if the socket drops while open.
class ChatSocket {
  WebSocketChannel? _ch;
  StreamSubscription? _sub;
  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  int? _convId;
  String? _token;
  bool _disposed = false;

  Stream<Map<String, dynamic>> get stream => _controller.stream;

  void connect(int conversationId, String? token) {
    _convId = conversationId;
    _token = token;
    _open();
  }

  void _open() {
    if (_disposed || _convId == null) return;
    final url = '${AppConfig.wsBaseUrl}/ws/chat/$_convId/?token=${Uri.encodeComponent(_token ?? '')}';
    try {
      _ch = WebSocketChannel.connect(Uri.parse(url));
      _sub = _ch!.stream.listen(
        (data) {
          try {
            final decoded = jsonDecode(data as String);
            if (decoded is Map) _controller.add(decoded.cast<String, dynamic>());
          } catch (e) {
            logSwallowed('ChatWs.onMessage', e);
          }
        },
        onError: (_) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  bool _reconnecting = false;
  void _scheduleReconnect() {
    if (_disposed || _reconnecting) return;
    _reconnecting = true;
    Future.delayed(const Duration(seconds: 3), () {
      _reconnecting = false;
      if (_disposed) return;
      _teardownSocket();
      _open();
    });
  }

  void _teardownSocket() {
    try {
      _sub?.cancel();
    } catch (_) {/* best-effort cleanup */}
    try {
      _ch?.sink.close();
    } catch (_) {/* best-effort cleanup */}
    _sub = null;
    _ch = null;
  }

  void dispose() {
    _disposed = true;
    _teardownSocket();
    _controller.close();
  }
}
