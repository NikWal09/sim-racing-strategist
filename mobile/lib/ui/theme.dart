/// Wspolny motyw aplikacji — paleta i style przeniesione 1:1 z desktopu (Qt QSS
/// w `gt7_gui_qt.py`), zeby obie wersje wygladaly tak samo.
library;

import 'package:flutter/material.dart';

/// Ciemna paleta (te same wartosci co DARK_QSS na desktopie). Dashboard zostaje
/// na tej palecie zawsze (czytelnosc w sloncu) — patrz [AppColors].
class AppColors {
  static const bg = Color(0xFF12151A); // tlo okna
  static const panel = Color(0xFF161A21); // tlo paneli / pasek zakladek
  static const tileTop = Color(0xFF1D242E); // gradient kafelka - gora
  static const tileBottom = Color(0xFF171C24); // gradient kafelka - dol
  static const tileBorder = Color(0xFF2A3340);
  static const stroke = Color(0xFF29313C); // ramki
  static const accent = Color(0xFF3D7BFD); // niebieski akcent (predkosc, podkreslenie)
  static const accentRpm = Color(0xFFF4A72A); // pomaranczowy (RPM)
  static const danger = Color(0xFFE0554A); // czerwony (redline, strata, stop)
  static const good = Color(0xFF5BD17A); // zielony (zysk, opona OK)
  static const warn = Color(0xFFF4A72A); // zolty (ostrzezenie)
  static const text = Color(0xFFE6E8EB);
  static const muted = Color(0xFF8D95A3); // szary podpis
  static const muted2 = Color(0xFF9AA0A6);
  static const gaugeTrack = Color(0xFF272F3A); // tlo luku zegara
  static const tick = Color(0xFF3A4452); // podzialka
}

/// Motywozalezna paleta (rozszerzenie ThemeData). Ekrany migrowane na jasny/ciemny
/// motyw czytaja kolory przez `context.appColors`, dzieki czemu zmieniaja sie
/// razem z motywem. Dashboard (CustomPainter) celowo dalej uzywa staej [AppColors].
@immutable
class AppColorsExt extends ThemeExtension<AppColorsExt> {
  const AppColorsExt({
    required this.bg,
    required this.panel,
    required this.tileTop,
    required this.tileBottom,
    required this.tileBorder,
    required this.stroke,
    required this.accent,
    required this.accentRpm,
    required this.danger,
    required this.good,
    required this.warn,
    required this.text,
    required this.muted,
    required this.muted2,
  });

  final Color bg, panel, tileTop, tileBottom, tileBorder, stroke;
  final Color accent, accentRpm, danger, good, warn;
  final Color text, muted, muted2;

  @override
  AppColorsExt copyWith({
    Color? bg,
    Color? panel,
    Color? tileTop,
    Color? tileBottom,
    Color? tileBorder,
    Color? stroke,
    Color? accent,
    Color? accentRpm,
    Color? danger,
    Color? good,
    Color? warn,
    Color? text,
    Color? muted,
    Color? muted2,
  }) {
    return AppColorsExt(
      bg: bg ?? this.bg,
      panel: panel ?? this.panel,
      tileTop: tileTop ?? this.tileTop,
      tileBottom: tileBottom ?? this.tileBottom,
      tileBorder: tileBorder ?? this.tileBorder,
      stroke: stroke ?? this.stroke,
      accent: accent ?? this.accent,
      accentRpm: accentRpm ?? this.accentRpm,
      danger: danger ?? this.danger,
      good: good ?? this.good,
      warn: warn ?? this.warn,
      text: text ?? this.text,
      muted: muted ?? this.muted,
      muted2: muted2 ?? this.muted2,
    );
  }

