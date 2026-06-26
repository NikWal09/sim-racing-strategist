/// Powloka aplikacji. Zakladki (Inzynier, Podglad, Nagrania, Ustawienia, Test
/// glosow) wybiera sie z bocznego, wysuwanego menu (Drawer) — dolny pasek
/// znika, dzieki czemu w poziomie dashboard ma maksimum miejsca.
library;

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../app_settings.dart';
import '../app_state.dart';
import '../auth/auth_service.dart';
import '../orientation_modes.dart';
import 'account_screen.dart';
import 'engineer_tab.dart';
import 'preview_tab.dart';
import 'recordings_tab.dart';
import 'settings_tab.dart';
import 'theme.dart';
import 'voice_tab.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final TelemetryController _controller = TelemetryController();
  int _index = 0; // start na Inzynierze (jak na desktopie)
  bool? _wakeOn; // ostatni ustawiony stan wakelocka (anty-zalewanie kanalu)

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncWakelock);
    // Po zalogowaniu: wczytaj indywidualne ustawienia użytkownika z chmury.
    _controller.setUser(_auth.currentUser?.uid);
    _controller.loadCloudSettings();
    _controller.speaker.setLanguage(AppSettings.instance.locale); // głos wg języka
    _applyOrientation(_index); // start na Inżynierze - dozwolone obie orientacje
    // Zmiana języka/motywu odświeża powłokę w miejscu (bez gubienia zakładki).
    AppSettings.instance.addListener(_onAppSettings);
  }

  void _onAppSettings() {
    if (mounted) setState(() {});
  }

  /// Podgląd (index 1) trzymamy w poziomie; pozostałe zakładki można obracać.
  void _applyOrientation(int i) {
    if (i == 1) {
      ScreenOrientation.landscape();
    } else {
      ScreenOrientation.all();
    }
  }

  void _syncWakelock() {
    // Kontroler powiadamia co pakiet (~30 Hz) - wakelock przelaczamy TYLKO przy
    // realnej zmianie stanu, inaczej zalewamy kanal platformy i apka sie zacina.
    final on = _controller.isRunning;
    if (on == _wakeOn) return;
    _wakeOn = on;
    if (on) {
      WakelockPlus.enable();
    } else {
      WakelockPlus.disable();
    }
  }

  @override
  void dispose() {
    AppSettings.instance.removeListener(_onAppSettings);
    _controller.removeListener(_syncWakelock);
    _controller.dispose();
    WakelockPlus.disable();
    ScreenOrientation.all(); // np. po wylogowaniu - ekran logowania obrotowy
    super.dispose();
  }

  // label = klucz i18n (rozwijany w build/drawer przez AppSettings.t).
  static const _items = [
    (icon: Icons.engineering, label: 'nav.engineer'),
    (icon: Icons.speed, label: 'nav.preview'),
    (icon: Icons.list_alt, label: 'nav.recordings'),
    (icon: Icons.settings, label: 'nav.settings'),
    (icon: Icons.record_voice_over, label: 'nav.voice'),
  ];

  @override
  Widget build(BuildContext context) {
    final tabs = [
      EngineerTab(controller: _controller),
      PreviewTab(controller: _controller),
      RecordingsTab(controller: _controller),
      SettingsTab(controller: _controller),
      const VoiceTab(),
    ];

    // Na Podglądzie (index 1) chowamy górny pasek, żeby dashboard miał cały
    // ekran. Dostęp do menu daje mała ikonka w rogu (albo gest od krawędzi).
    final isPreview = _index == 1;
    return Scaffold(
      appBar: isPreview
          ? null
          : AppBar(
              title: Text(
                  'GT7 Race Engineer — ${AppSettings.instance.t(_items[_index].label)}'),
              toolbarHeight: 48,
            ),
      drawer: _buildDrawer(context),
      body: Stack(
        children: [
          IndexedStack(index: _index, children: tabs),
          if (isPreview)
            Positioned(
              top: 2,
              left: 2,
              child: SafeArea(
                child: Builder(
                  builder: (ctx) => Material(
                    color: Colors.black26,
                    shape: const CircleBorder(),
                    child: IconButton(
                      iconSize: 22,
                      icon: const Icon(Icons.menu, color: AppColors.muted2),
                      tooltip: 'Menu',
                      onPressed: () => Scaffold.of(ctx).openDrawer(),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    final cc = context.appColors;
    String t(String k) => AppSettings.instance.t(k);
    return Drawer(
      backgroundColor: cc.panel,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.speed, color: cc.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('GT7 Race Engineer',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: cc.text)),
                        if (_accountName() != null)
                          Text(_accountName()!,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: cc.muted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(color: cc.stroke, height: 1),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (var i = 0; i < _items.length; i++)
                    ListTile(
                      leading: Icon(_items[i].icon,
                          color: i == _index ? cc.accent : cc.muted),
                      title: Text(t(_items[i].label),
                          style: TextStyle(
                              color: i == _index ? cc.text : cc.muted,
                              fontWeight: i == _index
                                  ? FontWeight.w700
                                  : FontWeight.normal)),
                      selected: i == _index,
                      selectedTileColor: cc.accent.withValues(alpha: 0.12),
                      onTap: () {
                        setState(() => _index = i);
                        _applyOrientation(i);
                        Navigator.pop(context);
                      },
                    ),
                ],
              ),
            ),
            if (AuthService.firebaseReady && _auth.currentUser != null) ...[
              Divider(color: cc.stroke, height: 1),
              ListTile(
                leading: Icon(Icons.manage_accounts, color: cc.muted),
                title: Text(t('common.account')),
                onTap: () {
                  Navigator.of(context).pop(); // zamknij szufladę
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const AccountScreen()));
                  // Po powrocie odśwież nazwę w nagłówku szuflady.
                  setState(() {});
                },
              ),
              ListTile(
                leading: Icon(Icons.logout, color: cc.muted),
                title: Text(t('common.logout')),
                onTap: () {
                  // Najpierw zamknij szufladę, potem wyloguj - nawigację na ekran
                  // logowania przejmuje AuthGate. Bez await/popu po, żeby nie
                  // dotykać widoku, który zaraz zniknie (to powodowało crash).
                  Navigator.of(context).pop();
                  _auth.signOut();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  final AuthService _auth = AuthService();

  String? _accountName() {
    if (!AuthService.firebaseReady) return null;
    final u = _auth.currentUser;
    if (u == null) return null;
    final n = (u.displayName ?? '').trim();
    return n.isNotEmpty ? n : u.email;
  }
}
