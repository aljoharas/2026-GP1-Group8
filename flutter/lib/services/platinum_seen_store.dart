// Remembers which Platinums the trophy guide has already celebrated, so the
// celebration only plays the first time the guide is opened after earning
// one. Stored on the device, per signed-in user and game.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PlatinumSeenStore {
  const PlatinumSeenStore();

  String _key(int rawgId) {
    String uid;
    try {
      uid = FirebaseAuth.instance.currentUser?.uid ?? 'anon';
    } catch (_) {
      uid = 'anon'; // Firebase not initialised (tests)
    }
    return 'platinum_celebrated_${uid}_$rawgId';
  }

  /// Marks the game's Platinum as celebrated. True only the first time.
  Future<bool> markCelebrated(int rawgId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _key(rawgId);
      if (prefs.getBool(key) == true) return false;
      await prefs.setBool(key, true);
      return true;
    } catch (_) {
      return false; // storage unavailable: skip rather than celebrate every time
    }
  }
}