  @override
  AppColorsExt lerp(ThemeExtension<AppColorsExt>? other, double t) {
    if (other is! AppColorsExt) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColorsExt(
      bg: c(bg, other.bg),
      panel: c(panel, other.panel),
      tileTop: c(tileTop, other.tileTop),
      tileBottom: c(tileBottom, other.tileBottom),
      tileBorder: c(tileBorder, other.tileBorder),
      stroke: c(stroke, other.stroke),
      accent: c(accent, other.accent),
      accentRpm: c(accentRpm, other.accentRpm),
      danger: c(danger, other.danger),
      good: c(good, other.good),
      warn: c(warn, other.warn),
      text: c(text, other.text),
      muted: c(muted, other.muted),
      muted2: c(muted2, other.muted2),
    );
  }
}

const _darkExt = AppColorsExt(
  bg: Color(0xFF12151A),
  panel: Color(0xFF161A21),
  tileTop: Color(0xFF1D242E),
  tileBottom: Color(0xFF171C24),
  tileBorder: Color(0xFF2A3340),
  stroke: Color(0xFF29313C),
  accent: Color(0xFF3D7BFD),
  accentRpm: Color(0xFFF4A72A),
  danger: Color(0xFFE0554A),
  good: Color(0xFF5BD17A),
  warn: Color(0xFFF4A72A),
  text: Color(0xFFE6E8EB),
  muted: Color(0xFF8D95A3),
  muted2: Color(0xFF9AA0A6),
);

const _lightExt = AppColorsExt(
  bg: Color(0xFFF4F6F8),
  panel: Color(0xFFFFFFFF),
  tileTop: Color(0xFFFFFFFF),
  tileBottom: Color(0xFFEFF2F5),
  tileBorder: Color(0xFFD7DCE2),
  stroke: Color(0xFFD0D5DB),
  accent: Color(0xFF2D6BF0),
  accentRpm: Color(0xFFD98200),
  danger: Color(0xFFCF3A2F),
  good: Color(0xFF2E9E4C),
  warn: Color(0xFFC9871A),
  text: Color(0xFF1A1D21),
  muted: Color(0xFF5C636C),
  muted2: Color(0xFF6B7480),
);

/// Skrot: kolory motywu z kontekstu. Gdy brak rozszerzenia — ciemne (fallback).
extension AppColorsContext on BuildContext {
  AppColorsExt get appColors =>
      Theme.of(this).extension<AppColorsExt>() ?? _darkExt;
}

ThemeData _build(Brightness brightness, AppColorsExt ext) {
  final base = ThemeData(brightness: brightness, useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: ext.bg,
    extensions: [ext],
    colorScheme: base.colorScheme.copyWith(
      primary: ext.accent,
      surface: ext.panel,
      error: ext.danger,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: ext.panel,
      foregroundColor: ext.text,
      elevation: 0,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: ext.accent,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
    ),
  );
}

ThemeData buildDarkTheme() => _build(Brightness.dark, _darkExt);
ThemeData buildLightTheme() => _build(Brightness.light, _lightExt);

/// Zgodnosc wsteczna — domyslnie ciemny.
ThemeData buildAppTheme() => buildDarkTheme();

/// Reuzywalny kafelek z tytulem i wartoscia (jak QFrame#tile na desktopie).
class InfoTile extends StatelessWidget {
  const InfoTile({
    super.key,
    required this.title,
    required this.value,
    this.valueColor = Colors.white,
    this.sub,
  });

  final String title;
  final String value;
  final Color valueColor;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.tileTop, AppColors.tileBottom],
        ),
        border: Border.all(color: AppColors.tileBorder),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title.toUpperCase(),
              style: const TextStyle(
                  color: AppColors.muted, fontSize: 11, letterSpacing: 1)),
          const SizedBox(height: 3),
          Text(value,
              style: TextStyle(
                  fontSize: 21, fontWeight: FontWeight.w700, color: valueColor)),
          if (sub != null)
            Text(sub!,
                style: const TextStyle(color: AppColors.muted2, fontSize: 11)),
        ],
      ),
    );
  }
}
