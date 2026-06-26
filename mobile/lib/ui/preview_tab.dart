/// Zakładka "Podgląd" — KONFIGUROWALNY dashboard.
///
/// Użytkownik układa własne ekrany na siatce 12×8: dodaje widgety z palety,
/// przeciąga je i skaluje (tryb edycji), tworzy wiele ekranów i przełącza je.
/// Układy zapisują się lokalnie ([DashboardStore]) per użytkownik. Domyślny
/// układ odwzorowuje dotychczasowy stały Podgląd.
library;

import 'package:flutter/material.dart';

import '../app_settings.dart';
import '../app_state.dart';
import '../dashboard/dash_widgets.dart';
import '../dashboard/dashboard_model.dart';
import '../dashboard/dashboard_store.dart';
import '../telemetry/gt7_packet.dart';
import 'theme.dart';

class PreviewTab extends StatefulWidget {
  const PreviewTab({super.key, required this.controller});

  final TelemetryController controller;

  @override
  State<PreviewTab> createState() => _PreviewTabState();
}

class _PreviewTabState extends State<PreviewTab> {
  final _store = DashboardStore();
  DashboardConfig? _cfg;
  bool _edit = false;
  bool _loading = true;

  // Stan przeciągania/skalowania (w pikselach, zatwierdzany na koniec gestu).
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
    setState(() {
      _cfg = cfg;
      _loading = false;
    });
  }

  void _save() {
    final cfg = _cfg;
    if (cfg != null) _store.save(widget.controller.uid, cfg);
  }

  DashScreen get _screen => _cfg!.screens[_cfg!.activeIndex];

  // --- Zarządzanie ekranami ---

  void _switchScreen(int i) {
    setState(() => _cfg!.activeIndex = i);
    _save();
  }

  Future<void> _addScreen() async {
    final name = await _askText(_t('dash.newScreen'), _t('dash.screenName'));
    if (name == null) return;
    setState(() {
      _cfg!.screens.add(DashScreen(name: name, widgets: []));
      _cfg!.activeIndex = _cfg!.screens.length - 1;
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
    });
    _save();
  }

  // --- Kolizje (widgety nie mogą się nakładać) ---

  bool _overlaps(int gx, int gy, int gw, int gh, int excludeId) {
    for (final o in _screen.widgets) {
      if (o.id == excludeId) continue;
      final hit = gx < o.gx + o.gw &&
          gx + gw > o.gx &&
          gy < o.gy + o.gh &&
          gy + gh > o.gy;
      if (hit) return true;
    }
    return false;
  }

  /// Najbliższe wolne miejsce dla prostokąta gw×gh, startując od (prefX,prefY).
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

  Future<void> _addWidget() async {
    final type = await showModalBottomSheet<DashWidgetType>(
      context: context,
      backgroundColor: AppColors.panel,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(_t('dash.addWidget'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, color: AppColors.text)),
            ),
            for (final t in DashWidgetType.values)
              ListTile(
                dense: true,
                title: Text(dashTypeLabel(t)),
                onTap: () => Navigator.pop(context, t),
              ),
          ],
        ),
      ),
    );
    if (type == null) return;
    final size = dashTypeDefaultSize(type);
    // Zmieść w siatce + znajdź wolne miejsce (bez nakładania).
    final gw = size.w.clamp(1, kGridCols).toInt();
    final gh = size.h.clamp(1, kGridRows).toInt();
    final spot = _findFree(gw, gh, -1, 0, 0);
    if (spot == null) {
      _toast(_t('dash.noSpace'));
      return;
    }
    setState(() {
      _screen.widgets.add(DashWidget(
        id: _cfg!.nextWidgetId(),
        type: type,
        gx: spot.x,
        gy: spot.y,
        gw: gw,
        gh: gh,
      ));
    });
    _save();
  }

  void _removeWidget(int id) {
    setState(() => _screen.widgets.removeWhere((w) => w.id == id));
    _save();
  }

  bool _hasOptions(DashWidgetType t) =>
      dashTypeVariants(t).isNotEmpty ||
      dashTypeHasShowValue(t) ||
      t == DashWidgetType.fuelTarget;

  /// Dialog ustawień pojedynczego widgetu (wariant wyglądu / pokaż liczbę / cel).
  Future<void> _editOptions(DashWidget w) async {
    final variants = dashTypeVariants(w.type);
    final lapsCtrl =
        TextEditingController(text: '${w.optInt('targetLaps', 5)}');
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: AppColors.panel,
          title: Text(dashTypeLabel(w.type)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (variants.isNotEmpty) ...[
                Text(_t('dash.appearance'),
                    style: const TextStyle(color: AppColors.muted)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final v in variants)
                      ChoiceChip(
                        label: Text(dashVariantLabel(v)),
                        selected: w.optStr('variant', variants.first) == v,
                        onSelected: (_) =>
                            setLocal(() => w.options['variant'] = v),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              if (dashTypeHasShowValue(w.type))
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_t('dash.showValue')),
                  value: w.optBool(
                      'showValue', w.type == DashWidgetType.tyres),
                  onChanged: (v) =>
                      setLocal(() => w.options['showValue'] = v),
                ),
              if (w.type == DashWidgetType.fuelTarget)
                Row(
                  children: [
                    Text(_t('dash.lapsCountLabel')),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 80,
                      child: TextField(
                        controller: lapsCtrl,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(border: OutlineInputBorder()),
                        onChanged: (s) {
                          final n = int.tryParse(s);
                          if (n != null && n > 0) w.options['targetLaps'] = n;
                        },
                      ),
                    ),
                  ],
                ),
            ],
          ),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(_t('common.done'))),
          ],
        ),
      ),
    );
    if (!mounted) return;
    setState(() {});
    _save();
  }

  // --- Gesty ---

  void _onMoveEnd(DashWidget w, double cellW, double cellH) {
    final nx = ((w.gx * cellW + _moveDelta.dx) / cellW)
        .round()
        .clamp(0, kGridCols - w.gw)
        .toInt();
    final ny = ((w.gy * cellH + _moveDelta.dy) / cellH)
        .round()
        .clamp(0, kGridRows - w.gh)
        .toInt();
    setState(() {
      if (!_overlaps(nx, ny, w.gw, w.gh, w.id)) {
        w.gx = nx;
        w.gy = ny;
      } else {
        // Cel zajęty - przesuń do najbliższego wolnego miejsca (albo zostaw).
        final free = _findFree(w.gw, w.gh, w.id, nx, ny);
        if (free != null) {
          w.gx = free.x;
          w.gy = free.y;
        }
      }
      _moveId = null;
      _moveDelta = Offset.zero;
    });
    _save();
  }

  void _onResizeEnd(DashWidget w, double cellW, double cellH) {
    var nw = ((w.gw * cellW + _resizeDelta.dx) / cellW)
        .round()
        .clamp(1, kGridCols - w.gx)
        .toInt();
    var nh = ((w.gh * cellH + _resizeDelta.dy) / cellH)
        .round()
        .clamp(1, kGridRows - w.gy)
        .toInt();
    // Zmniejszaj, dopóki nowy rozmiar nachodzi na inny widget (oryginalny
    // rozmiar w oryginalnym miejscu nie koliduje, więc pętla się zatrzyma).
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

  // --- Dialogi pomocnicze ---

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

  void _toast(String s) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(s)));

  @override
  Widget build(BuildContext context) {
    final Widget body = (_loading || _cfg == null)
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              _topBar(),
              Expanded(
                child: ListenableBuilder(
                  listenable: widget.controller,
                  builder: (context, _) {
                    final p = widget.controller.last ?? Gt7Packet();
                    return _grid(p);
                  },
                ),
              ),
            ],
          );
    // Dashboard zostaje ciemny niezależnie od motywu aplikacji (czytelność).
    return Theme(
      data: buildDarkTheme(),
      child: Container(color: AppColors.bg, child: body),
    );
  }

  Widget _topBar() {
    return Container(
      height: 44,
      padding: const EdgeInsets.only(left: 46, right: 4), // miejsce na ikonę menu
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
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
            ),
          ),
          if (_edit) ...[
            IconButton(
              tooltip: _t('dash.addWidget'),
              icon: const Icon(Icons.widgets, color: AppColors.accent),
              onPressed: _addWidget,
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: AppColors.muted),
              onSelected: (v) {
                if (v == 'rename') _renameScreen();
                if (v == 'delete') _deleteScreen();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                    value: 'rename', child: Text(_t('dash.renameScreen'))),
                PopupMenuItem(
                    value: 'delete', child: Text(_t('dash.deleteScreen'))),
              ],
            ),
          ],
          IconButton(
            tooltip: _edit ? _t('common.done') : _t('dash.tipEdit'),
            icon: Icon(_edit ? Icons.check : Icons.edit,
                color: _edit ? AppColors.good : AppColors.muted),
            onPressed: () => setState(() => _edit = !_edit),
          ),
        ],
      ),
    );
  }

  Widget _grid(Gt7Packet p) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: LayoutBuilder(
        builder: (context, cons) {
          final cellW = cons.maxWidth / kGridCols;
          final cellH = cons.maxHeight / kGridRows;
          final children = <Widget>[];

          if (_edit) {
            children.add(Positioned.fill(
              child: CustomPaint(painter: _GridPainter(cellW, cellH)),
            ));
          }

          for (final w in _screen.widgets) {
            var left = w.gx * cellW;
            var top = w.gy * cellH;
            var width = w.gw * cellW;
            var height = w.gh * cellH;
            if (_edit && _moveId == w.id) {
              left += _moveDelta.dx;
              top += _moveDelta.dy;
            }
            if (_edit && _resizeId == w.id) {
              width += _resizeDelta.dx;
              height += _resizeDelta.dy;
            }
            children.add(Positioned(
              left: left,
              top: top,
              width: width.clamp(24.0, cons.maxWidth).toDouble(),
              height: height.clamp(24.0, cons.maxHeight).toDouble(),
              child: _edit ? _editable(w, cellW, cellH, p) : _live(w, p),
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

  Widget _editable(DashWidget w, double cellW, double cellH, Gt7Packet p) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onPanStart: (_) => setState(() {
              _moveId = w.id;
              _moveDelta = Offset.zero;
            }),
            onPanUpdate: (d) => setState(() => _moveDelta += d.delta),
            onPanEnd: (_) => _onMoveEnd(w, cellW, cellH),
            child: Container(
              margin: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.accent, width: 1.5),
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
        // Usuwanie (lewy górny róg).
        Positioned(
          left: 0,
          top: 0,
          child: _miniButton(Icons.close, AppColors.danger,
              () => _removeWidget(w.id)),
        ),
        // Ustawienia widgetu (prawy górny róg) — tylko gdy są jakieś opcje.
        if (_hasOptions(w.type))
          Positioned(
            right: 0,
            top: 0,
            child: _miniButton(
                Icons.tune, AppColors.accent, () => _editOptions(w)),
          ),
        // Uchwyt skalowania (prawy dolny róg).
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

  Widget _miniButton(IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: color,
          borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(10), bottomRight: Radius.circular(8)),
        ),
        child: Icon(icon, size: 15, color: Colors.white),
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
      ..color = AppColors.stroke.withValues(alpha: 0.5)
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
