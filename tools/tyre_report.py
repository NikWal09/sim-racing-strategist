#!/usr/bin/env python3
"""Raport temperatur opon z nagran telemetrii (analiza po sesji).

Czyta nagrania okrazen (pliki JSON recordera z kanalami tyre_fl..tyre_rr),
wykrywa zakrety OFFLINE z ksztaltu sladu (zmiana kierunku jazdy, ta sama
heurystyka co CornerTracker na zywo) i buduje samodzielny raport HTML:

  * tabela okrazen per tor: srednie i maksymalne temperatury kazdej opony,
  * wykres trendu temperatur (max per opona) okrazenie po okrazeniu,
  * tabela zakretow: ktory zakret grzeje opony najmocniej, ktora opone
    i jaki jest trend miedzy poczatkiem a koncem sesji.

Starsze nagrania (bez kanalow opon) sa pomijane z adnotacja w raporcie.

Uzycie:
    python tools/tyre_report.py
    python tools/tyre_report.py --recordings recordings --out recordings/raport_opon.html
"""

from __future__ import annotations

import argparse
import html
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from tools.telemetry_viewer import load_laps  # noqa: E402

TYRES = ("FL", "FR", "RL", "RR")
TYRES_PL = ("lewa przednia", "prawa przednia", "lewa tylna", "prawa tylna")
TYRE_CHANNELS = ("tyre_fl", "tyre_fr", "tyre_rl", "tyre_rr")

# Progi detekcji zakretow - takie same jak w CornerTracker (na zywo).
ENTER_YAW_DPS = 14.0
EXIT_YAW_DPS = 7.0
MIN_SPEED_KPH = 30.0
MIN_ENTER_S = 0.20
MIN_EXIT_S = 0.45


def _chan_idx(lap: dict) -> dict[str, int]:
    return {name: i for i, name in enumerate(lap.get("channels") or [])}

def has_tyre_data(lap: dict) -> bool:
    idx = _chan_idx(lap)
    return all(c in idx for c in TYRE_CHANNELS)


def detect_corners(samples: list[list[float]], idx: dict[str, int]) -> list[tuple[int, int]]:
    """Segmenty zakretow [(start_i, end_i)] ze zmiany kierunku jazdy w x-z.

    Identyczna logika jak CornerTracker (histereza + minimalne czasy), tylko
    liczona offline z probek pozycji zamiast wektora predkosci.
    """
    it, ix, iz = idx["t"], idx["x"], idx["z"]
    iv = idx.get("speed_kph")
    corners: list[tuple[int, int]] = []
    heading: float | None = None
    in_corner = False
    enter_since: float | None = None
    exit_since: float | None = None
    start_i = 0

    for i in range(1, len(samples)):
        s0, s1 = samples[i - 1], samples[i]
        t0, t1 = s0[it], s1[it]
        dt = t1 - t0
        dx, dz = s1[ix] - s0[ix], s1[iz] - s0[iz]
        speed = s1[iv] if iv is not None else 999.0
        yaw_dps = 0.0
        if dt > 0 and (abs(dx) + abs(dz)) > 1e-3 and speed >= MIN_SPEED_KPH:
            h = math.atan2(dz, dx)
            if heading is not None:
                d = h - heading
                while d > math.pi:
                    d -= 2 * math.pi
                while d < -math.pi:
                    d += 2 * math.pi
                yaw_dps = abs(math.degrees(d) / dt)
            heading = h
        else:
            heading = None

        if not in_corner:
            if yaw_dps >= ENTER_YAW_DPS:
                if enter_since is None:
                    enter_since = t1
                    start_i = i
                if t1 - enter_since >= MIN_ENTER_S:
                    in_corner = True
                    exit_since = None
            else:
                enter_since = None
        else:
            if yaw_dps < EXIT_YAW_DPS:
                if exit_since is None:
                    exit_since = t1
                if t1 - exit_since >= MIN_EXIT_S:
                    corners.append((start_i, i))
                    in_corner = False
                    enter_since = None
                    exit_since = None
            else:
                exit_since = None

    if in_corner:
        corners.append((start_i, len(samples) - 1))
    return corners


