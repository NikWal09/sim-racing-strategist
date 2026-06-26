/// Synchronizacja indywidualnych ustawień użytkownika do Firestore.
///
/// Dokument `users/{uid}` trzyma `settings` (mapa) + nazwę. Działa tylko, gdy
/// Firebase jest skonfigurowany i użytkownik zalogowany; inaczej metody są no-op
/// i apka korzysta z ustawień lokalnych.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../auth/auth_service.dart';

class UserSettingsService {
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// Wczytuje mapę ustawień użytkownika (albo null, gdy brak / tryb lokalny).
  Future<Map<String, dynamic>?> load(String uid) async {
    if (!AuthService.firebaseReady) return null;
    try {
      final doc = await _db.collection('users').doc(uid).get();
      return doc.data()?['settings'] as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  /// Zapisuje ustawienia (merge, żeby nie kasować innych pól dokumentu).
  Future<void> save(String uid, Map<String, dynamic> settings,
      {String? displayName}) async {
    if (!AuthService.firebaseReady) return;
    try {
      await _db.collection('users').doc(uid).set({
        'settings': settings,
        if (displayName != null) 'displayName': displayName,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Brak sieci itp. - ustawienia i tak zostają lokalnie w pamięci.
    }
  }
}
