/// Zakładka "Podgląd" — KONFIGUROWALNY dashboard.
///
/// Tryb podglądu: żywy dashboard z aktywnego ekranu. Tryb edycji (handoff Część 2)
/// rozdzielony na dwa widoki: BIBLIOTEKĘ widgetów (pełny ekran, kategorie + żywe
/// miniatury) oraz CANVAS (siatka 12×8 + panel opcji zaznaczonego widgetu).
/// Układy zapisują się lokalnie ([DashboardStore]) per użytkownik.
library;

import 'package:flutter/material.dart';

import '../app_settings.dart';
import '../app_state.dart';
import '../dashboard/dash_presets.dart';
import '../dashboard/dash_skin.dart';
import '../dashboard/dash_widgets.dart';
import '../dashboard/dashboard_model.dart';
import '../dashboard/dashboard_store.dart';
import '../telemetry/gt7_packet.dart';
import 'theme.dart';

enum _EditView { catalog, canvas }

class PreviewTab extends StatefulWidget {
  const PreviewTab({super.key, required this.controller});

  final TelemetryController controller;

  @override
  State<PreviewTab> createState() => _PreviewTabState();
}

class _PreviewTabState extends State<PreviewTab> {
  final _store = DashboardStore();
  DashboardConfig? _cfg;
  bool _loading = true;

  bool _edit = false;
  _EditView _view = _EditView.canvas;
  int? _selectedId;

  // Stan przeciągania/skalowania (piksele, zatwierdzane na koniec gestu).
  int? _moveId;
  Offset _moveDelta = Offset.zero;
  int? _resizeId;
  Offset _resizeDelta = Offset.zero;

