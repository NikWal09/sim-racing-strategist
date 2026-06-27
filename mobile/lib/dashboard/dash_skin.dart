/// Skórki wizualne dashboardu (handoff Część 3).
///
/// Dashboard nie korzysta już ze stałej palety — kolory, gradienty, obrys,
/// promień rogów, poświata i tekstura pochodzą z aktywnej [DashSkin]. Aktywną
/// skórkę trzyma AppSettings (zapisywana). Wartości 1:1 z makiety.
library;

import 'package:flutter/material.dart';

class DashSkin {
  const DashSkin({
    required this.id,
    required this.name,
    required this.tag,
    required this.screen,
    required this.tile,
    required this.border,
    required this.text,
    required this.muted,
    required this.faint,
    required this.speed,
    required this.rpm,
    required this.good,
    required this.danger,
    required this.warn,
    required this.track,
    required this.radius,
    this.glow = false,
    this.carbon = false,
    this.tileShadow,
  });

  final String id;
  final String name;
  final String tag;
  final Gradient screen; // tło ekranu (baza; dla carbon rysujemy splot na wierzchu)
  final Gradient tile; // tło kafelka
  final Color border;
  final Color text;
  final Color muted;
  final Color faint;
  final Color speed;
  final Color rpm;
  final Color good;
  final Color danger;
  final Color warn;
  final Color track; // tło łuków/pasków
  final double radius;
  final bool glow; // poświata pod wypełnieniem łuku/paska
  final bool carbon; // tekstura splotu węglowego
  final List<BoxShadow>? tileShadow;
}

LinearGradient _v(int a, int b) => LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(a), Color(b)],
    );

RadialGradient _r(List<int> colors) => RadialGradient(
      center: const Alignment(0, -0.7),
      radius: 1.3,
      colors: colors.map((c) => Color(c)).toList(),
    );

const _kCarbon = DashSkin(
  id: 'carbon',
  name: 'Carbon',
  tag: 'Domyślna',
  screen: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF11151B), Color(0xFF0B0E12)]),
  tile: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF1E2530), Color(0xFF141A22)]),
  border: Color(0xFF2A3340),
  text: Color(0xFFE6E8EB),
  muted: Color(0xFF8D95A3),
  faint: Color(0xFF5A6472),
  speed: Color(0xFF3D7BFD),
  rpm: Color(0xFFF4A72A),
  good: Color(0xFF5BD17A),
  danger: Color(0xFFE0554A),
  warn: Color(0xFFF4A72A),
  track: Color(0xFF272F3A),
  radius: 12,
);

final _kApex = DashSkin(
  id: 'apex',
  name: 'Apex',
  tag: 'Neon',
  screen: _r(const [0xFF0B1117, 0xFF04070A]),
  tile: _v(0xFF0F1620, 0xFF080C11),
  border: const Color(0xFF18242E),
  text: const Color(0xFFEAF4F4),
  muted: const Color(0xFF6E8794),
  faint: const Color(0xFF394A55),
  speed: const Color(0xFF16E0D8),
  rpm: const Color(0xFFF5B92E),
  good: const Color(0xFF3BE38C),
  danger: const Color(0xFFFF4A5C),
  warn: const Color(0xFFFFC23D),
  track: const Color(0xFF132129),
  radius: 9,
  glow: true,
);

final _kDaylight = DashSkin(
  id: 'daylight',
  name: 'Daylight',
  tag: 'Jasna',
  screen: _v(0xFFEEF2F6, 0xFFDFE6ED),
  tile: _v(0xFFFFFFFF, 0xFFF0F4F8),
  border: const Color(0xFFD6DCE3),
  text: const Color(0xFF171C22),
  muted: const Color(0xFF5C6470),
  faint: const Color(0xFF9AA4AF),
  speed: const Color(0xFF2D6BF0),
  rpm: const Color(0xFFD98200),
  good: const Color(0xFF2E9E4C),
  danger: const Color(0xFFCF3A2F),
  warn: const Color(0xFFC9871A),
  track: const Color(0xFFDCE2E9),
  radius: 12,
  tileShadow: const [
    BoxShadow(color: Color(0x14141E32), blurRadius: 2, offset: Offset(0, 1)),
  ],
);

