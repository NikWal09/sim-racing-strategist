/// Zakładka "Nagrania" — lista zapisanych okrążeń + wejście do podglądu.
///
/// Nagrania powstają automatycznie podczas jazdy (recorder). Lista odświeża się
/// po zapisaniu nowego okrążenia (controller.recordingsRev) oraz przyciskiem.
library;

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../app_settings.dart';
import '../app_state.dart';
import '../auth/auth_service.dart';
import '../engineer/gt7_tracks.dart';
import '../telemetry/gt7_packet.dart';
import 'html_view_screen.dart';
import 'theme.dart';
import 'tyre_report_html.dart';
import 'viewer_html.dart';

class RecordingsTab extends StatefulWidget {
  const RecordingsTab({super.key, required this.controller});

  final TelemetryController controller;

  @override
  State<RecordingsTab> createState() => _RecordingsTabState();
}

class _RecordingsTabState extends State<RecordingsTab> {
  List<Map<String, dynamic>> _laps = [];
  final Set<String> _selected = {}; // ścieżki zaznaczonych okrążeń
  bool _loading = true;
  int _seenRev = -1;

  String _t(String k) => AppSettings.instance.t(k);

  void _toggle(String? path) {
    if (path == null) return;
    setState(() {
      if (_selected.contains(path)) {
        _selected.remove(path);
      } else {
        _selected.add(path);
      }
    });
  }

  /// Pełne dane okrążeń do generowania HTML: zaznaczone, a gdy nic nie zaznaczono
  /// — wszystkie.
  Future<List<Map<String, dynamic>>> _lapsForExport() async {
    if (_selected.isEmpty) return widget.controller.recordings.listFull();
    final out = <Map<String, dynamic>>[];
    for (final p in _selected) {
      try {
        out.add(await widget.controller.recordings.loadFull(p));
      } catch (_) {}
    }
    out.sort((a, b) {
      final tk = '${a['track_key']}'.compareTo('${b['track_key']}');
      if (tk != 0) return tk;
      return ((a['lap_ms'] ?? 0) as num).compareTo((b['lap_ms'] ?? 0) as num);
    });
    return out;
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
    _reload();
  }

  void _onChange() {
    if (widget.controller.recordingsRev != _seenRev) _reload();
  }

  Future<void> _reload() async {
    _seenRev = widget.controller.recordingsRev;
    setState(() => _loading = true);
    List<Map<String, dynamic>> laps = [];
    try {
      await widget.controller.trackLabels.load();
      laps = await widget.controller.recordings.list();
    } catch (_) {
      // Brak dostępu do katalogu (np. w środowisku testowym) - pusta lista.
    }
    if (!mounted) return;
    setState(() {
      _laps = laps;
      _loading = false;
    });
  }

  Future<void> _delete(Map<String, dynamic> lap) async {
    final path = lap['_file'] as String?;
    if (path == null) return;
    _selected.remove(path);
    await widget.controller.recordings.delete(path);
    _reload();
  }

