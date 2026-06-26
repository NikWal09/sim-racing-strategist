/// Warstwa mowy oparta o flutter_tts (natywny TTS Androida/iOS).
///
/// Port zachowania `gt7_engineer/speech/speaker.py`: kolejka priorytetowa (krytyczne
/// wyprzedzaja blahe) + anti-spam po kluczu (ten sam komunikat nie powtarza sie
/// czesciej niz co [minGapSeconds]). Mowienie idzie sekwencyjnie — kolejny tekst
/// startuje dopiero, gdy poprzedni sie skonczy (awaitSpeakCompletion).
library;

import 'package:flutter_tts/flutter_tts.dart';

/// Nizsza wartosc = wyzszy priorytet (jak Priority w wersji Pythona).
enum Priority { critical, high, normal, low }

class _Utt {
  _Utt(this.priority, this.seq, this.text);
  final int priority;
  final int seq;
  final String text;
}

class Speaker {
  Speaker({
    this.enabled = true,
    this.minGapSeconds = 1.5,
    this.language = 'pl',
    this.speechRate = 0.5,
    this.volume = 1.0,
  });

  bool enabled;
  double minGapSeconds;
  String language; // 'pl' albo 'en'
  double speechRate; // 0.0 - 1.0 (flutter_tts)
  double volume; // 0.0 - 1.0

  final FlutterTts _tts = FlutterTts();
  final List<_Utt> _queue = [];
  final Map<String, DateTime> _last = {};
  int _seq = 0;
  bool _draining = false;
  bool _inited = false;

  String get _locale => language == 'en' ? 'en-US' : 'pl-PL';

  /// Inicjuje silnik (jezyk, tempo, glosnosc, czekanie na koniec wypowiedzi).
  Future<void> init() async {
    await _tts.awaitSpeakCompletion(true);
    await _tts.setLanguage(_locale);
    await _tts.setSpeechRate(speechRate);
    await _tts.setVolume(volume.clamp(0.0, 1.0));
    _inited = true;
  }

  Future<void> setLanguage(String lang) async {
    language = lang;
    await _tts.setLanguage(_locale);
  }

  Future<void> setRate(double rate) async {
    speechRate = rate.clamp(0.0, 1.0);
    await _tts.setSpeechRate(speechRate);
  }

  /// Glosy dostepne dla biezacego jezyka (lista map {name, locale}).
  Future<List<Map<String, String>>> voicesForLanguage(String lang) async {
    final raw = await _tts.getVoices;
    final out = <Map<String, String>>[];
    if (raw is List) {
      for (final v in raw) {
        final name = '${v['name'] ?? ''}';
        final loc = '${v['locale'] ?? ''}';
        if (loc.toLowerCase().startsWith(lang.toLowerCase())) {
          out.add({'name': name, 'locale': loc});
        }
      }
    }
    out.sort((a, b) => a['name']!.compareTo(b['name']!));
    return out;
  }

  Future<void> setVoice(String name, String locale) async {
    await _tts.setVoice({'name': name, 'locale': locale});
  }

  /// Dodaje komunikat do kolejki. [key] = kategoria do anti-spamu; jesli ten sam
  /// key padl niedawno (< [minGap] s), komunikat jest pomijany. Zwraca true, gdy
  /// zakolejkowano.
  bool say(
    String text, {
    Priority priority = Priority.normal,
    String? key,
    double? minGap,
  }) {
    if (!enabled) return false;
    if (key != null) {
      final gap = minGap ?? minGapSeconds;
      final now = DateTime.now();
      final last = _last[key];
      if (last != null && now.difference(last).inMilliseconds < gap * 1000) {
        return false;
      }
      _last[key] = now;
    }
    _queue.add(_Utt(priority.index, _seq++, text));
    _drain();
    return true;
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    if (!_inited) await init();
    while (_queue.isNotEmpty) {
      _queue.sort((a, b) =>
          a.priority != b.priority ? a.priority - b.priority : a.seq - b.seq);
      final u = _queue.removeAt(0);
      try {
        await _tts.speak(u.text);
      } catch (_) {
        // Nie wywracaj kolejki przy bledzie pojedynczego komunikatu.
      }
    }
    _draining = false;
  }

  /// Przerywa biezaca wypowiedz i czysci kolejke.
  Future<void> stopNow() async {
    _queue.clear();
    await _tts.stop();
  }
}
