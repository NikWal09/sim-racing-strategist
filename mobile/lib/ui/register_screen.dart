/// Ekran rejestracji konta: nazwa + e-mail + hasło + powtórzenie hasła.
///
/// Po udanej rejestracji konto ma ustawioną nazwę, a na e-mail wysyłany jest
/// link weryfikacyjny. Dalej kierujemy do bramy weryfikacji ([VerifyEmailScreen])
/// — dostęp do aplikacji dopiero po potwierdzeniu adresu.
library;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../app_settings.dart';
import '../auth/auth_service.dart';
import 'theme.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _auth = AuthService();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  bool _busy = false;
  bool _hide = true;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _pass.dispose();
    _pass2.dispose();
    super.dispose();
  }

  String? _validate() {
    final t = AppSettings.instance.t;
    if (_name.text.trim().isEmpty) return t('register.errName');
    if (_email.text.trim().isEmpty) return t('register.errEmail');
    if (_pass.text.length < 6) return t('register.errPassLen');
    if (_pass.text != _pass2.text) return t('register.errPassMatch');
    return null;
  }

  Future<void> _submit() async {
    final v = _validate();
    if (v != null) {
      setState(() => _error = v);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _auth.registerEmail(
          _email.text.trim(), _pass.text, _name.text.trim());
      if (!mounted) return;
      Navigator.of(context).pop(); // wróć — AuthGate pokaże bramę weryfikacji
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _msg(e));
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _msg(FirebaseAuthException e) {
    final t = AppSettings.instance.t;
    switch (e.code) {
      case 'invalid-email':
        return t('auth.errInvalidEmail');
      case 'email-already-in-use':
        return t('auth.errEmailInUse');
      case 'weak-password':
        return t('auth.errWeakPassword');
      case 'network-request-failed':
        return t('auth.errNetwork');
      default:
        return e.message ?? '${t('register.errGeneric')} (${e.code}).';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cc = context.appColors;
    String t(String k) => AppSettings.instance.t(k);
    return Scaffold(
      appBar: AppBar(title: Text(t('register.title'))),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                      labelText: t('register.name'),
                      border: const OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: InputDecoration(
                      labelText: t('auth.email'),
                      border: const OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pass,
                  obscureText: _hide,
                  decoration: InputDecoration(
                    labelText: t('auth.password'),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_hide ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _hide = !_hide),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pass2,
                  obscureText: _hide,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                      labelText: t('register.repeatPassword'),
                      border: const OutlineInputBorder()),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: TextStyle(color: cc.danger)),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(t('register.create')),
                ),
                const SizedBox(height: 8),
                Text(
                  t('register.emailHint'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cc.muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