  /// Usuwa naraz wszystkie zaznaczone nagrania (po potwierdzeniu).
  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    final n = _selected.length;
    final cc = context.appColors;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cc.panel,
        title: Text(_t('rec.deleteSelTitle')),
        content: Text(
            '${_t('rec.deleteSelBody1')} $n ${_t('rec.deleteSelBody2')}',
            style: TextStyle(color: cc.muted)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(_t('common.cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cc.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_t('common.delete')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    for (final p in _selected.toList()) {
      try {
        await widget.controller.recordings.delete(p);
      } catch (_) {}
    }
    _selected.clear();
    _reload();
  }

  Future<void> _setRef(Map<String, dynamic> lap) async {
    final path = lap['_file'] as String?;
    if (path == null) return;
    await widget.controller.setReferenceFromPath(path);
    if (!mounted) return;
    setState(() {});
    final info = widget.controller.refInfo;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(info != null
          ? '${_t('rec.reference')}: ${info.lapTime} (${info.trackKey})'
          : _t('rec.refFail')),
    ));
  }

  void _clearRef() {
    widget.controller.clearReference();
    setState(() {});
  }

  /// Nazwa toru: przypisana (po obrysie) albo fingerprint (track_key) w razie braku.
  String _trackLabel(Map<String, dynamic> lap) {
    final name = widget.controller.trackLabels
        .nameFor(lap['fingerprint'] as Map<String, dynamic>?);
    return name ?? '${lap['track_key']}';
  }

  Future<void> _nameTrack(Map<String, dynamic> lap) async {
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => const _TrackNameDialog(),
    );
    if (picked == null || picked.isEmpty) return;
    await widget.controller.trackLabels
        .assign(lap['fingerprint'] as Map<String, dynamic>?, picked);
    if (!mounted) return;
    setState(() {});
  }

  /// Udostępnia plik nagrania przez systemowy share sheet (z nazwą autora).
  Future<void> _share(Map<String, dynamic> lap) async {
    final path = lap['_file'] as String?;
    if (path == null) return;
    try {
      final name = AuthService().currentUser?.displayName;
      final shared = await widget.controller.recordings
          .exportForShare(path, sharedBy: name);
      final time = (lap['lap_time'] as String?) ??
          Gt7Packet.formatLaptime((lap['lap_ms'] ?? 0) as int);
      await Share.shareXFiles([XFile(shared)],
          text: '${_t('rec.shareText')}: ${_trackLabel(lap)} · $time');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  /// Importuje nagranie z pliku JSON od innego użytkownika.
  Future<void> _import() async {
    try {
      // FileType.any zamiast custom('json') - filtr custom nie jest wspierany
      // na części urządzeń/emulatorów (PlatformException "Unsupported filter").
      // Poprawność pliku i tak weryfikuje importFromJson.
      final res = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );
      if (res == null || res.files.isEmpty) return;
      final f = res.files.first;
      String content;
      if (f.bytes != null) {
        content = utf8.decode(f.bytes!);
      } else if (f.path != null) {
        content = await File(f.path!).readAsString();
      } else {
        return;
      }
      await widget.controller.recordings.importFromJson(content);
      _reload();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_t('rec.importOk'))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${_t('rec.importFail')}: $e')));
      }
    }
  }

  Future<void> _openViewer(Map<String, dynamic> lap, String time) async {
    final path = lap['_file'] as String?;
    if (path == null) return;
    final full = await widget.controller.recordings.loadFull(path);
    if (!mounted) return;
    final html = buildViewerHtml([full]);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => HtmlViewScreen(
          html: html, title: '${_trackLabel(lap)} · $time', zoom: true),
    ));
  }

  Future<void> _openTelemetryHtml() async {
    final laps = await _lapsForExport();
    if (!mounted) return;
    if (laps.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_t('rec.nothingToShow'))));
      return;
    }
    final html = buildViewerHtml(laps);
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => HtmlViewScreen(
          html: html, title: _t('rec.telemetryTitle'), zoom: true),
    ));
  }

  Future<void> _openTyreReport() async {
    final laps = await _lapsForExport();
    if (!mounted) return;
    if (laps.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_t('rec.nothingToShow'))));
      return;
    }
    final html = buildReportHtml(laps);
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => HtmlViewScreen(html: html, title: _t('rec.tyreReport')),
    ));
  }


  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cc = context.appColors;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _laps.isEmpty
                      ? _t('rec.noRecordings')
                      : (_selected.isEmpty
                          ? '${_t('rec.lapsCount')}: ${_laps.length} (${_t('rec.noneSelectedAll')})'
                          : '${_t('rec.selected')}: ${_selected.length} ${_t('rec.of')} ${_laps.length}'),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: cc.muted2),
                ),
              ),
              IconButton(
                onPressed: _reload,
                icon: Icon(Icons.refresh, color: cc.muted),
                tooltip: _t('rec.refresh'),
              ),
            ],
          ),
          // Akcje w osobnej, przewijanej w poziomie linii - nie przepełnia się
          // ani w poziomie, ani w pionie.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: _openTelemetryHtml,
                  icon: const Icon(Icons.show_chart, size: 18),
                  label: Text(_t('rec.telemetry')),
                ),
                TextButton.icon(
                  onPressed: _openTyreReport,
                  icon: const Icon(Icons.thermostat, size: 18),
                  label: Text(_t('rec.tyreReport')),
                ),
                if (_selected.isNotEmpty)
                  TextButton.icon(
                    onPressed: _deleteSelected,
                    icon: Icon(Icons.delete_outline, size: 18, color: cc.danger),
                    label: Text('${_t('rec.deleteShort')} (${_selected.length})',
                        style: TextStyle(color: cc.danger)),
                  ),
                TextButton.icon(
                  onPressed: _import,
                  icon: const Icon(Icons.file_download_outlined, size: 18),
                  label: Text(_t('rec.import')),
                ),
              ],
            ),
          ),
          if (widget.controller.refInfo != null) _refBanner(),
          const SizedBox(height: 4),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _laps.isEmpty
                    ? Center(
                        child: Text(_t('rec.autoNote'),
                            style: TextStyle(color: cc.muted)))
                    : ListView.separated(
                        itemCount: _laps.length,
                        separatorBuilder: (_, __) =>
                            Divider(height: 1, color: cc.stroke),
                        itemBuilder: (context, i) => _row(_laps[i]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _refBanner() {
    final cc = context.appColors;
    final info = widget.controller.refInfo!;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: cc.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cc.accent),
      ),
      child: Row(
        children: [
          Icon(Icons.flag, size: 18, color: cc.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${_t('rec.reference')}: ${info.lapTime} · ${info.trackKey} · ${info.carName}',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: cc.text),
            ),
          ),
          TextButton(onPressed: _clearRef, child: Text(_t('rec.clear'))),
        ],
      ),
    );
  }

  Widget _row(Map<String, dynamic> lap) {
    final cc = context.appColors;
    final time = (lap['lap_time'] as String?) ??
        Gt7Packet.formatLaptime((lap['lap_ms'] ?? 0) as int);
    final recorded = '${lap['recorded_at'] ?? ''}'.replaceFirst('T', ' ');
    final path = lap['_file'] as String?;
    final checked = path != null && _selected.contains(path);
    final sharedBy = lap['shared_by'];
    final extra = lap['imported'] == true
        ? ' · ${_t('rec.imported')}${sharedBy != null ? ' ${_t('rec.from')} $sharedBy' : ''}'
        : '';
    return ListTile(
      dense: true,
      leading: Checkbox(
        value: checked,
        onChanged: (_) => _toggle(path),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(_trackLabel(lap),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontWeight: FontWeight.w600, color: cc.text)),
          ),
          const SizedBox(width: 12),
          Text(time,
              style:
                  TextStyle(color: cc.accent, fontWeight: FontWeight.w700)),
        ],
      ),
      subtitle: Text(
        '${_t('rec.lapShort')} ${lap['lap_number']} · ${lap['car_name'] ?? lap['car_code']} · $recorded$extra',
        style: TextStyle(color: cc.muted, fontSize: 12),
      ),
      trailing: PopupMenuButton<String>(
        icon: Icon(Icons.more_vert, color: cc.muted),
        onSelected: (v) {
          if (v == 'view') {
            _openViewer(lap, time);
          } else if (v == 'name') {
            _nameTrack(lap);
          } else if (v == 'ref') {
            _setRef(lap);
          } else if (v == 'share') {
            _share(lap);
          } else if (v == 'delete') {
            _delete(lap);
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(value: 'view', child: Text(_t('rec.viewSingle'))),
          PopupMenuItem(value: 'name', child: Text(_t('rec.nameTrack'))),
          PopupMenuItem(value: 'ref', child: Text(_t('rec.setReference'))),
          PopupMenuItem(value: 'share', child: Text(_t('rec.share'))),
          PopupMenuItem(value: 'delete', child: Text(_t('rec.delete'))),
        ],
      ),
      onTap: () => _toggle(path),
    );
  }
}

