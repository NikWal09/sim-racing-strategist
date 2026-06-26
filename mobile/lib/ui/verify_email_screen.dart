/// Brama weryfikacji e-maila. Pokazywana, gdy użytkownik jest zalogowany, ale
/// nie potwierdził jeszcze adresu (konta e-mail/hasło). Dostęp do aplikacji
/// dopiero po kliknięciu linku z wiadomości i sprawdzeniu tutaj.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../app_settings.dart';
import '../auth/auth_service.dart';
import 'theme.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key, required this.onVerified});

  /// Wywoływane, gdy e-mail został potwierdzony (bramka przechodzi dalej).
  final VoidCallback onVerified;

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final _auth = AuthService();
  bool _busy = false;
  String? _msg;
  int _cooldown = 0; // sekundy do ponownego wysłania
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      final ok = await _auth.reloadAndCheckVerified();
      if (!mounted) return;
      if (ok) {
        widget.onVerified();
      } else {
        setState(() => _msg = AppSettings.instance.t('verify.notVerified'));
      }
    } catch (e) {
      if (mounted) {
        setState(() =>
            _msg = '${AppSettings.instance.t('verify.checkError')}: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      await _auth.sendEmailVerification();
      if (!mounted) return;
      setState(() {
        _msg = AppSettings.instance.t('verify.resent');
        _cooldown = 30;
      });
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return;
        setState(() => _cooldown--);
        if (_cooldown <= 0) t.cancel();
      });
    } catch (e) {
      if (mounted) {
        setState(
            () => _msg = '${AppSettings.instance.t('verify.sendError')}: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cc = context.appColors;
    String t(String k) => AppSettings.instance.t(k);
    final email = _auth.currentUser?.email ?? 'Twój e-mail';
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.mark_email_unread, size: 56, color: cc.accent),
                const SizedBox(height: 12),
                Text(t('verify.title'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(
                  '${t('verify.sentTo')}\n$email\n\n${t('verify.instruction')}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cc.muted),
                ),
                if (_msg != null) ...[
                  const SizedBox(height: 12),
                  Text(_msg!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: cc.accent)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _check,
                  child: _busy
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(t('verify.check')),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: (_busy || _cooldown > 0) ? null : _resend,
                  child: Text(_cooldown > 0
                      ? '${t('verify.resendShort')} ($_cooldown s)'
                      : t('verify.resend')),
                ),
                TextButton(
                  onPressed: _busy ? null : _auth.signOut,
                  child: Text(t('common.logout')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
