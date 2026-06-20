import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../../core/utils/log.dart';

/// Language-aware speech in/out for Dale: recognises the user's speech in the
/// language they're using and speaks Dale's reply back in that same language.
/// Shared by the floating Dale panel and the full-screen Dale.
class DaleVoice {
  final stt.SpeechToText _stt = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();

  bool available = false;
  List<stt.LocaleName> _locales = const [];

  Future<void> init({
    void Function(String status)? onStatus,
    void Function(String error)? onError,
  }) async {
    try {
      available = await _stt.initialize(
        onStatus: (s) => onStatus?.call(s),
        onError: (e) => onError?.call(e.errorMsg),
      );
      if (available) {
        try {
          _locales = await _stt.locales();
        } catch (e) {
          logSwallowed('DaleVoice.locales', e);
        }
      }
    } catch (e) {
      logSwallowed('DaleVoice.init', e);
      available = false;
    }
  }

  bool get isListening => _stt.isListening;

  /// Canonical BCP-47 tag for text-to-speech (and an STT fallback).
  static String bcp47(String lang) {
    switch (lang) {
      case 'fr':
        return 'fr-FR';
      case 'es':
        return 'es-ES';
      case 'pt':
        return 'pt-PT';
      case 'sw':
        return 'sw-KE';
      case 'ar':
        return 'ar-SA';
      case 'lg':
        return 'lg-UG';
      default:
        return 'en-US';
    }
  }

  /// Best on-device recogniser locale for [lang] (e.g. picks 'sw_KE' or 'sw_TZ'
  /// for 'sw'); falls back to the canonical tag when none is installed.
  String _sttLocaleId(String lang) {
    final want = lang.toLowerCase();
    for (final l in _locales) {
      final id = l.localeId.toLowerCase().replaceAll('-', '_');
      if (id == want || id.startsWith('${want}_')) return l.localeId;
    }
    return bcp47(lang);
  }

  /// True if the device actually has a recogniser for [lang].
  bool supportsLanguage(String lang) {
    final want = lang.toLowerCase();
    return _locales.any((l) {
      final id = l.localeId.toLowerCase().replaceAll('-', '_');
      return id == want || id.startsWith('${want}_');
    });
  }

  Future<void> listen({
    required String lang,
    required void Function(String text, bool isFinal) onResult,
  }) async {
    if (!available) return;
    await _stt.listen(
      listenOptions:
          stt.SpeechListenOptions(cancelOnError: true, localeId: _sttLocaleId(lang)),
      onResult: (r) => onResult(r.recognizedWords, r.finalResult),
    );
  }

  Future<void> stopListening() async {
    try {
      await _stt.stop();
    } catch (e) {
      logSwallowed('DaleVoice.stopListening', e);
    }
  }

  /// Speaks [text] in [lang] (markdown stripped first). Best-effort.
  Future<void> speak(String text, String lang) async {
    try {
      await _tts.setLanguage(bcp47(lang));
      await _tts.stop();
      await _tts.speak(_plain(text));
    } catch (e) {
      logSwallowed('DaleVoice.speak', e);
    }
  }

  Future<void> stopSpeaking() async {
    try {
      await _tts.stop();
    } catch (_) {/* best-effort */}
  }

  void dispose() {
    try {
      _stt.cancel();
      _tts.stop();
    } catch (_) {/* best-effort */}
  }

  static String _plain(String md) => md
      .replaceAll(RegExp(r'\*\*(.+?)\*\*'), r'$1')
      .replaceAll(RegExp(r'^[\-\*•]\s+', multiLine: true), '')
      .trim();
}
