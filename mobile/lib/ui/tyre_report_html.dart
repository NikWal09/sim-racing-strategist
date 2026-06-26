/// Raport temperatur opon jako samodzielny HTML — port `tools/tyre_report.py`.
///
/// Wykrywa zakręty offline z kształtu śladu (ta sama heurystyka co inżynier na
/// żywo), liczy średnie/maks. temperatury opon per okrążenie i per zakręt, i
/// składa stronę HTML z tabelami + wykresem trendu SVG. Wygląd 1:1 z desktopem.
library;

import 'dart:math' as math;

const List<String> _tyres = ['FL', 'FR', 'RL', 'RR'];
const List<String> _tyresPl = [
  'lewa przednia',
  'prawa przednia',
  'lewa tylna',
  'prawa tylna'
];
const List<String> _tyreChannels = ['tyre_fl', 'tyre_fr', 'tyre_rl', 'tyre_rr'];

const double _enterYawDps = 14.0;
const double _exitYawDps = 7.0;
const double _minSpeedKph = 30.0;
const double _minEnterS = 0.20;
const double _minExitS = 0.45;

Map<String, int> _chanIdx(Map<String, dynamic> lap) {
  final ch = (lap['channels'] as List?)?.cast<String>() ?? const [];
  return {for (var i = 0; i < ch.length; i++) ch[i]: i};
}

bool hasTyreData(Map<String, dynamic> lap) {
  final idx = _chanIdx(lap);
  return _tyreChannels.every(idx.containsKey);
}

List<List<num>> _samples(Map<String, dynamic> lap) =>
    (lap['samples'] as List).map((s) => (s as List).cast<num>()).toList();

String _esc(Object? s) => '$s'
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

/// Segmenty zakrętów [[start, end], ...] ze zmiany kierunku jazdy w x-z.
List<List<int>> _detectCorners(List<List<num>> samples, Map<String, int> idx) {
  final it = idx['t']!, ix = idx['x']!, iz = idx['z']!;
  final iv = idx['speed_kph'];
  final corners = <List<int>>[];
  double? heading;
  var inCorner = false;
  double? enterSince, exitSince;
  var startI = 0;

  for (var i = 1; i < samples.length; i++) {
    final s0 = samples[i - 1], s1 = samples[i];
    final t0 = s0[it].toDouble(), t1 = s1[it].toDouble();
    final dt = t1 - t0;
    final dx = s1[ix] - s0[ix], dz = s1[iz] - s0[iz];
    final speed = iv != null ? s1[iv].toDouble() : 999.0;
    var yawDps = 0.0;
    if (dt > 0 && (dx.abs() + dz.abs()) > 1e-3 && speed >= _minSpeedKph) {
      final h = math.atan2(dz.toDouble(), dx.toDouble());
      if (heading != null) {
        var d = h - heading;
        while (d > math.pi) {
          d -= 2 * math.pi;
        }
        while (d < -math.pi) {
          d += 2 * math.pi;
        }
        yawDps = (d * 180 / math.pi / dt).abs();
      }
      heading = h;
    } else {
      heading = null;
    }

    if (!inCorner) {
      if (yawDps >= _enterYawDps) {
        if (enterSince == null) {
          enterSince = t1;
          startI = i;
        }
        if (t1 - enterSince >= _minEnterS) {
          inCorner = true;
          exitSince = null;
        }
      } else {
        enterSince = null;
      }
    } else {
      if (yawDps < _exitYawDps) {
        exitSince ??= t1;
        if (t1 - exitSince >= _minExitS) {
          corners.add([startI, i]);
          inCorner = false;
          enterSince = null;
          exitSince = null;
        }
      } else {
        exitSince = null;
      }
    }
  }
  if (inCorner) corners.add([startI, samples.length - 1]);
  return corners;
}

