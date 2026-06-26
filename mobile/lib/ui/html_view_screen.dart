/// Pokazuje samodzielny HTML (telemetria / raport opon) w aplikacji.
///
/// Na Androidzie/iOS renderuje w WebView (wygląd 1:1 z wersją komputerową).
/// Na desktopie (brak WebView) zapisuje plik i otwiera w przeglądarce systemowej.
///
/// Dla telemetrii ([zoom] = true) pokazujemy natywny suwak z dwoma końcami —
/// reguluje przybliżenie fragmentu toru, wołając w stronie funkcję setView(a,b).
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../app_settings.dart';
import '../orientation_modes.dart';
import 'theme.dart';

class HtmlViewScreen extends StatefulWidget {
  const HtmlViewScreen({
    super.key,
    required this.html,
    required this.title,
    this.zoom = false,
  });

  final String html;
  final String title;
  final bool zoom; // pokaż suwak przybliżenia fragmentu (telemetria)

  @override
  State<HtmlViewScreen> createState() => _HtmlViewScreenState();
}

class _HtmlViewScreenState extends State<HtmlViewScreen> {
  WebViewController? _controller;
  String _status = AppSettings.instance.t('view.preparing');
  RangeValues _range = const RangeValues(0, 1);

  bool get _webviewSupported =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    // Strony HTML (wykresy, mapa toru) mają sens tylko w poziomie. Jeden kierunek
    // omija błąd WebView z odwracaniem obrazu w odwróconym poziomie.
    if (_webviewSupported) ScreenOrientation.landscapeFixed();
    _prepare();
  }

  @override
  void dispose() {
    // Po wyjściu wracamy do swobodnego obracania (lista nagrań jest obrotowa).
    if (_webviewSupported) ScreenOrientation.all();
    super.dispose();
  }

  Future<void> _prepare() async {
    try {
      final dir = await getTemporaryDirectory();
      final f = File(
          '${dir.path}/gt7_view_${DateTime.now().millisecondsSinceEpoch}.html');
      await f.writeAsString(widget.html);

      if (_webviewSupported) {
        final c = WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setBackgroundColor(AppColors.bg);
        await c.loadFile(f.path);
        if (!mounted) return;
        setState(() => _controller = c);
      } else {
        await launchUrl(Uri.file(f.path),
            mode: LaunchMode.externalApplication);
        if (!mounted) return;
        setState(() => _status = AppSettings.instance.t('view.openedInBrowser'));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() =>
          _status = '${AppSettings.instance.t('view.openFail')}: $e');
    }
  }

  void _applyView() {
    final c = _controller;
    if (c == null) return;
    final a = _range.start.toStringAsFixed(4);
    final b = _range.end.toStringAsFixed(4);
    // setView / resetView to globalne funkcje w stronie telemetrii.
    c.runJavaScript(
        'try{(($a)<=0&&($b)>=1)?resetView():setView($a,$b);}catch(e){}');
  }

  void _resetZoom() {
    setState(() => _range = const RangeValues(0, 1));
    _controller?.runJavaScript('try{resetView();}catch(e){}');
  }

  Widget _zoomBar() {
    final a = (_range.start * 100).round();
    final b = (_range.end * 100).round();
    return Container(
      color: AppColors.panel,
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 6),
      child: Row(
        children: [
          const Icon(Icons.zoom_in, size: 18, color: AppColors.muted),
          const SizedBox(width: 4),
          Text('$a–$b%',
              style: const TextStyle(color: AppColors.muted2, fontSize: 12)),
          Expanded(
            child: RangeSlider(
              values: _range,
              min: 0,
              max: 1,
              labels: RangeLabels('$a%', '$b%'),
              onChanged: (v) {
                setState(() => _range = v);
                _applyView();
              },
            ),
          ),
          TextButton(
              onPressed: _resetZoom,
              child: Text(AppSettings.instance.t('view.whole'))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (!_webviewSupported) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_status,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted)),
        ),
      );
    } else if (_controller == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      final web = WebViewWidget(controller: _controller!);
      body = widget.zoom
          ? Column(children: [Expanded(child: web), _zoomBar()])
          : web;
    }
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: body,
    );
  }
}
