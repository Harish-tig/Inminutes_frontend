import 'package:socket_io_client/socket_io_client.dart' as io;

import '../utils/config.dart';

/// Thin wrapper over socket.io for one group session.
///
/// The client never writes state over the socket — all changes go through the
/// REST API. The socket delivers `group:state`, which carries the complete
/// session state so the listener can replace its copy wholesale, plus
/// `group:participant_removed`, which is the one thing state alone cannot say.
class SocketService {
  io.Socket? _socket;

  /// Connects and subscribes to [joinCode]'s room.
  ///
  /// [onState] fires with the raw `group:state` payload; [onConnectionChange]
  /// reports connect/disconnect so the UI can show a "reconnecting" hint;
  /// [onParticipantRemoved] fires with the removed member's user id.
  void connect({
    required String joinCode,
    required void Function(Map<String, dynamic> state) onState,
    void Function(bool connected)? onConnectionChange,
    void Function(String userId, String displayName)? onParticipantRemoved,
  }) {
    // Socket.IO uses the bare server URL — no `/api` suffix.
    //
    // forceNew matters: without it the package hands back a *cached* connection
    // for this host, so a second SocketService would reuse the first one's
    // socket. Already being connected means onConnect never fires again, the
    // `group:join` below is never sent, and that session silently receives no
    // updates. One connection per SocketService avoids the whole problem.
    final socket = io.io(
      AppConfig.serverUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .enableReconnection()
          .enableForceNew()
          .disableAutoConnect()
          .build(),
    );

    // Re-emitted on every connect, so a reconnect re-subscribes by itself.
    socket.onConnect((_) {
      socket.emit('group:join', joinCode);
      onConnectionChange?.call(true);
    });

    socket.onDisconnect((_) => onConnectionChange?.call(false));

    socket.on('group:state', (data) {
      if (data is Map) {
        onState(Map<String, dynamic>.from(data));
      }
    });

    // The one event that is not just state: a kicked client cannot tell from
    // the new state that it was removed, it only sees itself missing.
    socket.on('group:participant_removed', (data) {
      if (data is Map) {
        onParticipantRemoved?.call(
          data['user'] as String? ?? '',
          data['display_name'] as String? ?? '',
        );
      }
    });

    socket.connect();

    // If this socket was somehow already up, onConnect will not fire, so
    // subscribe here too. Joining a room twice is harmless.
    if (socket.connected) socket.emit('group:join', joinCode);

    _socket = socket;
  }

  /// Leaves the room and tears the connection down.
  void dispose(String joinCode) {
    final socket = _socket;
    if (socket == null) return;
    if (socket.connected) socket.emit('group:leave', joinCode);
    socket.dispose();
    _socket = null;
  }
}