Map<String, dynamic>? _analyzeLap(Map<String, dynamic> lap) {
  if (!hasTyreData(lap)) return null;
  final idx = _chanIdx(lap);
  final samples = _samples(lap);
  final ti = [for (final c in _tyreChannels) idx[c]!];
  final n = samples.length;

  final avg = [
    for (final i in ti) samples.fold<double>(0, (a, s) => a + s[i]) / n
  ];
  final mx = [
    for (final i in ti)
      samples.fold<double>(-1e9, (a, s) => math.max(a, s[i].toDouble()))
  ];

  final corners = <Map<String, dynamic>>[];
  final segs = _detectCorners(samples, idx);
  for (var no = 0; no < segs.length; no++) {
    final a = segs[no][0], b = segs[no][1];
    var peak = 0.0, tyre = 0;
    for (var j = a; j <= b; j++) {
      for (var k = 0; k < ti.length; k++) {
        final v = samples[j][ti[k]].toDouble();
        if (v > peak) {
          peak = v;
          tyre = k;
        }
      }
    }
    corners.add({'no': no + 1, 'peak': _r1(peak), 'tyre': tyre});
  }
  return {
    'avg': [for (final v in avg) _r1(v)],
    'max': [for (final v in mx) _r1(v)],
    'corners': corners,
  };
}

double _r1(double v) => (v * 10).round() / 10;

String _svgChart(List<List<double?>> series, List<String> labels,
    {int width = 860, int height = 260}) {
  const colors = ['#4f8cff', '#f4a72a', '#5bd17a', '#e0554a'];
  const pad = 40;
  final ptsN = series.isEmpty
      ? 0
      : series.map((s) => s.length).fold<int>(0, math.max);
  if (ptsN < 1) return '';
  final flat = [
    for (final s in series)
      for (final v in s)
        if (v != null) v
  ];
  if (flat.isEmpty) return '';
  var vmin = flat.reduce(math.min), vmax = flat.reduce(math.max);
  if (vmax - vmin < 5) vmax = vmin + 5;
  double sx(int i) => pad + (width - 2 * pad) * (i / math.max(1, ptsN - 1));
  double sy(double v) =>
      height - pad - (height - 2 * pad) * ((v - vmin) / (vmax - vmin));

  final p = StringBuffer(
      '<svg viewBox="0 0 $width $height" xmlns="http://www.w3.org/2000/svg" '
      'style="background:#11141a;border:1px solid #2a2f3a;border-radius:8px">');
  for (final frac in [0.0, 0.5, 1.0]) {
    final v = vmin + (vmax - vmin) * frac;
    final y = sy(v);
    p.write('<line x1="$pad" y1="${y.toStringAsFixed(1)}" x2="${width - pad}" '
        'y2="${y.toStringAsFixed(1)}" stroke="#2a2f3a" stroke-width="1"/>');
    p.write('<text x="6" y="${(y + 4).toStringAsFixed(1)}" fill="#8b93a4" '
        'font-size="11">${v.toStringAsFixed(0)}°C</text>');
  }
  for (var k = 0; k < series.length; k++) {
    final pts = [
      for (var i = 0; i < series[k].length; i++)
        if (series[k][i] != null)
          '${sx(i).toStringAsFixed(1)},${sy(series[k][i]!).toStringAsFixed(1)}'
    ].join(' ');
    if (pts.isNotEmpty) {
      p.write('<polyline points="$pts" fill="none" stroke="${colors[k]}" '
          'stroke-width="2"/>');
    }
  }
  for (var k = 0; k < labels.length; k++) {
    final x = pad + k * 70;
    p.write('<rect x="$x" y="10" width="10" height="10" fill="${colors[k]}"/>');
    p.write('<text x="${x + 14}" y="20" fill="#e6e9ef" font-size="12">'
        '${labels[k]}</text>');
  }
  p.write('<text x="${width - pad}" y="${height - 8}" fill="#8b93a4" '
      'font-size="11" text-anchor="end">kolejne okrążenia →</text>');
  p.write('</svg>');
  return p.toString();
}

int _mostCommon(List<int> xs) {
  final counts = <int, int>{};
  for (final x in xs) {
    counts[x] = (counts[x] ?? 0) + 1;
  }
  var best = xs.first, bestN = -1;
  counts.forEach((k, v) {
    if (v > bestN) {
      bestN = v;
      best = k;
    }
  });
  return best;
}

List<Map<String, dynamic>> _cornerRows(List<List<Map<String, dynamic>>> analyzed) {
  final byNo = <int, List<List<num>>>{};
  for (final pair in analyzed) {
    final an = pair[1];
    for (final c in (an['corners'] as List)) {
      final no = c['no'] as int;
      byNo.putIfAbsent(no, () => []).add([c['peak'] as num, c['tyre'] as int]);
    }
  }
  final rows = <Map<String, dynamic>>[];
  for (final no in byNo.keys.toList()..sort()) {
    final vals = byNo[no]!;
    final peaks = [for (final v in vals) v[0].toDouble()];
    final tyres = [for (final v in vals) v[1].toInt()];
    final dom = _mostCommon(tyres);
    final half = math.max(1, peaks.length ~/ 2);
    double mean(List<double> xs) => xs.reduce((a, b) => a + b) / xs.length;
    final trend = peaks.length >= 2
        ? mean(peaks.sublist(half)) - mean(peaks.sublist(0, half))
        : 0.0;
    rows.add({
      'no': no,
      'n': vals.length,
      'mean': mean(peaks),
      'max': peaks.reduce(math.max),
      'tyre': dom,
      'trend': trend,
    });
  }
  return rows;
}