final _kCarbonFiber = DashSkin(
  id: 'carbonfiber',
  name: 'Carbon Fiber',
  tag: 'Splot',
  screen: _v(0xFF141519, 0xFF0F1115),
  tile: _v(0xFF262A30, 0xFF15171B),
  border: const Color(0xFF33373F),
  text: const Color(0xFFECEEF1),
  muted: const Color(0xFF969CA6),
  faint: const Color(0xFF5E646E),
  speed: const Color(0xFFE8EAEE),
  rpm: const Color(0xFFF5A623),
  good: const Color(0xFF54D27E),
  danger: const Color(0xFFE84545),
  warn: const Color(0xFFF5A623),
  track: const Color(0xFF2B2F37),
  radius: 10,
  carbon: true,
  tileShadow: const [
    BoxShadow(color: Color(0x66000000), blurRadius: 8, offset: Offset(0, 2)),
  ],
);

final _kRedline = DashSkin(
  id: 'redline',
  name: 'Redline',
  tag: 'Agresywna',
  screen: _r(const [0xFF22090A, 0xFF080404]),
  tile: _v(0xFF231114, 0xFF160B0D),
  border: const Color(0xFF3A1A1D),
  text: const Color(0xFFF4ECEC),
  muted: const Color(0xFFA8868A),
  faint: const Color(0xFF5C3E42),
  speed: const Color(0xFFFF3B30),
  rpm: const Color(0xFFFF9F1C),
  good: const Color(0xFF3DDC84),
  danger: const Color(0xFFFF2A2A),
  warn: const Color(0xFFFFB020),
  track: const Color(0xFF341619),
  radius: 8,
  glow: true,
);

final _kLeMans = DashSkin(
  id: 'lemans',
  name: 'Le Mans',
  tag: 'Heritage',
  screen: _v(0xFF17283C, 0xFF0C1622),
  tile: _v(0xFF1C3149, 0xFF122231),
  border: const Color(0xFF284260),
  text: const Color(0xFFEDEFF2),
  muted: const Color(0xFF8AA0B6),
  faint: const Color(0xFF506C86),
  speed: const Color(0xFF52A8DD),
  rpm: const Color(0xFFF0681E),
  good: const Color(0xFF52D08A),
  danger: const Color(0xFFF0681E),
  warn: const Color(0xFFF2A23C),
  track: const Color(0xFF22384F),
  radius: 11,
);

final _kToxic = DashSkin(
  id: 'toxic',
  name: 'Toxic',
  tag: 'Motorsport',
  screen: _r(const [0xFF101810, 0xFF070A07]),
  tile: _v(0xFF16221A, 0xFF0B120D),
  border: const Color(0xFF23351F),
  text: const Color(0xFFEAF2E6),
  muted: const Color(0xFF8FA386),
  faint: const Color(0xFF516046),
  speed: const Color(0xFF9EFF2E),
  rpm: const Color(0xFFFFC400),
  good: const Color(0xFF9EFF2E),
  danger: const Color(0xFFFF425A),
  warn: const Color(0xFFFFC400),
  track: const Color(0xFF21311C),
  radius: 8,
  glow: true,
);

/// Wszystkie skórki (kolejność = kolejność w wyborze).
final List<DashSkin> kDashSkins = [
  _kCarbon,
  _kApex,
  _kDaylight,
  _kCarbonFiber,
  _kRedline,
  _kLeMans,
  _kToxic,
];

DashSkin dashSkinById(String id) =>
    kDashSkins.firstWhere((s) => s.id == id, orElse: () => kDashSkins.first);
