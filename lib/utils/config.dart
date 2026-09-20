/// The only place the backend address lives.
///
/// Deliberately free of Flutter imports: `tool/api_smoke.dart` runs on the
/// plain Dart VM and reaches the backend through this file. That is why the
/// web check below is `bool.fromEnvironment` rather than `kIsWeb` — same
/// value, no `package:flutter` dependency.
class AppConfig {
  /// True when compiled for the web, without importing Flutter. This is how
  /// `kIsWeb` itself is defined.
  static const bool _isWeb = bool.fromEnvironment('dart.library.js_util');

  /// Host of the inminutes backend, with no trailing slash and no `/api`.
  ///
  /// On the web the app and the backend share a machine, so `localhost` works.
  /// On Android, `10.0.2.2` is the emulator's alias for the host machine — a
  /// real phone needs the LAN IP or a dev tunnel passed in instead.
  ///
  /// Override without touching code:
  ///   flutter run   --dart-define=SERVER_URL=https://my-tunnel.example.com
  ///   flutter build apk --dart-define=SERVER_URL=https://my-tunnel.example.com
  static const String serverUrl = String.fromEnvironment(
    'SERVER_URL',
    defaultValue: _isWeb ? 'http://localhost:3000' : 'http://10.0.2.2:3000',
  );

  /// REST base URL. Socket.IO uses [serverUrl] instead — it has no `/api`.
  static const String apiBaseUrl = '$serverUrl/api';

  /// How long a single REST call may take before it is treated as unreachable.
  static const Duration requestTimeout = Duration(seconds: 15);
}