/// Dialog wyboru nazwy toru: wyszukiwarka po liście oficjalnych torów GT7
/// ([gt7TrackNames]) z możliwością wpisania własnej nazwy.
class _TrackNameDialog extends StatefulWidget {
  const _TrackNameDialog();

  @override
  State<_TrackNameDialog> createState() => _TrackNameDialogState();
}

class _TrackNameDialogState extends State<_TrackNameDialog> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final matches = q.isEmpty
        ? gt7TrackNames
        : gt7TrackNames.where((n) => n.toLowerCase().contains(q)).toList();
    final cc = context.appColors;
    final t = AppSettings.instance.t;
    return AlertDialog(
      backgroundColor: cc.panel,
      title: Text(t('rec.nameTrack')),
      content: SizedBox(
        width: 460,
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _q = v),
              decoration: InputDecoration(
                labelText: t('rec.searchTrack'),
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
              ),
            ),
            if (q.isNotEmpty)
              ListTile(
                dense: true,
                leading: Icon(Icons.edit, color: cc.accent),
                title: Text('${t('rec.useCustom')}: „${_q.trim()}"'),
                onTap: () => Navigator.pop(context, _q.trim()),
              ),
            Expanded(
              child: ListView.builder(
                itemCount: matches.length,
                itemBuilder: (_, i) => ListTile(
                  dense: true,
                  title: Text(matches[i]),
                  onTap: () => Navigator.pop(context, matches[i]),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t('common.cancel')),
        ),
      ],
    );
  }
}