/// Buduje samodzielny raport HTML (string) z listy nagrań.
String buildReportHtml(List<Map<String, dynamic>> laps) {
  final groups = <String, List<Map<String, dynamic>>>{};
  var skipped = 0;
  for (final lap in laps) {
    if (hasTyreData(lap)) {
      groups.putIfAbsent('${lap['track_key'] ?? '?'}', () => []).add(lap);
    } else {
      skipped++;
    }
  }

  final body = StringBuffer();
  if (skipped > 0) {
    body.writeln('<p class="note">Pominięto $skipped starszych nagrań bez '
        'danych temperatur opon.</p>');
  }
  if (groups.isEmpty) {
    body.writeln('<p class="note">Brak nagrań z danymi opon. Nowe nagrania '
        'zawierają temperatury automatycznie.</p>');
  }

  for (final trackKey in groups.keys.toList()..sort()) {
    final glaps = [...groups[trackKey]!]..sort((a, b) {
        final s = '${a['session_id'] ?? ''}'.compareTo('${b['session_id'] ?? ''}');
        if (s != 0) return s;
        return ((a['lap_number'] ?? 0) as num)
            .compareTo((b['lap_number'] ?? 0) as num);
      });
    final analyzed = <List<Map<String, dynamic>>>[];
    for (final lap in glaps) {
      final an = _analyzeLap(lap);
      if (an != null) analyzed.add([lap, an]);
    }
    if (analyzed.isEmpty) continue;
    final length = (glaps.first['fingerprint'] as Map?)?['length_m'] ?? '?';
    body.writeln('<h2>Tor ${_esc(trackKey)} <span class="sub">(~$length m, '
        'okrążeń: ${analyzed.length})</span></h2>');

    // Podział okrążeń na auta.
    final byCar = <String, List<List<Map<String, dynamic>>>>{};
    for (final pair in analyzed) {
      final lap = pair[0];
      final car = '${lap['car_name'] ?? lap['car_code'] ?? '?'}';
      byCar.putIfAbsent(car, () => []).add(pair);
    }

    if (byCar.length > 1) {
      final comp = <Map<String, dynamic>>[];
      byCar.forEach((car, items) {
        final peaks = [
          for (final p in items) (p[1]['max'] as List).cast<num>().reduce(math.max)
        ];
        final hotTyres = [
          for (final p in items)
            (p[1]['max'] as List)
                .cast<num>()
                .indexOf((p[1]['max'] as List).cast<num>().reduce(math.max))
        ];
        comp.add({
          'car': car,
          'n': items.length,
          'mean': peaks.reduce((a, b) => a + b) / peaks.length,
          'max': peaks.reduce(math.max),
          'tyre': _mostCommon(hotTyres),
        });
      });
      comp.sort((a, b) => (b['mean'] as num).compareTo(a['mean'] as num));
      body.writeln('<h3>Porównanie aut — które najmocniej przegrzewa opony</h3>');
      body.writeln('<table><tr><th>Auto</th><th>Okrążenia</th><th>Śr. szczyt</th>'
          '<th>Max</th><th>Najgorętsza opona</th></tr>');
      for (var i = 0; i < comp.length; i++) {
        final r = comp[i];
        final mark = i == 0 ? ' class="hot"' : '';
        body.writeln('<tr$mark><td>${_esc(r['car'])}</td><td>${r['n']}</td>'
            '<td>${(r['mean'] as num).toStringAsFixed(0)}°C</td>'
            '<td>${(r['max'] as num).toStringAsFixed(0)}°C</td>'
            '<td>${_tyresPl[r['tyre'] as int]}</td></tr>');
      }
      body.writeln('</table>');
      body.writeln('<p class="note">Najmocniej grzeje opony: '
          '${_esc(comp.first['car'])} (średnio '
          '${(comp.first['mean'] as num).toStringAsFixed(0)}°C na okrążenie).</p>');
    }

    for (final car in byCar.keys.toList()..sort()) {
      final items = byCar[car]!;
      body.writeln('<h3>${_esc(car)} <span class="sub">(${items.length} okr.)'
          '</span></h3>');
      body.writeln('<table><tr><th>Sesja</th><th>Okr.</th><th>Czas</th>'
          '${[for (final t in _tyres) '<th>$t śr. (max)</th>'].join()}</tr>');
      for (final pair in items) {
        final lap = pair[0], an = pair[1];
        final cells = [
          for (var k = 0; k < 4; k++)
            '<td>${(an['avg'][k] as num).toStringAsFixed(0)} '
                '(${(an['max'][k] as num).toStringAsFixed(0)})</td>'
        ].join();
        body.writeln('<tr><td>${_esc(lap['session_id'] ?? '?')}</td>'
            '<td>${lap['lap_number'] ?? '?'}</td>'
            '<td>${_esc(lap['lap_time'] ?? '?')}</td>$cells</tr>');
      }
      body.writeln('</table>');

      final series = [
        for (var k = 0; k < 4; k++)
          [for (final p in items) (p[1]['max'][k] as num).toDouble() as double?]
      ];
      body.writeln(_svgChart(series, _tyres));

      final rows = _cornerRows(items);
      if (rows.isNotEmpty) {
        body.writeln('<h4>Zakręty (szczytowe temperatury)</h4>');
        body.writeln('<table><tr><th>Zakręt</th><th>Przejazdy</th>'
            '<th>Śr. szczyt</th><th>Max</th><th>Najgorętsza opona</th>'
            '<th>Trend w sesji</th></tr>');
        final hottest =
            rows.reduce((a, b) => (b['mean'] as num) > (a['mean'] as num) ? b : a);
        for (final r in rows) {
          final mark = identical(r, hottest) ? ' class="hot"' : '';
          final trend = r['trend'] as num;
          final arrow = trend > 1 ? '↗ +' : (trend < -1 ? '↘ ' : '→ +');
          body.writeln('<tr$mark><td>${r['no']}</td><td>${r['n']}</td>'
              '<td>${(r['mean'] as num).toStringAsFixed(0)}°C</td>'
              '<td>${(r['max'] as num).toStringAsFixed(0)}°C</td>'
              '<td>${_tyresPl[r['tyre'] as int]}</td>'
              '<td>$arrow${trend.toStringAsFixed(1)}°C</td></tr>');
        }
        body.writeln('</table>');
        body.writeln('<p class="note">Najmocniej grzeje opony zakręt '
            '${hottest['no']} (${_tyresPl[hottest['tyre'] as int]}, średnio '
            '${(hottest['mean'] as num).toStringAsFixed(0)}°C).</p>');
      }
    }
  }

  return _page.replaceFirst('<!--BODY-->', body.toString());
}

