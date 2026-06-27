/// Zakładka „Stint" — kalkulator paliwa + narzędzie strategii opon.
///
/// 1) Paliwo: tryb Z sesji (na żywo) / Ręcznie. Liczy wspólny [StintCalculator].
/// 2) Pomiar tempa: podczas jazdy app uczy się tempa i degradacji per mieszanka
///    (regresja w [TyrePaceLearner], wiek opony liczony od „montażu").
/// 3) Strategia: dla wybranych mieszanek (tempo + degradacja + życie), długości
///    wyścigu i straty na pit stopie [StrategyCalculator] szereguje najszybsze
///    warianty (ile pit stopów, które mieszanki).
///
/// Opony są szacunkowe — GT7 nie udostępnia mieszanki ani zużycia, więc mieszankę
/// i żywotność wskazuje/koryguje użytkownik (tempo można zmierzyć z jazdy).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_settings.dart';
import '../app_state.dart';
import '../engineer/stint_calculator.dart';
import '../engineer/strategy_calculator.dart';
import '../engineer/tyre_compounds.dart';
import 'theme.dart';

class StintTab extends StatefulWidget {
  const StintTab({super.key, required this.controller});

  final TelemetryController controller;

  @override
  State<StintTab> createState() => _StintTabState();
}

class _StintTabState extends State<StintTab> {
  bool _auto = true; // tryb sekcji paliwa

  // Paliwo (tryb ręczny).
  final _tank = TextEditingController(text: '60');
  final _current = TextEditingController(text: '40');
  final _perLap = TextEditingController(text: '3.0');
  final _laps = TextEditingController(text: '10');
  final _margin = TextEditingController(text: '0.5');

  // Strategia.
  final _raceLaps = TextEditingController(text: '20');
  final _pitLoss = TextEditingController(text: '22');
  bool _twoComp = false;
  final Set<String> _avail = {'RS', 'RM', 'RH'};
  final Map<String, TextEditingController> _base = {};
  final Map<String, TextEditingController> _deg = {};
  final Map<String, TextEditingController> _life = {};

  @override
  void initState() {
    super.initState();
    for (final c in kTyreCompounds) {
      _base[c.id] = TextEditingController(text: _fmt(c.defaultBasePaceS));
      _deg[c.id] = TextEditingController(text: _fmt(c.defaultDegPerLapS));
      _life[c.id] = TextEditingController(text: '${c.defaultLifeLaps}');
    }
  }

  @override
  void dispose() {
    for (final c in [_tank, _current, _perLap, _laps, _margin, _raceLaps, _pitLoss]) {
      c.dispose();
    }
    for (final m in [_base, _deg, _life]) {
      for (final c in m.values) {
        c.dispose();
      }
    }
    super.dispose();
  }

  String _t(String k) => AppSettings.instance.t(k);

  double? _num(TextEditingController? c) {
    final s = c?.text.trim().replaceAll(',', '.') ?? '';
    if (s.isEmpty) return null;
    return double.tryParse(s);
  }

  static String _fmt(double v) {
    final s = v.toStringAsFixed(2);
    return s.endsWith('.00') ? v.toStringAsFixed(0) : s;
  }

