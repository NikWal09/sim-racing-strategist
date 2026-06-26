/// Ekran pierwszej konfiguracji konta — prosi o nazwę wyświetlaną (ksywę).
///
/// Pokazywany po pierwszym logowaniu, gdy konto nie ma jeszcze nazwy. Zapisuje
/// nazwę w profilu Firebase (bez osobnej bazy). Pełna synchronizacja ustawień
/// dojdzie w kolejnym kroku.
library;

import 'package:flutter/material.dart';

import '../app_settings.dart';
import '../auth/auth_service.dart';
import 'theme.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _auth = AuthService();
  final _name = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _busy = true);
    try {
      await _auth.setDisplayName(name);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _busy = false);
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final cc = context.appColors;
    String t(String k) => AppSettings.instance.t(k);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(t('setup.welcome'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(t('setup.ask'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cc.muted)),
                const SizedBox(height: 20),
                TextField(
                  controller: _name,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _save(),
                  decoration: InputDecoration(
                      labelText: t('setup.nameLabel'),
                      border: const OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: _busy
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(t('setup.start')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
