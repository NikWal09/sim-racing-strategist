/// Ekran logowania / rejestracji (e-mail + hasło oraz Google).
library;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_settings.dart';
import '../auth/auth_service.dart';
import 'register_screen.dart';
import 'theme.dart';

/// Czy logowanie Google jest wspierane na tej platformie (google_sign_in:
/// Android, iOS, web, macOS — NIE Windows/Linux).
bool get _googleSupported =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.macOS;

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _auth = AuthService();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  bool _hide = true;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await action();
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _msg(e));
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgotPassword() async {
    final t = AppSettings.instance.t;
    final cc = context.appColors;
    final ctrl = TextEditingController(text: _email.text.trim());
    final email = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cc.panel,
        title: Text(t('auth.resetTitle')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(t('auth.resetHint'),
                style: TextStyle(color: cc.muted, fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: InputDecoration(
                  labelText: t('auth.email'),
                  border: const OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(t('common.cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: Text(t('auth.send'))),
        ],
      ),
    );
    if (email == null || email.isEmpty) return;
    await _run(() async {
      await _auth.sendPasswordReset(email);
      if (mounted) {
        setState(() => _info = '${t('auth.resetSent')}: $email');
      }
    });
  }

  String _msg(FirebaseAuthException e) {
    final t = AppSettings.instance.t;
    switch (e.code) {
      case 'invalid-email':
        return t('auth.errInvalidEmail');
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return t('auth.errBadCredentials');
      case 'email-already-in-use':
        return t('auth.errEmailInUse');
      case 'weak-password':
        return t('auth.errWeakPassword');
      case 'network-request-failed':
        return t('auth.errNetwork');
      default:
        return e.message ?? '${t('auth.errLoginGeneric')} (${e.code}).';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cc = context.appColors;
    String t(String k) => AppSettings.instance.t(k);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.speed, size: 56, color: cc.accent),
                const SizedBox(height: 8),
                const Text('GT7 Race Engineer',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 24),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                      labelText: t('auth.email'),
                      border: const OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pass,
                  obscureText: _hide,
                  onSubmitted: (_) => _busy
                      ? null
                      : _run(() =>
                          _auth.signInEmail(_email.text.trim(), _pass.text)),
                  decoration: InputDecoration(
                    labelText: t('auth.password'),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_hide ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _hide = !_hide),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _busy ? null : _forgotPassword,
                    child: Text(t('auth.forgotPassword')),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 4),
                  Text(_error!, style: TextStyle(color: cc.danger)),
                ],
                if (_info != null) ...[
                  const SizedBox(height: 4),
                  Text(_info!, style: TextStyle(color: cc.accent)),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() =>
                          _auth.signInEmail(_email.text.trim(), _pass.text)),
                  child: _busy
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(t('auth.login')),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const RegisterScreen())),
                  child: Text(t('auth.noAccountRegister')),
                ),
                if (_googleSupported) ...[
                  Row(children: [
                    Expanded(child: Divider(color: cc.stroke)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(t('auth.or'),
                          style: TextStyle(color: cc.muted)),
                    ),
                    Expanded(child: Divider(color: cc.stroke)),
                  ]),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _run(_auth.signInGoogle),
                    icon: const Icon(Icons.account_circle),
                    label: Text(t('auth.google')),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