  String _t(String k) => AppSettings.instance.t(k);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cfg = await _store.load(widget.controller.uid);
    if (!mounted) return;
    _cfg = cfg;
    _sanitizeOverlaps(); // posprzątaj ewentualne stare nakładki
    setState(() => _loading = false);
  }

  /// Usuwa nakładki w zapisanych układach: nachodzący widget przesuwany jest na
  /// wolne miejsce, a gdy go brak — usuwany. Zapewnia spójny stan po wczytaniu.
  void _sanitizeOverlaps() {
    var changed = false;
    for (final screen in _cfg!.screens) {
      final placed = <DashWidget>[];
      bool hits(DashWidget w, int gx, int gy) {
        for (final o in placed) {
          if (gx < o.gx + o.gw &&
              gx + w.gw > o.gx &&
              gy < o.gy + o.gh &&
              gy + w.gh > o.gy) {
            return true;
          }
        }
        return false;
      }

      ({int x, int y})? freeFor(DashWidget w) {
        for (var y = 0; y <= kGridRows - w.gh; y++) {
          for (var x = 0; x <= kGridCols - w.gw; x++) {
            if (!hits(w, x, y)) return (x: x, y: y);
          }
        }
        return null;
      }

      final keep = <DashWidget>[];
      for (final w in screen.widgets) {
        if (!hits(w, w.gx, w.gy)) {
          placed.add(w);
          keep.add(w);
          continue;
        }
        final spot = freeFor(w);
        if (spot != null) {
          w.gx = spot.x;
          w.gy = spot.y;
          placed.add(w);
          keep.add(w);
          changed = true;
        } else {
          changed = true; // brak miejsca — pomijamy (usuwamy)
        }
      }
      if (keep.length != screen.widgets.length) {
        screen.widgets
          ..clear()
          ..addAll(keep);
      }
    }
    if (changed) _save();
  }

  void _save() {
    final cfg = _cfg;
    if (cfg != null) _store.save(widget.controller.uid, cfg);
  }

  DashScreen get _screen => _cfg!.screens[_cfg!.activeIndex];

  DashWidget? _selectedWidget() {
    if (_selectedId == null) return null;
    for (final w in _screen.widgets) {
      if (w.id == _selectedId) return w;
    }
    return null;
  }

  // --- Ekrany ---

  void _switchScreen(int i) {
    setState(() {
      _cfg!.activeIndex = i;
      _selectedId = null;
    });
    _save();
  }

  Future<void> _addScreen() async {
    final name = await _askText(_t('dash.newScreen'), _t('dash.screenName'));
    if (name == null) return;
    setState(() {
      _cfg!.screens.add(DashScreen(name: name, widgets: []));
      _cfg!.activeIndex = _cfg!.screens.length - 1;
      _selectedId = null;
    });
    _save();
  }

  Future<void> _renameScreen() async {
    final name =
        await _askText(_t('dash.rename'), _t('dash.screenName'), _screen.name);
    if (name == null) return;
    setState(() => _screen.name = name);
    _save();
  }

  Future<void> _deleteScreen() async {
    if (_cfg!.screens.length <= 1) {
      _toast(_t('dash.atLeastOne'));
      return;
    }
    final ok = await _confirm('${_t('dash.deleteScreenQ')} „${_screen.name}"?');
    if (!ok) return;
    setState(() {
      _cfg!.screens.removeAt(_cfg!.activeIndex);
      if (_cfg!.activeIndex >= _cfg!.screens.length) {
        _cfg!.activeIndex = _cfg!.screens.length - 1;
      }
      _selectedId = null;
    });
    _save();
  }

  // --- Kolizje ---

  bool _overlaps(int gx, int gy, int gw, int gh, int excludeId) {
    for (final o in _screen.widgets) {
      if (o.id == excludeId) continue;
      if (gx < o.gx + o.gw &&
          gx + gw > o.gx &&
          gy < o.gy + o.gh &&
          gy + gh > o.gy) {
        return true;
      }
    }
    return false;
  }

  ({int x, int y})? _findFree(int gw, int gh, int excludeId, int prefX, int prefY) {
    ({int x, int y})? best;
    var bestD = 1 << 30;
    for (var y = 0; y <= kGridRows - gh; y++) {
      for (var x = 0; x <= kGridCols - gw; x++) {
        if (_overlaps(x, y, gw, gh, excludeId)) continue;
        final d = (x - prefX).abs() + (y - prefY).abs();
        if (d < bestD) {
          bestD = d;
          best = (x: x, y: y);
        }
      }
    }
    return best;
  }

  // --- Widgety ---

  /// Dodaje widget danego typu, zaznacza go i wraca na canvas. Gdy nie ma wolnego
  /// miejsca — NIE dodaje (żeby nigdy nie powstał nałożony widget) i informuje.
  void _addType(DashWidgetType type) {
    final def = dashTypeDefaultSize(type);
    final min = dashTypeMinSize(type);
    var gw = def.w.clamp(1, kGridCols).toInt();
    var gh = def.h.clamp(1, kGridRows).toInt();
    var spot = _findFree(gw, gh, -1, 0, 0);
    if (spot == null) {
      // Spróbuj zmieścić w minimalnym rozmiarze.
      gw = min.w;
      gh = min.h;
      spot = _findFree(gw, gh, -1, 0, 0);
    }
    if (spot == null) {
      setState(() => _view = _EditView.canvas);
      _toast(_t('dash.noSpace'));
      return;
    }
    final s = spot;
    final id = _cfg!.nextWidgetId();
    setState(() {
      _screen.widgets
          .add(DashWidget(id: id, type: type, gx: s.x, gy: s.y, gw: gw, gh: gh));
      _selectedId = id;
      _view = _EditView.canvas;
    });
    _save();
  }

  void _removeWidget(int id) {
    setState(() {
      _screen.widgets.removeWhere((w) => w.id == id);
      if (_selectedId == id) _selectedId = null;
    });
    _save();
  }

  void _resizeBy(DashWidget w, int dw, int dh) {
    final min = dashTypeMinSize(w.type);
    final nw = (w.gw + dw).clamp(min.w, kGridCols - w.gx).toInt();
    final nh = (w.gh + dh).clamp(min.h, kGridRows - w.gy).toInt();
    if (nw == w.gw && nh == w.gh) return;
    if (!_overlaps(w.gx, w.gy, nw, nh, w.id)) {
      setState(() {
        w.gw = nw;
        w.gh = nh;
      });
      _save();
    } else {
      _flashBlocked(w.id); // brak miejsca na powiększenie
    }
  }

  /// Czerwony błysk obrysu, gdy operacji nie da się wykonać (brak miejsca).
  int? _blockedId;
  void _flashBlocked(int id) {
    setState(() => _blockedId = id);
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted && _blockedId == id) setState(() => _blockedId = null);
    });
  }

  void _setLaps(DashWidget w, int d) {
    final n = (w.optInt('targetLaps', 5) + d).clamp(1, 99).toInt();
    setState(() => w.options['targetLaps'] = n);
    _save();
  }

  // --- Gesty przeciągania / skalowania ---

  void _onMoveEnd(DashWidget w, double cellW, double cellH) {
    final nx = ((w.gx * cellW + _moveDelta.dx) / cellW)
        .round()
        .clamp(0, kGridCols - w.gw)
        .toInt();
    final ny = ((w.gy * cellH + _moveDelta.dy) / cellH)
        .round()
        .clamp(0, kGridRows - w.gh)
        .toInt();
    var blocked = false;
    if (!_overlaps(nx, ny, w.gw, w.gh, w.id)) {
      w.gx = nx;
      w.gy = ny;
    } else {
      final free = _findFree(w.gw, w.gh, w.id, nx, ny);
      if (free != null) {
        w.gx = free.x;
        w.gy = free.y;
      } else {
        blocked = true; // nie ma gdzie odłożyć — wraca na miejsce
      }
    }
    setState(() {
      _moveId = null;
      _moveDelta = Offset.zero;
    });
    _save();
    if (blocked) _flashBlocked(w.id);
  }

  void _onResizeEnd(DashWidget w, double cellW, double cellH) {
    final min = dashTypeMinSize(w.type);
    var nw = ((w.gw * cellW + _resizeDelta.dx) / cellW)
        .round()
        .clamp(min.w, kGridCols - w.gx)
        .toInt();
    var nh = ((w.gh * cellH + _resizeDelta.dy) / cellH)
        .round()
        .clamp(min.h, kGridRows - w.gy)
        .toInt();
    while ((nw > w.gw || nh > w.gh) && _overlaps(w.gx, w.gy, nw, nh, w.id)) {
      if (nw > w.gw && (nw - w.gw) >= (nh - w.gh)) {
        nw--;
      } else if (nh > w.gh) {
        nh--;
      } else {
        nw--;
      }
    }
    setState(() {
      if (!_overlaps(w.gx, w.gy, nw, nh, w.id)) {
        w.gw = nw;
        w.gh = nh;
      }
      _resizeId = null;
      _resizeDelta = Offset.zero;
    });
    _save();
  }

  // --- Dialogi ---

  Future<String?> _askText(String title, String label, [String initial = '']) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
              labelText: label, border: const OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(_t('common.cancel'))),
          FilledButton(
            onPressed: () {
              final s = ctrl.text.trim();
              Navigator.pop(ctx, s.isEmpty ? null : s);
            },
            child: Text(_t('common.ok')),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirm(String msg) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.panel,
        content: Text(msg, style: const TextStyle(color: AppColors.text)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(_t('common.cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_t('common.delete')),
          ),
        ],
      ),
    );
    return r ?? false;
  }

  void _toast(String s) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  // --- Wybór skórki ---

  void _openSkinPicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.panel,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_t('dash.skinPicker'),
                    style: const TextStyle(
                        color: AppColors.text, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final sk in kDashSkins)
                      _skinTile(sk, () => setSheet(() {})),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _skinTile(DashSkin sk, VoidCallback onPicked) {
    final selected = AppSettings.instance.dashSkinId == sk.id;
    return InkWell(
      onTap: () {
        AppSettings.instance.setDashSkin(sk.id);
        setState(() {}); // odśwież dashboard pod spodem
        onPicked(); // odśwież zaznaczenie w arkuszu
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 150,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF161A21),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selected ? AppColors.accent : AppColors.stroke,
              width: selected ? 2 : 1),
          boxShadow: selected
              ? [
                  BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.4),
                      blurRadius: 10)
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              _skinDot(sk.speed),
              _skinDot(sk.rpm),
              _skinDot(sk.good),
            ]),
            const SizedBox(height: 8),
            Text(sk.name,
                style: const TextStyle(
                    color: AppColors.text, fontWeight: FontWeight.w700)),
            Text(sk.tag,
                style: const TextStyle(color: AppColors.muted, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _skinDot(Color c) => Container(
        margin: const EdgeInsets.only(right: 5),
        width: 14,
        height: 14,
        decoration: BoxDecoration(shape: BoxShape.circle, color: c),
      );

  // --- Presety (gotowe układy) ---

  void _openPresetPicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.panel,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_t('dash.presetPicker'),
                  style: const TextStyle(
                      color: AppColors.text, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              for (final pr in kDashPresets)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.grid_view, color: AppColors.muted),
                  title: Text(_t(pr.nameKey),
                      style: const TextStyle(color: AppColors.text)),
                  subtitle: Text('${pr.widgets.length} widgetów',
                      style: const TextStyle(
                          color: AppColors.muted, fontSize: 11)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _addPreset(pr);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Dodaje preset jako NOWY ekran (z świeżymi id), przełącza się na niego.
  void _addPreset(DashPreset preset) {
    var nextId = _cfg!.nextWidgetId();
    final screen = DashScreen(name: _t(preset.nameKey), widgets: []);
    for (final pw in preset.widgets) {
      screen.widgets.add(DashWidget(
        id: nextId++,
        type: pw.type,
        gx: pw.gx,
        gy: pw.gy,
        gw: pw.gw,
        gh: pw.gh,
        options: pw.options == null ? {} : Map<String, dynamic>.of(pw.options!),
      ));
    }
    setState(() {
      _cfg!.screens.add(screen);
      _cfg!.activeIndex = _cfg!.screens.length - 1;
      _selectedId = null;
    });
    _save();
  }

  // =====================================================================
  //  BUILD
  // =====================================================================

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_loading || _cfg == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (!_edit) {
      body = Column(children: [
        _viewTopBar(),
        Expanded(
          child: ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) =>
                _grid(widget.controller.last ?? Gt7Packet(), editing: false),
          ),
        ),
      ]);
    } else if (_view == _EditView.catalog) {
      body = _catalog();
    } else {
      body = _canvas();
    }
    // Dashboard ma własny motyw (ciemny chrome) + tło ze skórki.
    return Theme(
      data: buildDarkTheme(),
      child: _screenBg(body),
    );
  }

  /// Tło ekranu wg skórki: gradient albo tekstura włókna węglowego.
  Widget _screenBg(Widget child) {
    final s = AppSettings.instance.dashSkin;
    if (s.carbon) {
      return Stack(
        fit: StackFit.expand,
        children: [
          const Positioned.fill(
              child: CustomPaint(painter: DashCarbonPainter(cell: 16))),
          child,
        ],
      );
    }
    return DecoratedBox(
        decoration: BoxDecoration(gradient: s.screen), child: child);
  }

  // --- Tryb podglądu ---

  Widget _viewTopBar() {
    return Container(
      height: 44,
      padding: const EdgeInsets.only(left: 46, right: 4),
      child: Row(
        children: [
          Expanded(child: _screenChips()),
          IconButton(
            tooltip: _t('dash.skin'),
            icon: const Icon(Icons.palette_outlined, color: AppColors.muted),
            onPressed: _openSkinPicker,
          ),
          IconButton(
            tooltip: _t('dash.tipEdit'),
            icon: const Icon(Icons.edit, color: AppColors.muted),
            onPressed: () => setState(() {
              _edit = true;
              _view = _EditView.canvas;
            }),
          ),
        ],
      ),
    );
  }

  Widget _screenChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < _cfg!.screens.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: ChoiceChip(
                label: Text(_cfg!.screens[i].name),
                selected: i == _cfg!.activeIndex,
                onSelected: (_) => _switchScreen(i),
              ),
            ),
          if (_edit)
            IconButton(
              tooltip: _t('dash.newScreen'),
              icon: const Icon(Icons.add, color: AppColors.muted),
              onPressed: _addScreen,
            ),
        ],
      ),
    );
  }

  // --- CANVAS ---

  Widget _canvas() {
    final sel = _selectedWidget();
    return Column(
      children: [
        _canvasTopBar(),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: ListenableBuilder(
                  listenable: widget.controller,
                  builder: (context, _) =>
                      _grid(widget.controller.last ?? Gt7Packet(), editing: true),
                ),
              ),
              if (sel != null) _optionsPanel(sel),
            ],
          ),
        ),
      ],
    );
  }

  Widget _canvasTopBar() {
    return Container(
      height: 48,
      padding: const EdgeInsets.only(left: 46, right: 6),
      child: Row(
        children: [
          Expanded(child: _screenChips()),
          IconButton(
            tooltip: _t('dash.skin'),
            icon: const Icon(Icons.palette_outlined, color: AppColors.muted),
            onPressed: _openSkinPicker,
          ),
          IconButton(
            tooltip: _t('dash.presets'),
            icon: const Icon(Icons.dashboard_customize_outlined,
                color: AppColors.muted),
            onPressed: _openPresetPicker,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: AppColors.muted),
            onSelected: (v) {
              if (v == 'rename') _renameScreen();
              if (v == 'delete') _deleteScreen();
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'rename', child: Text(_t('dash.renameScreen'))),
              PopupMenuItem(value: 'delete', child: Text(_t('dash.deleteScreen'))),
            ],
          ),
          const SizedBox(width: 4),
          FilledButton.icon(
            onPressed: () => setState(() => _view = _EditView.catalog),
            icon: const Icon(Icons.add, size: 18),
            label: Text(_t('dash.addWidget')),
          ),
          const SizedBox(width: 4),
          TextButton(
            onPressed: () => setState(() {
              _edit = false;
              _selectedId = null;
            }),
            child: Text(_t('common.done')),
          ),
        ],
      ),
    );
  }

  Widget _grid(Gt7Packet p, {required bool editing}) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: LayoutBuilder(
        builder: (context, cons) {
          final cellW = cons.maxWidth / kGridCols;
          final cellH = cons.maxHeight / kGridRows;
          final children = <Widget>[];

          if (editing) {
            // Tło z siatką + odznaczanie po tapnięciu pustego miejsca.
            children.add(Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _selectedId = null),
                child: CustomPaint(painter: _GridPainter(cellW, cellH)),
              ),
            ));
          }

          for (final w in _screen.widgets) {
            var left = w.gx * cellW;
            var top = w.gy * cellH;
            var width = w.gw * cellW;
            var height = w.gh * cellH;
            if (editing && _moveId == w.id) {
              left += _moveDelta.dx;
              top += _moveDelta.dy;
            }
            if (editing && _resizeId == w.id) {
              width += _resizeDelta.dx;
              height += _resizeDelta.dy;
            }
            children.add(Positioned(
              left: left,
              top: top,
              width: width.clamp(24.0, cons.maxWidth).toDouble(),
              height: height.clamp(24.0, cons.maxHeight).toDouble(),
              child: editing ? _canvasCell(w, cellW, cellH, p) : _live(w, p),
            ));
          }

          if (_screen.widgets.isEmpty) {
            children.add(Positioned.fill(
              child: Center(
                child: Text(_t('dash.emptyScreen'),
                    style: const TextStyle(color: AppColors.muted)),
              ),
            ));
          }

          return Stack(children: children);
        },
      ),
    );
  }

  Widget _live(DashWidget w, Gt7Packet p) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: buildDashWidget(w, p, widget.controller),
    );
  }

  Widget _canvasCell(DashWidget w, double cellW, double cellH, Gt7Packet p) {
    final selected = w.id == _selectedId;
    final blocked = w.id == _blockedId;
    final borderColor = blocked
        ? AppColors.danger
        : (selected ? AppColors.accent : AppColors.tileBorder);
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: () => setState(() => _selectedId = w.id),
            onPanStart: (_) => setState(() {
              _selectedId = w.id;
              _moveId = w.id;
              _moveDelta = Offset.zero;
            }),
            onPanUpdate: (d) => setState(() => _moveDelta += d.delta),
            onPanEnd: (_) => _onMoveEnd(w, cellW, cellH),
            child: Container(
              margin: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                border: Border.all(
                    color: borderColor,
                    width: (selected || blocked) ? 2 : 1),
                borderRadius: BorderRadius.circular(11),
              ),
              child: IgnorePointer(
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: buildDashWidget(w, p, widget.controller),
                ),
              ),
            ),
          ),
        ),
        // Plakietka typu (lewy górny róg).
        Positioned(
          left: 4,
          top: 4,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(dashTypeLabel(w.type),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted2, fontSize: 9)),
            ),
          ),
        ),
        // Uchwyt skalowania — tylko dla zaznaczonego.
        if (selected)
          Positioned(
            right: 0,
            bottom: 0,
            child: GestureDetector(
              onPanStart: (_) => setState(() {
                _resizeId = w.id;
                _resizeDelta = Offset.zero;
              }),
              onPanUpdate: (d) => setState(() => _resizeDelta += d.delta),
              onPanEnd: (_) => _onResizeEnd(w, cellW, cellH),
              child: Container(
                width: 26,
                height: 26,
                decoration: const BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(8),
                      bottomRight: Radius.circular(10)),
                ),
                child: const Icon(Icons.open_in_full,
                    size: 15, color: Colors.white),
              ),
            ),
          ),
      ],
    );
  }

  // --- Panel opcji zaznaczonego widgetu ---

  Widget _optionsPanel(DashWidget w) {
    final variants = dashTypeVariants(w.type);
    return Container(
      width: 250,
      color: AppColors.panel,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(dashCategoryColor(w.type))),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(dashTypeLabel(w.type),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppColors.text, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const Divider(color: AppColors.stroke, height: 20),
          if (variants.isNotEmpty) ...[
            _panelLabel(_t('dash.appearance')),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final v in variants)
                  ChoiceChip(
                    label: Text(dashVariantLabel(v)),
                    selected: w.optStr('variant', variants.first) == v,
                    onSelected: (_) {
                      setState(() => w.options['variant'] = v);
                      _save();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          if (dashTypeHasShowValue(w.type))
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(_t('dash.showValue'),
                  style: const TextStyle(color: AppColors.text)),
              value: w.optBool('showValue', w.type == DashWidgetType.tyres),
              onChanged: (v) {
                setState(() => w.options['showValue'] = v);
                _save();
              },
            ),
          if (w.type == DashWidgetType.fuelTarget)
            _stepperRow(_t('dash.lapsCountLabel'), '${w.optInt('targetLaps', 5)}',
                () => _setLaps(w, -1), () => _setLaps(w, 1)),
          const Divider(color: AppColors.stroke, height: 20),
          _panelLabel(_t('dash.size')),
          _stepperRow(_t('dash.width'), '${w.gw}', () => _resizeBy(w, -1, 0),
              () => _resizeBy(w, 1, 0)),
          _stepperRow(_t('dash.height'), '${w.gh}', () => _resizeBy(w, 0, -1),
              () => _resizeBy(w, 0, 1)),
          const SizedBox(height: 10),
          Text(_t('dash.dragHint'),
              style: const TextStyle(color: AppColors.muted, fontSize: 11)),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => _removeWidget(w.id),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: Text(_t('dash.deleteWidget')),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.danger,
              side: BorderSide(color: AppColors.danger.withValues(alpha: 0.4)),
              backgroundColor: AppColors.danger.withValues(alpha: 0.1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _panelLabel(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(s.toUpperCase(),
            style: const TextStyle(
                color: AppColors.muted, fontSize: 11, letterSpacing: 1.2)),
      );

  Widget _stepperRow(
      String label, String value, VoidCallback minus, VoidCallback plus) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(color: AppColors.muted2, fontSize: 13)),
          ),
          _square(Icons.remove, minus),
          SizedBox(
            width: 34,
            child: Text(value,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.text, fontWeight: FontWeight.w700)),
          ),
          _square(Icons.add, plus),
        ],
      ),
    );
  }

  Widget _square(IconData icon, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: const Color(0xFF1B212A),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.stroke),
          ),
          child: Icon(icon, size: 16, color: AppColors.text),
        ),
      );

  // --- BIBLIOTEKA (catalog) ---

  Widget _catalog() {
    return Column(
      children: [
        _catalogHeader(),
        Expanded(
          child: LayoutBuilder(
            builder: (context, cons) {
              final cols = cons.maxWidth > 760
                  ? 5
                  : (cons.maxWidth > 560 ? 4 : 3);
              final cardW = (cons.maxWidth - 24 - (cols - 1) * 8) / cols;
              return ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  for (final cat in dashCategories) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 8),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(cat.color)),
                          ),
                          const SizedBox(width: 8),
                          Text(_t(cat.titleKey).toUpperCase(),
                              style: const TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 11,
                                  letterSpacing: 1.2,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final ty in cat.types)
                          SizedBox(width: cardW, child: _card(ty)),
                      ],
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _catalogHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(46, 8, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_t('dash.libraryTitle'),
                    style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                Text(_t('dash.librarySubtitle'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppColors.muted, fontSize: 11)),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () => setState(() => _view = _EditView.canvas),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: Text(_t('dash.backToScreen')),
          ),
        ],
      ),
    );
  }

  Widget _card(DashWidgetType type) {
    final variants = dashTypeVariants(type);
    final size = dashTypeDefaultSize(type);
    final sample = DashWidget(
        id: 0, type: type, gx: 0, gy: 0, gw: size.w, gh: size.h);
    return InkWell(
      onTap: () => _addType(type),
      borderRadius: BorderRadius.circular(11),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.panel,
          border: Border.all(color: AppColors.stroke),
          borderRadius: BorderRadius.circular(11),
        ),
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: Container(
                height: 84,
                decoration: BoxDecoration(
                    gradient: AppSettings.instance.dashSkin.screen),
                child: IgnorePointer(
                  child: buildDashWidget(
                      sample, sampleDashPacket(), widget.controller),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(dashCategoryColor(type))),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(dashTypeLabel(type),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.text, fontSize: 12)),
                ),
                Text(
                  variants.length > 1
                      ? '${variants.length} ${_t('dash.variantsBadge')}'
                      : '+',
                  style: const TextStyle(color: AppColors.muted, fontSize: 10),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Subtelne linie siatki widoczne tylko w trybie edycji.
class _GridPainter extends CustomPainter {
  _GridPainter(this.cellW, this.cellH);
  final double cellW;
  final double cellH;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.tileBorder.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    for (var x = 0; x <= kGridCols; x++) {
      canvas.drawLine(
          Offset(x * cellW, 0), Offset(x * cellW, size.height), paint);
    }
    for (var y = 0; y <= kGridRows; y++) {
      canvas.drawLine(
          Offset(0, y * cellH), Offset(size.width, y * cellH), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.cellW != cellW || old.cellH != cellH;
}
