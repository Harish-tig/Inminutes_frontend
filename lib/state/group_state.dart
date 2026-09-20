import 'package:flutter/foundation.dart';

import '../models/group_session.dart';
import '../models/order.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import 'shop_state.dart';

/// One live group session, plus the socket that keeps it in sync.
///
/// Created by the group route only, so the socket connects when the group
/// screen opens and is torn down when it closes. Every mutation is a REST call
/// whose response is the full group state; the socket delivers the same object
/// when *someone else* makes a change. Either way the session is replaced
/// wholesale — there is no diffing anywhere.
class GroupState extends ChangeNotifier {
  final String joinCode;
  final String userId;
  final ShopState _shop;
  final SocketService _socket = SocketService();

  GroupSession? _session;
  bool _loading = true;
  bool _connected = false;
  bool _disposed = false;
  bool _removed = false;
  String? _error;

  GroupState({
    required this.joinCode,
    required this.userId,
    required ShopState shop,
  }) : _shop = shop {
    _start();
  }

  GroupSession? get session => _session;
  bool get loading => _loading;
  bool get connected => _connected;
  String? get error => _error;

  bool get isHost => _session?.isHost(userId) ?? false;
  bool get isMember => _session?.isMember(userId) ?? false;
  bool get isReady => _session?.participantFor(userId)?.ready ?? false;
  bool get isActive => _session?.active ?? false;

  /// True once the host has kicked this device out of the session.
  bool get wasRemoved => _removed;

  /// Reads the current state once over REST, then subscribes for updates.
  Future<void> _start() async {
    try {
      _session = await ApiService.getGroupSession(joinCode);
      _error = null;
    } on ApiException catch (e) {
      _error = e.message;
    }
    _loading = false;
    _safeNotify();

    _socket.connect(
      joinCode: joinCode,
      onState: _onSocketState,
      onConnectionChange: (connected) {
        _connected = connected;
        _safeNotify();
      },
      onParticipantRemoved: (removedId, _) {
        if (removedId == userId) {
          _removed = true;
          _safeNotify();
        }
      },
    );
  }

  /// A `group:state` push from another device.
  void _onSocketState(Map<String, dynamic> json) {
    _session = GroupSession.fromJson(json);
    _safeNotify();
    // Stock moved, so the group menu's availability needs to move with it.
    _shop.loadProducts(showSpinner: false);
  }

  /// Applies the state a REST call returned, for the device that made the
  /// change — it does not receive its own broadcast any sooner than this.
  void _apply(GroupSession session) {
    _session = session;
    _safeNotify();
    _shop.loadProducts(showSpinner: false);
  }

  // ------------------------------------------------------------- mutations

  Future<void> setReady(bool ready) async =>
      _apply(await ApiService.setReady(joinCode, userId, ready));

  Future<void> addItem(String productId, int qty) async =>
      _apply(await ApiService.addGroupCartItem(joinCode, userId, productId, qty));

  /// [qty] is the absolute new quantity for the line.
  Future<void> updateQty(String productId, int qty) async => _apply(
      await ApiService.updateGroupCartItem(joinCode, userId, productId, qty));

  Future<void> removeItem(String productId) async =>
      _apply(await ApiService.removeGroupCartItem(joinCode, userId, productId));

  /// Host only. Also drops everything that member added to the shared cart,
  /// releasing the stock those lines held — hence the product refresh.
  Future<void> removeParticipant(String participantId) async =>
      _apply(await ApiService.removeParticipant(joinCode, userId, participantId));

  /// Host only. Closes the session on success.
  Future<Order> placeOrder() async {
    final order = await ApiService.placeGroupOrder(joinCode, userId);
    try {
      _apply(await ApiService.getGroupSession(joinCode));
    } on ApiException {
      // The order succeeded; a failed refresh must not look like a failure.
    }
    return order;
  }

  /// How many units of [productId] **this device's user** has on order. The
  /// cart holds a line per member, so the stepper edits your line, not the
  /// group's running total.
  int qtyInGroupCart(String productId) =>
      _session?.myQty(productId, userId) ?? 0;

  /// What everyone has on order for [productId], for the "group has N" hint.
  int groupQtyFor(String productId) => _session?.totalQtyFor(productId) ?? 0;

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _socket.dispose(joinCode);
    super.dispose();
  }
}
