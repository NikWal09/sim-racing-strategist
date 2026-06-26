/// Zakładka "Ustawienia" — wygląd/język + połączenie + głos + inżynier + nagrywanie.
///
/// Kolory bierze z motywu (`context.appColors`), teksty z i18n (AppSettings).
/// Zmiany trzymane w pamięci (engineerCfg / recordingCfg / speaker); motyw i język
/// zapisują się globalnie w [AppSettings].
library;

import 'package:flutter/material.dart';

import '../app_settings.dart';
import '../app_state.dart';
import 'theme.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key, required this.controller});

  final TelemetryController controller;

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  late final TextEditingController _ip =
      TextEditingController(text: widget.controller.playstationIp);
  late String _format = widget.controller.packetFormat;

  String _t(String k) => AppSettings.instance.t(k);

  @override
  void dispose() {
    _ip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final eng = c.engineerCfg;
    final rec = c.recordingCfg;
    final cc = context.appColors;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _section(_t('settings.section.appearance')),
        _themePicker(),
        const SizedBox(height: 10),
        _languagePicker(),
        const SizedBox(height: 10),
        _unitsPicker(),

        _section(_t('settings.section.telemetry')),
        TextField(
          controller: _ip,
          onChanged: (v) {
            c.playstationIp = v.trim();
            c.scheduleSettingsSave();
          },
          decoration: InputDecoration(
            labelText: _t('settings.consoleIp'),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Text(_t('settings.packetFormat'),
                style: TextStyle(color: cc.text)),
            const SizedBox(width: 12),
            DropdownButton<String>(
              value: _format,
              items: [
                DropdownMenuItem(value: 'A', child: Text(_t('settings.format.a'))),
                DropdownMenuItem(value: 'B', child: Text(_t('settings.format.b'))),
                DropdownMenuItem(
                    value: '~', child: Text(_t('settings.format.full'))),
              ],
              onChanged: (v) => setState(() {
                _format = v ?? 'B';
                c.packetFormat = _format;
                c.scheduleSettingsSave();
              }),
            ),
          ],
        ),

        _section(_t('settings.section.voice')),
        _switch(_t('settings.voiceEnabled'), c.voiceEnabled, c.setVoiceEnabled),
        _slider(_t('settings.speechRate'), c.speaker.speechRate, 0.2, 1.0, 8,
            (v) => setState(() => c.speaker.setRate(v))),

        _section(_t('settings.section.engineerMsgs')),
        _switch(_t('settings.announceLapTimes'), eng.announceLapTimes,
            (v) => setState(() => eng.announceLapTimes = v)),
        _switch(_t('settings.announceBestLap'), eng.announceBestLap,
            (v) => setState(() => eng.announceBestLap = v)),
        _switch(_t('settings.announcePositionChanges'),
            eng.announcePositionChanges,
            (v) => setState(() => eng.announcePositionChanges = v)),
        _switch(_t('settings.announceDelta'), eng.announceDelta,
            (v) => setState(() => eng.announceDelta = v)),
        _switch(_t('settings.announceCornerTyres'), eng.announceCornerTyres,
            (v) => setState(() => eng.announceCornerTyres = v)),
        _switch(_t('settings.announceRefSectors'), eng.announceRefSectors,
            (v) => setState(() => eng.announceRefSectors = v)),

        _section(_t('settings.section.engineerThresholds')),
        _slider(_t('settings.tyreTempWarning'), eng.tyreTempWarning, 80, 130, 50,
            (v) => setState(() => eng.tyreTempWarning = v),
            fmt: (v) => v.toStringAsFixed(0)),
        _slider(_t('settings.deltaThreshold'), eng.deltaMinSeconds, 0.05, 1.0, 19,
            (v) => setState(() => eng.deltaMinSeconds = v),
            fmt: (v) => v.toStringAsFixed(2)),
        _slider(_t('settings.refSectors'), eng.refSectors.toDouble(), 1, 5, 4,
            (v) => setState(() => eng.refSectors = v.round()),
            fmt: (v) => v.round().toString()),

        _section(_t('settings.section.recording')),
        _switch(_t('settings.recordLaps'), rec.enabled,
            (v) => setState(() => rec.enabled = v)),
        _slider(_t('settings.minLapLength'), rec.minLapSeconds, 5, 60, 11,
            (v) => setState(() => rec.minLapSeconds = v),
            fmt: (v) => v.toStringAsFixed(0)),

        const SizedBox(height: 16),
        Text(_t('settings.footer'),
            style: TextStyle(color: cc.muted, fontSize: 12)),
      ],
    );
  }

  Widget _themePicker() {
    final s = AppSettings.instance;
    Widget chip(String label, ThemeMode mode) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(label),
            selected: s.themeMode == mode,
            onSelected: (_) => setState(() => s.setThemeMode(mode)),
          ),
        );
    return Row(
      children: [
        Icon(Icons.brightness_6, size: 18, color: context.appColors.muted),
        const SizedBox(width: 8),
        chip(_t('settings.themeSystem'), ThemeMode.system),
        chip(_t('settings.themeLight'), ThemeMode.light),
        chip(_t('settings.themeDark'), ThemeMode.dark),
      ],
    );
  }

  Widget _languagePicker() {
    final s = AppSettings.instance;
    void pick(String lang) {
      setState(() => s.setLocale(lang));
      // Język steruje też głosem inżyniera (locale TTS).
      widget.controller.speaker.setLanguage(lang);
    }

    Widget chip(String label, String lang) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(label),
            selected: s.locale == lang,
            onSelected: (_) => pick(lang),
          ),
        );
    return Row(
      children: [
        Icon(Icons.language, size: 18, color: context.appColors.muted),
        const SizedBox(width: 8),
        chip(_t('settings.langPolish'), 'pl'),
        chip(_t('settings.langEnglish'), 'en'),
      ],
    );
  }

  Widget _unitsPicker() {
    final s = AppSettings.instance;
    Widget chip(String label, String u) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(label),
            selected: s.units == u,
            onSelected: (_) => setState(() => s.setUnits(u)),
          ),
        );
    return Row(
      children: [
        Icon(Icons.straighten, size: 18, color: context.appColors.muted),
        const SizedBox(width: 8),
        chip(_t('units.metric'), 'metric'),
        chip(_t('units.imperial'), 'imperial'),
      ],
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 6),
        child: Text(title.toUpperCase(),
            style: TextStyle(
                color: context.appColors.accent,
                fontWeight: FontWeight.w700,
                letterSpacing: 1)),
      );

  Widget _switch(String label, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: TextStyle(color: context.appColors.text)),
      value: value,
      onChanged: (v) {
        onChanged(v);
        widget.controller.scheduleSettingsSave();
        setState(() {});
      },
    );
  }

  Widget _slider(String label, double value, double min, double max,
      int divisions, ValueChanged<double> onChanged,
      {String Function(double)? fmt}) {
    final show = (fmt ?? (v) => v.toStringAsFixed(2))(value);
    final cc = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: TextStyle(color: cc.text)),
              Text(show, style: TextStyle(color: cc.muted2)),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: (v) {
              onChanged(v);
              widget.controller.scheduleSettingsSave();
            },
          ),
        ],
      ),
    );
  }
}