def analyze_lap(lap: dict) -> dict | None:
    """Statystyki opon okrazenia: srednie/maksima per opona + szczyty per zakret.

    None, gdy nagranie nie ma kanalow temperatur opon (starszy format).
    """
    if not has_tyre_data(lap):
        return None
    idx = _chan_idx(lap)
    samples = lap["samples"]
    ti = [idx[c] for c in TYRE_CHANNELS]

    n = len(samples)
    avg = [sum(s[i] for s in samples) / n for i in ti]
    mx = [max(s[i] for s in samples) for i in ti]

    corners = []
    for no, (a, b) in enumerate(detect_corners(samples, idx), start=1):
        seg = samples[a:b + 1]
        peak, tyre = 0.0, 0
        for s in seg:
            for k, i in enumerate(ti):
                if s[i] > peak:
                    peak, tyre = s[i], k
        corners.append({"no": no, "peak": round(peak, 1), "tyre": tyre})

    return {
        "avg": [round(v, 1) for v in avg],
        "max": [round(v, 1) for v in mx],
        "corners": corners,
    }


def _svg_chart(series: list[list[float]], labels: list[str], width=860, height=260) -> str:
    """Prosty wykres liniowy SVG: jedna linia per opona, x = kolejne okrazenia."""
    colors = ("#4f8cff", "#f4a72a", "#5bd17a", "#e0554a")
    pad = 40
    pts_n = max(len(s) for s in series) if series else 0
    if pts_n < 1:
        return ""
    flat = [v for s in series for v in s if v is not None]
    if not flat:
        return ""
    vmin, vmax = min(flat), max(flat)
    if vmax - vmin < 5:
        vmax = vmin + 5
    def sx(i): return pad + (width - 2 * pad) * (i / max(1, pts_n - 1))
    def sy(v): return height - pad - (height - 2 * pad) * ((v - vmin) / (vmax - vmin))

    parts = [f'<svg viewBox="0 0 {width} {height}" xmlns="http://www.w3.org/2000/svg" '
             f'style="background:#11141a;border:1px solid #2a2f3a;border-radius:8px">']
    # Osie i opisy.
    for frac in (0.0, 0.5, 1.0):
        v = vmin + (vmax - vmin) * frac
        y = sy(v)
        parts.append(f'<line x1="{pad}" y1="{y:.1f}" x2="{width-pad}" y2="{y:.1f}" '
                     f'stroke="#2a2f3a" stroke-width="1"/>')
        parts.append(f'<text x="6" y="{y+4:.1f}" fill="#8b93a4" font-size="11">{v:.0f}&#176;C</text>')
    for k, s in enumerate(series):
        pts = " ".join(f"{sx(i):.1f},{sy(v):.1f}" for i, v in enumerate(s) if v is not None)
        if pts:
            parts.append(f'<polyline points="{pts}" fill="none" stroke="{colors[k]}" stroke-width="2"/>')
    # Legenda.
    for k, lab in enumerate(labels):
        x = pad + k * 70
        parts.append(f'<rect x="{x}" y="10" width="10" height="10" fill="{colors[k]}"/>')
        parts.append(f'<text x="{x+14}" y="20" fill="#e6e9ef" font-size="12">{lab}</text>')
    parts.append(f'<text x="{width-pad}" y="{height-8}" fill="#8b93a4" font-size="11" '
                 f'text-anchor="end">kolejne okr&#261;&#380;enia &#8594;</text>')
    parts.append("</svg>")
    return "".join(parts)