const String _page = '''<!DOCTYPE html>
<html lang="pl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Raport temperatur opon - GT7</title>
<style>
  :root { color-scheme: dark; }
  body { margin: 0; padding: 20px; font-family: "Segoe UI", Roboto, system-ui, sans-serif;
         background: #14171c; color: #e6e9ef; max-width: 960px; margin: 0 auto; }
  h1 { font-size: 20px; } h2 { font-size: 17px; margin-top: 28px; }
  h3 { font-size: 14px; margin-top: 18px; }
  h4 { font-size: 13px; margin: 14px 0 4px; color: #c7cdd9; }
  .sub { color: #8b93a4; font-weight: 400; font-size: 13px; }
  .note { color: #8b93a4; font-size: 13px; }
  table { border-collapse: collapse; width: 100%; margin: 10px 0; font-size: 13px; }
  th, td { border: 1px solid #2a2f3a; padding: 6px 9px; text-align: left;
           font-variant-numeric: tabular-nums; }
  th { background: #1b1f27; color: #8b93a4; font-weight: 600; }
  tr.hot td { background: #2a1c1c; }
  svg { width: 100%; height: auto; margin: 8px 0 4px; }
</style>
</head>
<body>
<h1>Raport temperatur opon</h1>
<p class="note">Wygenerowano z nagrań telemetrii GT7. Zakręty wykrywane
automatycznie z kształtu śladu (ta sama heurystyka co inżynier na żywo).</p>
<!--BODY-->
</body>
</html>
''';
