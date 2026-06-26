/// Zakladka "Test glosow" — odpowiednik zakladki Test glosow z desktopu.
///
/// Wybierasz glos (sposrod polskich glosow systemowych), tempo i przykladowy
/// komunikat, po czym go odsluchujesz. Korzysta z natywnego TTS (flutter_tts).
library;

import 'package:flutter/material.dart';

import '../app_settings.dart';
import '../messages/messages_pl.dart';
import '../speech/speaker.dart';
import 'theme.dart';

class VoiceTab extends StatefulWidget {
  const VoiceTab({super.key});

  @override
  State<VoiceTab> createState() => _VoiceTabState();
}

class _VoiceTabState extends State<VoiceTab> {
  final Speaker _speaker = Speaker();
  final PolishMessages _m = PolishMessages();
  late final List<({String label, String Function() build})> _samples =
      voiceSamples(_m);

  List<Map<String, String>> _voices = [];
  Map<String, String>? _voice; // wybrany glos (null = domyslny)
  int _sample = 0;
  double _rate = 0.5;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _loadVoices();
  }

  Future<void> _loadVoices() async {
    List<Map<String, String>> v = [];
    try {
      await _speaker.init();
      v = await _speaker.voicesForLanguage('pl');
    } catch (_) {
      // TTS niedostępny (np. środowisko testowe) - lista zostaje pusta.
    }
    if (!mounted) return;
    setState(() {
      _voices = v;
      final t = AppSettings.instance.t;
      _status = v.isEmpty
          ? t('voice.noVoices')
          : '${t('voice.voicesCount')}: ${v.length}.';
    });
  }

  @override
  void dispose() {
    _speaker.stopNow();
    super.dispose();
  }

  Future<void> _play() async {
    final text = _samples[_sample].build();
    setState(() => _status = '${AppSettings.instance.t('voice.playing')}: $text');
    await _speaker.setRate(_rate);
    final v = _voice;
    if (v != null) await _speaker.setVoice(v['name']!, v['locale']!);
    _speaker.say(text); // bez klucza = zawsze odtworz
  }

  @override
  Widget build(BuildContext context) {
    final cc = context.appColors;
    String t(String k) => AppSettings.instance.t(k);
    final labelStyle =
        TextStyle(color: cc.muted, fontSize: 11, letterSpacing: 1);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(t('voice.label.voice'), style: labelStyle),
        DropdownButton<Map<String, String>?>(
          isExpanded: true,
          value: _voice,
          hint: Text(t('voice.defaultVoice')),
          items: [
            DropdownMenuItem(value: null, child: Text(t('voice.defaultVoice'))),
            for (final v in _voices)
              DropdownMenuItem(value: v, child: Text(v['name'] ?? '?')),
          ],
          onChanged: (v) => setState(() => _voice = v),
        ),
        const SizedBox(height: 16),
        Text(t('voice.label.tempo'), style: labelStyle),
        Slider(
          value: _rate,
          min: 0.2,
          max: 1.0,
          divisions: 8,
          label: _rate.toStringAsFixed(2),
          onChanged: (v) => setState(() => _rate = v),
        ),
        const SizedBox(height: 8),
        Text(t('voice.label.message'), style: labelStyle),
        DropdownButton<int>(
          isExpanded: true,
          value: _sample,
          items: [
            for (var i = 0; i < _samples.length; i++)
              DropdownMenuItem(value: i, child: Text(_samples[i].label)),
          ],
          onChanged: (i) => setState(() => _sample = i ?? 0),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _play,
          icon: const Icon(Icons.play_arrow),
          label: Text(t('voice.play')),
        ),
        const SizedBox(height: 12),
        Text(_status, style: TextStyle(color: cc.muted)),
      ],
    );
  }
}