def _corner_rows(analyzed: list[tuple[dict, dict]]) -> list[dict]:
    """Agregacja zakretow w grupie toru: srednia/max szczytu, dominujaca opona, trend."""
    by_no: dict[int, list[tuple[float, int]]] = {}
    for _lap, an in analyzed:
        for c in an["corners"]:
            by_no.setdefault(c["no"], []).append((c["peak"], c["tyre"]))
    rows = []
    for no in sorted(by_no):
        vals = by_no[no]
        peaks = [p for p, _ in vals]
        tyres = [t for _, t in vals]
        dom = max(set(tyres), key=tyres.count)
        half = max(1, len(peaks) // 2)
        trend = (sum(peaks[half:]) / len(peaks[half:])) - (sum(peaks[:half]) / half) \
            if len(peaks) >= 2 else 0.0
        rows.append({
            "no": no, "n": len(vals),
            "mean": sum(peaks) / len(peaks), "max": max(peaks),
            "tyre": dom, "trend": trend,
        })
    return rows


def build_report_html(laps: list[dict]) -> str:
    """Buduje samodzielny raport HTML (string) z listy nagran."""
    groups: dict[str, list[dict]] = {}
    skipped = 0
    for lap in laps:
        if has_tyre_data(lap):
            groups.setdefault(lap.get("track_key", "?"), []).append(lap)
        else:
            skipped += 1

    body: list[str] = []
    if skipped:
        body.append(f'<p class="note">Pomini&#281;to {skipped} starszych nagra&#324; '
                    f'bez danych temperatur opon.</p>')
    if not groups:
        body.append('<p class="note">Brak nagra&#324; z danymi opon. Nowe nagrania '
                    '(po aktualizacji) zawieraj&#261; temperatury automatycznie.</p>')

    for track_key in sorted(groups):
        glaps = sorted(groups[track_key], key=lambda d: (d.get("session_id", ""),
                                                          d.get("lap_number", 0)))
        analyzed = [(lap, analyze_lap(lap)) for lap in glaps]
        analyzed = [(lap, an) for lap, an in analyzed if an]
        if not analyzed:
            continue
        length = (glaps[0].get("fingerprint") or {}).get("length_m", "?")
        body.append(f'<h2>Tor {html.escape(track_key)} '
                    f'<span class="sub">(~{length} m, okr&#261;&#380;e&#324;: {len(analyzed)})</span></h2>')

        # Podzial okrazen na AUTA - kazde auto dostaje wlasna sekcje i wykres,
        # zeby dalo sie porownac, ktory pojazd najmocniej przegrzewa opony.
        by_car: dict[str, list[tuple[dict, dict]]] = {}
        for lap, an in analyzed:
            car = str(lap.get("car_name") or lap.get("car_code", "?"))
            by_car.setdefault(car, []).append((lap, an))

        # Tabela porownawcza aut (sens, gdy na torze jezdzilo wiecej niz 1 auto).
        if len(by_car) > 1:
            comp = []
            for car, items in by_car.items():
                # Szczyt okrazenia = najgoretsza opona w tym kolku.
                peaks = [max(an["max"]) for _l, an in items]
                hot_tyres = [an["max"].index(max(an["max"])) for _l, an in items]
                dom = max(set(hot_tyres), key=hot_tyres.count)
                comp.append({"car": car, "n": len(items),
                             "mean": sum(peaks) / len(peaks),
                             "max": max(peaks), "tyre": dom})
            comp.sort(key=lambda r: r["mean"], reverse=True)
            body.append('<h3>Por&#243;wnanie aut &#8212; kt&#243;re najmocniej '
                        'przegrzewa opony</h3>')
            body.append('<table><tr><th>Auto</th><th>Okr&#261;&#380;enia</th>'
                        '<th>&#346;r. szczyt</th><th>Max</th>'
                        '<th>Najgor&#281;tsza opona</th></tr>')
            for i, r in enumerate(comp):
                mark = ' class="hot"' if i == 0 else ""
                body.append(
                    f'<tr{mark}><td>{html.escape(r["car"])}</td><td>{r["n"]}</td>'
                    f'<td>{r["mean"]:.0f}&#176;C</td><td>{r["max"]:.0f}&#176;C</td>'
                    f'<td>{TYRES_PL[r["tyre"]]}</td></tr>')
            body.append("</table>")
            body.append(f'<p class="note">Najmocniej grzeje opony: '
                        f'{html.escape(comp[0]["car"])} '
                        f'(&#347;rednio {comp[0]["mean"]:.0f}&#176;C na okr&#261;&#380;enie).</p>')

        # Sekcja per auto: tabela okrazen + wlasny wykres trendu + zakrety.
        for car in sorted(by_car):
            items = by_car[car]
            body.append(f'<h3>{html.escape(car)} '
                        f'<span class="sub">({len(items)} okr.)</span></h3>')

            body.append('<table><tr><th>Sesja</th><th>Okr.</th><th>Czas</th>'
                        + "".join(f"<th>{t} &#347;r. (max)</th>" for t in TYRES) + "</tr>")
            for lap, an in items:
                cells = "".join(f"<td>{an['avg'][k]:.0f} ({an['max'][k]:.0f})</td>"
                                for k in range(4))
                body.append(
                    f"<tr><td>{html.escape(str(lap.get('session_id', '?')))}</td>"
                    f"<td>{lap.get('lap_number', '?')}</td>"
                    f"<td>{html.escape(str(lap.get('lap_time', '?')))}</td>"
                    f"{cells}</tr>")
            body.append("</table>")

            # Wykres trendu tego auta (max temp per opona, okrazenie po okrazeniu).
            series = [[an["max"][k] for _lap, an in items] for k in range(4)]
            body.append(_svg_chart(series, list(TYRES)))

            # Tabela zakretow tego auta (punkty hamowania roznia sie miedzy autami,
            # wiec numeracja zakretow nie miesza sie miedzy pojazdami).
            rows = _corner_rows(items)
            if rows:
                body.append('<h4>Zakr&#281;ty (szczytowe temperatury)</h4>')
                body.append('<table><tr><th>Zakr&#281;t</th><th>Przejazdy</th>'
                            '<th>&#346;r. szczyt</th><th>Max</th>'
                            '<th>Najgor&#281;tsza opona</th><th>Trend w sesji</th></tr>')
                hottest = max(rows, key=lambda r: r["mean"])
                for r in rows:
                    mark = ' class="hot"' if r is hottest else ""
                    arrow = ("&#8599; +" if r["trend"] > 1 else
                             ("&#8600; " if r["trend"] < -1 else "&#8594; +"))
                    body.append(
                        f'<tr{mark}><td>{r["no"]}</td><td>{r["n"]}</td>'
                        f'<td>{r["mean"]:.0f}&#176;C</td><td>{r["max"]:.0f}&#176;C</td>'
                        f'<td>{TYRES_PL[r["tyre"]]}</td>'
                        f'<td>{arrow}{r["trend"]:.1f}&#176;C</td></tr>')
                body.append("</table>")
                body.append(f'<p class="note">Najmocniej grzeje opony zakr&#281;t '
                            f'{hottest["no"]} ({TYRES_PL[hottest["tyre"]]}, '
                            f'&#347;rednio {hottest["mean"]:.0f}&#176;C).</p>')

    return _PAGE.replace("<!--BODY-->", "\n".join(body))


_PAGE = """<!DOCTYPE html>
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
<p class="note">Wygenerowano z nagra&#324; telemetrii GT7. Zakr&#281;ty wykrywane
automatycznie z kszta&#322;tu &#347;ladu (ta sama heurystyka co inżynier na żywo).</p>
<!--BODY-->
</body>
</html>
"""


def main() -> int:
    ap = argparse.ArgumentParser(description="Raport temperatur opon z nagran GT7")
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ap.add_argument("--recordings", default=os.path.join(root, "recordings"))
    ap.add_argument("--out", default=None)
    args = ap.parse_args()

    laps = load_laps(args.recordings)
    if not laps:
        print(f"Brak nagran w {args.recordings}")
        return 1
    out = args.out or os.path.join(args.recordings, "raport_opon.html")
    with open(out, "w", encoding="utf-8") as f:
        f.write(build_report_html(laps))
    print(f"Zapisano raport: {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
