import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_user.dart';
import '../services/api_service.dart';

/// Who the user is. There is no login — `POST /api/users` returns an id and
/// the app stores it, exactly as the backend intends.
class UserState extends ChangeNotifier {
  static const _idKey = 'user_id';
  static const _nameKey = 'user_name';
  static const _groupKey = 'active_join_code';

  AppUser? _user;
  String? _activeJoinCode;
  bool _loading = true;

  AppUser? get user => _user;
  bool get loading => _loading;
  bool get hasUser => _user != null;
  String get userId => _user?.id ?? '';

  /// The group this device last created or joined, so backing out of the group
  /// screen is not a one-way door. Cleared when the session closes or the user
  /// leaves it deliberately.
  String? get activeJoinCode => _activeJoinCode;

  /// Reads the stored id and confirms it still exists on the backend. If the
  /// database was reseeded, the stale id is cleared and the app asks for a
  /// name again instead of failing every later call.
  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_idKey);
    final name = prefs.getString(_nameKey);
    _activeJoinCode = prefs.getString(_groupKey);

    if (id != null && name != null) {
      _user = AppUser(id: id, username: name);
      try {
        _user = await ApiService.getUser(id);
      } on ApiException catch (e) {
        // 404 means the id is gone for good; anything else is likely the
        // server being unreachable, so keep the cached user and carry on.
        if (e.statusCode == 404) {
          await prefs.remove(_idKey);
          await prefs.remove(_nameKey);
          _user = null;
        }
      }
    }

    _loading = false;
    notifyListeners();
  }

  /// Creates the user and stores the returned id.
  Future<void> createUser(String username) async {
    final created = await ApiService.createUser(username);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_idKey, created.id);
    await prefs.setString(_nameKey, created.username);
    _user = created;
    notifyListeners();
  }

  /// Demo convenience: continue as a user that already exists, matched by
  /// username. There is no password and no auth — this only saves retyping a
  /// name when testing the group flow across two devices.
  Future<void> signInAs(String username) async {
    final wanted = username.trim().toLowerCase();
    final users = await ApiService.getUsers();

    AppUser? match;
    for (final user in users) {
      if (user.username.toLowerCase() == wanted) {
        match = user;
        break;
      }
    }

    if (match == null) {
      throw ApiException(404, 'No user called "${username.trim()}" yet.');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_idKey, match.id);
    await prefs.setString(_nameKey, match.username);
    await prefs.remove(_groupKey);
    _user = match;
    _activeJoinCode = null;
    notifyListeners();
  }

  /// Remembers the group this device is in, so the home screen can offer a way
  /// back into it.
  Future<void> rememberGroup(String joinCode) async {
    if (_activeJoinCode == joinCode) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_groupKey, joinCode);
    _activeJoinCode = joinCode;
    notifyListeners();
  }

  /// Called when the session closes, is gone, or the user leaves it.
  Future<void> forgetGroup() async {
    if (_activeJoinCode == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_groupKey);
    _activeJoinCode = null;
    notifyListeners();
  }

  /// Forgets the local user — used by the "Switch user" action.
  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_idKey);
    await prefs.remove(_nameKey);
    await prefs.remove(_groupKey);
    _user = null;
    _activeJoinCode = null;
    notifyListeners();
  }
}
