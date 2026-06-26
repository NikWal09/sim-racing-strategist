/// Ustawienia konta: podgląd danych, zmiana nazwy i hasła, usunięcie konta,
/// wylogowanie. Część funkcji (zmiana hasła, usunięcie hasłem) dotyczy tylko
/// kont e-mail/hasło — dla kont Google są ukryte. Kolory z motywu, teksty z i18n.
library;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../app_settings.dart';
import '../auth/auth_service.dart';
import 'theme.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _auth = AuthService();

  String _t(String k) => AppSettings.instance.t(k);

  String _err(FirebaseAuthException e) {
    switch (e.code) {
      case 'wrong-password':
      case 'invalid-credential':
        return _t('account.errWrongPassword');
      case 'weak-password':
        return _t('account.errWeakNew');
      case 'requires-recent-login':
        return _t('account.errRecentLogin');
      case 'network-request-failed':
        return _t('auth.errNetwork');
      default:
        return e.message ?? '${_t('account.error')} (${e.code}).';
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _changeName() async {
    final cc = context.appColors;
    final ctrl =
        TextEditingController(text: _auth.currentUser?.displayName ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cc.panel,
        title: Text(_t('account.changeName')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
              labelText: _t('register.name'),
              border: const OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(_t('common.cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: Text(_t('common.save'))),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      await _auth.setDisplayName(name);
      setState(() {});
      _snack(_t('account.nameChanged'));
    } catch (e) {
      _snack('${_t('account.nameChangeFail')}: $e');
    }
  }

  Future<void> _changePassword() async {
    final cc = context.appColors;
    final cur = TextEditingController();
    final nw = TextEditingController();
    final nw2 = TextEditingController();
    String? localErr;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: cc.panel,
          title: Text(_t('account.changePassword')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: cur,
                obscureText: true,
                decoration: InputDecoration(
                    labelText: _t('account.currentPassword'),
                    border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: nw,
                obscureText: true,
                decoration: InputDecoration(
                    labelText: _t('account.newPassword'),
                    border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: nw2,
                obscureText: true,
                decoration: InputDecoration(
                    labelText: _t('account.repeatNewPassword'),
                    border: const OutlineInputBorder()),
              ),
              if (localErr != null) ...[
                const SizedBox(height: 8),
                Text(localErr!, style: TextStyle(color: cc.danger)),
              ],
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(_t('common.cancel'))),
            FilledButton(
              onPressed: () {
                if (nw.text.length < 6) {
                  setLocal(() => localErr = _t('account.newPassMin'));
                  return;
                }
                if (nw.text != nw2.text) {
                  setLocal(() => localErr = _t('register.errPassMatch'));
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: Text(_t('account.change')),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await _auth.changePassword(cur.text, nw.text);
      _snack(_t('account.passwordChanged'));
    } on FirebaseAuthException catch (e) {
      _snack(_err(e));
    } catch (e) {
      _snack('${_t('account.error')}: $e');
    }
  }

  Future<void> _deleteAccount() async {
    final cc = context.appColors;
    final pass = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cc.panel,
        title: Text(_t('account.deleteTitle')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_t('account.deleteBody'),
                style: TextStyle(color: cc.muted, fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: pass,
              obscureText: true,
              decoration: InputDecoration(
                  labelText: _t('auth.password'),
                  border: const OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(_t('common.cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cc.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_t('account.deleteAccount')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _auth.deleteAccount(pass.text);
      if (mounted) Navigator.of(context).pop();
    } on FirebaseAuthException catch (e) {
      _snack(_err(e));
    } catch (e) {
      _snack('${_t('account.error')}: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cc = context.appColors;
    final u = _auth.currentUser;
    final name = (u?.displayName ?? '').trim();
    final email = u?.email ?? '—';
    final verified = u?.emailVerified ?? false;
    final isPass = _auth.isPasswordAccount;

    return Scaffold(
      appBar: AppBar(title: Text(_t('common.account'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _info(_t('account.name'), name.isEmpty ? '—' : name, Icons.person),
          _info(_t('auth.email'), email, Icons.email),
          _info(
            _t('account.status'),
            verified ? _t('account.verified') : _t('account.notVerified'),
            verified ? Icons.verified : Icons.warning_amber,
            color: verified ? cc.accent : cc.danger,
          ),
          Divider(color: cc.stroke, height: 24),
          ListTile(
            leading: Icon(Icons.edit, color: cc.muted),
            title: Text(_t('account.changeName')),
            onTap: _changeName,
          ),
          if (isPass)
            ListTile(
              leading: Icon(Icons.lock_reset, color: cc.muted),
              title: Text(_t('account.changePassword')),
              onTap: _changePassword,
            ),
          ListTile(
            leading: Icon(Icons.logout, color: cc.muted),
            title: Text(_t('common.logout')),
            onTap: () {
              Navigator.of(context).pop();
              _auth.signOut();
            },
          ),
          Divider(color: cc.stroke, height: 24),
          if (isPass)
            ListTile(
              leading: Icon(Icons.delete_forever, color: cc.danger),
              title: Text(_t('account.deleteAccount'),
                  style: TextStyle(color: cc.danger)),
              onTap: _deleteAccount,
            ),
        ],
      ),
    );
  }

  Widget _info(String label, String value, IconData icon, {Color? color}) {
    final cc = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color ?? cc.muted),
          const SizedBox(width: 12),
          Text('$label: ', style: TextStyle(color: cc.muted)),
          Expanded(
            child: Text(value,
                style: TextStyle(color: color ?? cc.text),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}