  static String _fmtTime(double seconds) {
    final ms = (seconds * 1000).round();
    final m = ms ~/ 60000;
    final rem = ms % 60000;
    final s = rem ~/ 1000;
    final mm = rem % 1000;
    return '$m:${s.toString().padLeft(2, '0')}.${mm.toString().padLeft(3, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final cc = context.appColors;
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(_t('stint.title'),
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: cc.text)),
                const SizedBox(height: 12),
                // --- Paliwo ---
                _sectionTitle(cc, Icons.local_gas_station, _t('stint.fuel')),
                const SizedBox(height: 8),
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(value: true, label: Text(_t('stint.modeAuto'))),
                    ButtonSegment(value: false, label: Text(_t('stint.modeManual'))),
                  ],
                  selected: {_auto},
                  onSelectionChanged: (s) => setState(() => _auto = s.first),
                ),
                const SizedBox(height: 12),
                if (_auto) _fuelAuto(cc) else _fuelManual(cc),
                const SizedBox(height: 22),
                // --- Strategia opon ---
                _sectionTitle(cc, Icons.tire_repair, _t('strat.section')),
                const SizedBox(height: 8),
                _measureCard(cc),
                const SizedBox(height: 14),
                _strategySection(cc),
              ],
            ),
          ),
        );
      },
    );
  }

  // ===================== PALIWO =====================

  Widget _fuelAuto(AppColorsExt cc) {
    final p = widget.controller.last;
    final avg = widget.controller.avgFuelPerLap;
    if (p == null || p.fuelCapacity <= 0 || avg == null || p.totalLaps <= 0) {
      return _hint(cc, _t('stint.noData'));
    }
    final raceLaps = p.totalLaps - p.currentLap + 1;
    if (raceLaps <= 0) return _hint(cc, _t('stint.noData'));

    final plan = StintCalculator.fuel(
      FuelInput(
        tankL: p.fuelCapacity,
        currentL: p.currentFuel,
        perLapL: avg,
        lapsRemaining: raceLaps,
      ),
      marginLaps: widget.controller.engineerCfg.fuelTargetMarginLaps,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _hint(cc, _t('stint.autoHint')),
        const SizedBox(height: 12),
        _readonlyRow(cc, _t('stint.current'),
            '${p.currentFuel.toStringAsFixed(1)} ${_t('stint.unitL')}'),
        _readonlyRow(cc, _t('stint.perLap'),
            '${avg.toStringAsFixed(2)} ${_t('stint.unitL')}'),
        _readonlyRow(cc, _t('stint.lapsRemaining'), '$raceLaps'),
        const SizedBox(height: 14),
        _fuelResult(cc, plan, p.fuelCapacity),
      ],
    );
  }

  Widget _fuelManual(AppColorsExt cc) {
    final tank = _num(_tank) ?? 0.0;
    final current = _num(_current);
    final perLap = _num(_perLap);
    final laps = _num(_laps);
    final margin = _num(_margin) ?? 0.5;

    final ready = current != null &&
        perLap != null &&
        perLap > 0 &&
        laps != null &&
        laps >= 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _field(cc, _t('stint.tank'), _tank, suffix: _t('stint.unitL')),
        _field(cc, _t('stint.current'), _current, suffix: _t('stint.unitL')),
        _field(cc, _t('stint.perLap'), _perLap, suffix: _t('stint.unitL')),
        _field(cc, _t('stint.lapsRemaining'), _laps),
        _field(cc, _t('stint.margin'), _margin),
        const SizedBox(height: 14),
        if (!ready)
          _hint(cc, _t('stint.needInputs'))
        else
          _fuelResult(
            cc,
            StintCalculator.fuel(
              FuelInput(
                tankL: tank,
                currentL: current,
                perLapL: perLap,
                lapsRemaining: laps.round(),
              ),
              marginLaps: margin,
            ),
            tank,
          ),
      ],
    );
  }

  Widget _fuelResult(AppColorsExt cc, FuelPlan plan, double tankL) {
    final ok = plan.finishesWithoutPit;
    final headColor = ok ? cc.good : cc.danger;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cc.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: headColor.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(ok ? Icons.check_circle : Icons.warning_amber_rounded,
                  color: headColor, size: 22),
              const SizedBox(width: 8),
              Text(ok ? _t('stint.finishes') : _t('stint.deficit'),
                  style: TextStyle(
                      color: headColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          if (!ok) ...[
            _valRow(cc, _t('stint.refuel'),
                '+${plan.refuelL.toStringAsFixed(1)} ${_t('stint.unitL')}'
                '${tankL > 0 ? '  (${plan.refuelPct.toStringAsFixed(0)}%)' : ''}',
                strong: true),
            if (plan.savePerLapL > 0.01)
              _valRow(cc, _t('stint.savePerLap'),
                  '${plan.savePerLapL.toStringAsFixed(2)} ${_t('stint.unitL')}'),
          ] else
            _valRow(cc, _t('stint.spareLaps'),
                '${plan.spareLaps.toStringAsFixed(1)} ${_t('stint.unitLap')}',
                strong: true),
          _valRow(cc, _t('stint.lapsOnFuel'),
              '${plan.lapsLeftOnFuel.toStringAsFixed(1)} ${_t('stint.unitLap')}'),
        ],
      ),
    );
  }

  // ===================== POMIAR TEMPA =====================

  Widget _measureCard(AppColorsExt cc) {
    final ctrl = widget.controller;
    final prof = ctrl.paceLearner.profileFor(ctrl.tyreCompoundId);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cc.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cc.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.timer_outlined, size: 18, color: cc.accent),
              const SizedBox(width: 8),
              Text(_t('strat.measure'),
                  style: TextStyle(
                      color: cc.text, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          Text(_t('strat.measureHint'), style: TextStyle(color: cc.muted)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _compoundDropdown(cc)),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: ctrl.mountTyres,
                icon: const Icon(Icons.autorenew, size: 18),
                label: Text(_t('tyre.mountNew')),
              ),
            ],
          ),
          _readonlyRow(cc, _t('tyre.lapsOnSet'), '${ctrl.tyreLapsOnSet}'),
          const SizedBox(height: 4),
          if (prof != null)
            Text(
              '${_t('strat.measured')}: '
              '${prof.basePaceS.toStringAsFixed(2)} s · '
              '+${prof.degPerLapS.toStringAsFixed(3)} s/${_t('stint.unitLap')} · '
              '${prof.sampleLaps} ${_t('strat.samples')}',
              style: TextStyle(color: cc.good, fontWeight: FontWeight.w600),
            )
          else
            Text(_t('strat.noMeasure'), style: TextStyle(color: cc.muted2)),
        ],
      ),
    );
  }

  Widget _compoundDropdown(AppColorsExt cc) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: _t('tyre.compound'),
        labelStyle: TextStyle(color: cc.muted),
        isDense: true,
        border: const OutlineInputBorder(),
        enabledBorder:
            OutlineInputBorder(borderSide: BorderSide(color: cc.stroke)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: widget.controller.tyreCompoundId,
          isExpanded: true,
          dropdownColor: cc.panel,
          style: TextStyle(color: cc.text),
          items: [
            for (final c in kTyreCompounds)
              DropdownMenuItem(value: c.id, child: Text(_t(c.nameKey))),
          ],
          onChanged: (id) {
            if (id == null) return;
            final c = tyreCompoundById(id);
            widget.controller.setTyreCompound(c.id, c.defaultLifeLaps);
            setState(() {});
          },
        ),
      ),
    );
  }

  // ===================== STRATEGIA =====================

  Widget _strategySection(AppColorsExt cc) {
    final profiles = <CompoundProfile>[];
    for (final c in kTyreCompounds) {
      if (!_avail.contains(c.id)) continue;
      final base = _num(_base[c.id]);
      final deg = _num(_deg[c.id]);
      final life = _num(_life[c.id]);
      if (base == null || base <= 0 || life == null || life < 1) continue;
      profiles.add(CompoundProfile(
        id: c.id,
        basePaceS: base,
        degPerLapS: deg ?? 0,
        lifeLaps: life.round(),
      ));
    }

    final raceLaps = (_num(_raceLaps) ?? 0).round();
    final pit = _num(_pitLoss) ?? 0;
    final options = (raceLaps > 0 && profiles.isNotEmpty)
        ? StrategyCalculator.rank(StrategyInput(
            raceLaps: raceLaps,
            pitLossS: pit,
            compounds: profiles,
            requireTwoCompounds: _twoComp,
          ))
        : const <StrategyOption>[];

    final sessionLaps = widget.controller.last?.totalLaps ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _field(cc, _t('strat.raceLaps'), _raceLaps)),
            const SizedBox(width: 10),
            Expanded(child: _field(cc, _t('strat.pitLoss'), _pitLoss)),
          ],
        ),
        if (sessionLaps > 0)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                _raceLaps.text = '$sessionLaps';
                setState(() {});
              },
              icon: const Icon(Icons.download, size: 16),
              label: Text('${_t('strat.fromSession')}: $sessionLaps'),
            ),
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(_t('strat.twoCompounds'),
              style: TextStyle(color: cc.text)),
          value: _twoComp,
          onChanged: (v) => setState(() => _twoComp = v),
        ),
        const SizedBox(height: 6),
        Text(_t('strat.available'),
            style: TextStyle(color: cc.muted, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        for (final c in kTyreCompounds) _compoundRow(cc, c),
        const SizedBox(height: 14),
        Text(_t('strat.results'),
            style: TextStyle(
                color: cc.text, fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (options.isEmpty)
          _hint(cc, _t('strat.noResult'))
        else
          for (var i = 0; i < options.length; i++)
            _strategyCard(cc, options[i], options.first.totalTimeS, i == 0),
      ],
    );
  }

  Widget _compoundRow(AppColorsExt cc, TyreCompound c) {
    final on = _avail.contains(c.id);
    final prof = widget.controller.paceLearner.profileFor(c.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Checkbox(
                value: on,
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _avail.add(c.id);
                  } else {
                    _avail.remove(c.id);
                  }
                }),
              ),
              Expanded(
                child: Text(_t(c.nameKey),
                    style: TextStyle(color: cc.text)),
              ),
              if (prof != null)
                TextButton(
                  onPressed: () {
                    _base[c.id]!.text = _fmt(prof.basePaceS);
                    _deg[c.id]!.text = _fmt(prof.degPerLapS);
                    if (prof.maxAgeLaps > 0) {
                      _life[c.id]!.text = '${prof.maxAgeLaps + 1}';
                    }
                    _avail.add(c.id);
                    setState(() {});
                  },
                  child: Text(_t('strat.useMeasured')),
                ),
            ],
          ),
          if (on)
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 4),
              child: Row(
                children: [
                  Expanded(child: _miniField(cc, _t('strat.base'), _base[c.id]!)),
                  const SizedBox(width: 8),
                  Expanded(child: _miniField(cc, _t('strat.deg'), _deg[c.id]!)),
                  const SizedBox(width: 8),
                  Expanded(child: _miniField(cc, _t('strat.life'), _life[c.id]!)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _strategyCard(
      AppColorsExt cc, StrategyOption o, double bestTime, bool isBest) {
    final plan = o.legs
        .map((l) => '${l.compoundId} ${l.laps}')
        .join('  +  ');
    final stopsText =
        o.stops == 0 ? _t('strat.noStop') : '${o.stops} ${_t('strat.stops')}';
    final delta = isBest
        ? _t('strat.best')
        : '+${(o.totalTimeS - bestTime).toStringAsFixed(1)} s';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cc.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isBest ? cc.good.withValues(alpha: 0.6) : cc.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(stopsText,
                  style: TextStyle(
                      color: isBest ? cc.good : cc.text,
                      fontWeight: FontWeight.w700)),
              Text(delta,
                  style: TextStyle(
                      color: isBest ? cc.good : cc.muted,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(plan,
                    style: TextStyle(color: cc.muted), overflow: TextOverflow.ellipsis),
              ),
              Text(_fmtTime(o.totalTimeS),
                  style: TextStyle(color: cc.text, fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }

  // ===================== WSPÓLNE =====================

  Widget _sectionTitle(AppColorsExt cc, IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 18, color: cc.accent),
        const SizedBox(width: 8),
        Text(text,
            style: TextStyle(
                color: cc.text, fontSize: 15, fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _field(AppColorsExt cc, String label, TextEditingController c,
      {String? suffix}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
        style: TextStyle(color: cc.text),
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: cc.muted),
          suffixText: suffix,
          suffixStyle: TextStyle(color: cc.muted2),
          isDense: true,
          border: const OutlineInputBorder(),
          enabledBorder:
              OutlineInputBorder(borderSide: BorderSide(color: cc.stroke)),
        ),
      ),
    );
  }

  Widget _miniField(AppColorsExt cc, String label, TextEditingController c) {
    return TextField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      style: TextStyle(color: cc.text, fontSize: 13),
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: cc.muted, fontSize: 11),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        border: const OutlineInputBorder(),
        enabledBorder:
            OutlineInputBorder(borderSide: BorderSide(color: cc.stroke)),
      ),
    );
  }

  Widget _readonlyRow(AppColorsExt cc, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: cc.muted)),
          Text(value,
              style: TextStyle(color: cc.text, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _valRow(AppColorsExt cc, String label, String value,
      {bool strong = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: cc.muted)),
          Text(value,
              style: TextStyle(
                  color: cc.text,
                  fontSize: strong ? 18 : 14,
                  fontWeight: strong ? FontWeight.w700 : FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _hint(AppColorsExt cc, String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cc.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cc.stroke),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: cc.muted2),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: cc.muted))),
        ],
      ),
    );
  }
}
