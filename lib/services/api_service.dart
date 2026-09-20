import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/app_user.dart';
import '../models/cart_item.dart';
import '../models/group_session.dart';
import '../models/hosted_group_order.dart';
import '../models/order.dart';
import '../models/product.dart';
import '../utils/config.dart';

/// A failed request, already carrying a message that is safe to show a user.
class ApiException implements Exception {
  final int statusCode; // 0 means the request never reached the server
  final String message;

  const ApiException(this.statusCode, this.message);

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// Every REST call the app makes. No widget talks to `http` directly.
///
/// The backend answers with `{"data": ...}` on success, except `POST /users`
/// (`{id, name}`) and `POST /group-sessions` (`{join_code}`). Errors are
/// `{"mssg": ...}`, `{"error": ...}` or a Zod `{"errors": [...]}` list. All of
/// that is normalised here so the rest of the app never sees those keys.
class ApiService {
  static const String _base = AppConfig.apiBaseUrl;

  // ---------------------------------------------------------------- plumbing

  static Future<dynamic> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse('$_base$path');
    final headers = {'Content-Type': 'application/json'};

    try {
      final request = switch (method) {
        'GET' => http.get(uri, headers: headers),
        'POST' => http.post(uri, headers: headers, body: jsonEncode(body ?? {})),
        'PATCH' =>
          http.patch(uri, headers: headers, body: jsonEncode(body ?? {})),
        'DELETE' => http.delete(uri, headers: headers),
        _ => throw ArgumentError('Unsupported method $method'),
      };
      final response = await request.timeout(AppConfig.requestTimeout);
      return _decode(response);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException(0, 'The server took too long to respond.');
    } on SocketException {
      throw const ApiException(
        0,
        'Cannot reach the server. Check your connection.',
      );
    } catch (_) {
      throw const ApiException(
        0,
        'Cannot reach the server. Check your connection.',
      );
    }
  }

  /// Returns the useful part of a successful body, or throws [ApiException].
  static dynamic _decode(http.Response response) {
    Map<String, dynamic> json;
    try {
      json = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException(response.statusCode, _fallbackMessage(response.statusCode));
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      // `data` when it is there, otherwise the bare body (users / join code).
      return json.containsKey('data') ? json['data'] : json;
    }

    throw ApiException(response.statusCode, _errorMessage(json, response.statusCode));
  }

  /// A backend message reads fine in `apidocs.md` but references its own
  /// implementation ("use PATCH") in a way a user has no reason to understand.
  /// Matched on the exact text rather than rewritten server-side, so the API
  /// contract stays what the docs say it is.
  static const Map<String, String> _friendlierWording = {
    'Product already in cart, use PATCH to update quantity':
        'This item is already in your cart. Use the + / − buttons to change the quantity.',
    'You already added this item, use PATCH to change your quantity':
        "You've already added this item. Use the + / − buttons to change the quantity.",
  };

  /// Picks the backend's own wording when it has any, so messages such as
  /// "Insufficient stock" reach the user unchanged. A 500 is the one
  /// exception — that status is always developer-facing, so it always gets
  /// the generic fallback instead of whatever text happened to be attached.
  static String _errorMessage(Map<String, dynamic> json, int status) {
    if (status == 500) return _fallbackMessage(status);

    final mssg = json['mssg'];
    if (mssg is String && mssg.isNotEmpty) {
      return _friendlierWording[mssg] ?? mssg;
    }

    final error = json['error'];
    if (error is String && error.isNotEmpty) {
      return _friendlierWording[error] ?? error;
    }

    final errors = json['errors'];
    if (errors is List && errors.isNotEmpty) {
      final first = errors.first;
      if (first is Map && first['message'] is String) {
        final field = (first['path'] as List?)?.join('.') ?? '';
        return field.isEmpty
            ? first['message'] as String
            : '$field: ${first['message']}';
      }
    }

    return _fallbackMessage(status);
  }

  static String _fallbackMessage(int status) => switch (status) {
        400 => 'Please check the details and try again.',
        403 => 'You are not allowed to do that.',
        404 => 'Not found.',
        409 => 'That conflicts with the current state. Please refresh.',
        500 => 'Something went wrong on the server.',
        _ => 'Something went wrong. Please try again.',
      };

  // ------------------------------------------------------------------- users

  /// `POST /api/users` — username must be at least 6 characters and unique.
  static Future<AppUser> createUser(String username) async {
    final data = await _send('POST', '/users', body: {'username': username});
    return AppUser.fromCreateJson(data as Map<String, dynamic>);
  }

  /// `GET /api/users` — the whole list.
  ///
  /// Used only by the demo "continue as an existing user" flow. The backend
  /// has no lookup-by-username endpoint, so the match happens client side.
  static Future<List<AppUser>> getUsers() async {
    final data = await _send('GET', '/users') as List<dynamic>;
    return data
        .map((u) => AppUser.fromJson(u as Map<String, dynamic>))
        .toList();
  }

  /// `GET /api/users/:id` — used to check a stored id still exists.
  static Future<AppUser> getUser(String userId) async {
    final data = await _send('GET', '/users/$userId');
    return AppUser.fromJson(data as Map<String, dynamic>);
  }

  // ---------------------------------------------------------------- products

  /// `GET /api/products`
  static Future<List<Product>> getProducts() async {
    final data = await _send('GET', '/products') as List<dynamic>;
    return data
        .map((p) => Product.fromJson(p as Map<String, dynamic>))
        .toList();
  }

  // ----------------------------------------------------------- personal cart

  /// `GET /api/users/:id/cart` — the only cart response with the product
  /// populated, so the app always re-reads the cart after a change.
  static Future<List<CartItem>> getCart(String userId) async {
    final data = await _send('GET', '/users/$userId/cart') as List<dynamic>;
    return data
        .map((c) => CartItem.fromJson(c as Map<String, dynamic>))
        .toList();
  }

  /// `POST /api/users/:id/cart` — reserves stock immediately.
  static Future<void> addToCart(String userId, String productId, int qty) =>
      _send('POST', '/users/$userId/cart',
          body: {'productId': productId, 'qty': qty});

  /// `PATCH /api/users/:id/cart/:productId` — [qty] is the absolute new
  /// quantity, not a delta. The server reserves or releases the difference.
  static Future<void> updateCartItem(
    String userId,
    String productId,
    int qty,
  ) =>
      _send('PATCH', '/users/$userId/cart/$productId', body: {'qty': qty});

  /// `DELETE /api/users/:id/cart/:productId` — releases the reserved stock.
  static Future<void> removeCartItem(String userId, String productId) =>
      _send('DELETE', '/users/$userId/cart/$productId');

  // --------------------------------------------------------------- my orders

  /// `POST /api/users/:id/orders` — no body; built from the current cart.
  static Future<Order> placeOrder(String userId) async {
    final data = await _send('POST', '/users/$userId/orders');
    return Order.fromJson(data as Map<String, dynamic>);
  }

  /// `GET /api/users/:id/orders` — newest first, normal and group orders.
  static Future<List<Order>> getOrders(String userId) async {
    final data = await _send('GET', '/users/$userId/orders') as List<dynamic>;
    return data.map((o) => Order.fromJson(o as Map<String, dynamic>)).toList();
  }

  /// `GET /api/users/:id/group-orders` — only the group orders this user
  /// **hosted**, each with a breakdown of what every member owes. Sessions the
  /// user merely joined stay in [getOrders].
  static Future<List<HostedGroupOrder>> getHostedGroupOrders(
      String userId) async {
    final data =
        await _send('GET', '/users/$userId/group-orders') as List<dynamic>;
    return data
        .map((o) => HostedGroupOrder.fromJson(o as Map<String, dynamic>))
        .toList();
  }

  // ---------------------------------------------------------- group sessions

  /// `POST /api/group-sessions` — the caller becomes the host. Returns the
  /// join code. [displayName] is optional; the backend falls back to the
  /// username when it is omitted.
  static Future<String> createGroupSession(
    String userId, {
    String? displayName,
  }) async {
    final data = await _send('POST', '/group-sessions', body: {
      'userId': userId,
      if (displayName != null && displayName.isNotEmpty)
        'display_name': displayName,
    });
    return (data as Map<String, dynamic>)['join_code'] as String;
  }

  /// `GET /api/group-sessions/:code` — works for closed sessions too.
  static Future<GroupSession> getGroupSession(String joinCode) async {
    final data = await _send('GET', '/group-sessions/$joinCode');
    return GroupSession.fromJson(data as Map<String, dynamic>);
  }

  /// `POST /api/group-sessions/:code/join`
  static Future<GroupSession> joinGroupSession(
    String joinCode,
    String userId,
    String displayName,
  ) async {
    final data = await _send('POST', '/group-sessions/$joinCode/join',
        body: {'userId': userId, 'display_name': displayName});
    return GroupSession.fromJson(data as Map<String, dynamic>);
  }

  /// `PATCH /api/group-sessions/:code/participants/:userId/ready`
  static Future<GroupSession> setReady(
    String joinCode,
    String userId,
    bool ready,
  ) async {
    final data = await _send(
      'PATCH',
      '/group-sessions/$joinCode/participants/$userId/ready',
      body: {'ready': ready},
    );
    return GroupSession.fromJson(data as Map<String, dynamic>);
  }

  /// `DELETE /api/group-sessions/:code/participants/:participantId?userId=`
  /// Host only. Also drops everything that member added to the shared cart and
  /// releases the stock those lines were holding.
  static Future<GroupSession> removeParticipant(
    String joinCode,
    String hostId,
    String participantId,
  ) async {
    final data = await _send(
      'DELETE',
      '/group-sessions/$joinCode/participants/$participantId?userId=$hostId',
    );
    return GroupSession.fromJson(data as Map<String, dynamic>);
  }

  // --------------------------------------------------------------- group cart
  // Every group cart call answers with the full group state, so no follow-up
  // GET is needed. The caller's id travels in the body, or the query string
  // for DELETE, because the URL has no :userId segment.

  static Future<GroupSession> addGroupCartItem(
    String joinCode,
    String userId,
    String productId,
    int qty,
  ) async {
    final data = await _send('POST', '/group-sessions/$joinCode/cart',
        body: {'userId': userId, 'productId': productId, 'qty': qty});
    return GroupSession.fromJson(data as Map<String, dynamic>);
  }

  static Future<GroupSession> updateGroupCartItem(
    String joinCode,
    String userId,
    String productId,
    int qty,
  ) async {
    final data = await _send('PATCH', '/group-sessions/$joinCode/cart/$productId',
        body: {'userId': userId, 'qty': qty});
    return GroupSession.fromJson(data as Map<String, dynamic>);
  }

  static Future<GroupSession> removeGroupCartItem(
    String joinCode,
    String userId,
    String productId,
  ) async {
    final data = await _send(
      'DELETE',
      '/group-sessions/$joinCode/cart/$productId?userId=$userId',
    );
    return GroupSession.fromJson(data as Map<String, dynamic>);
  }

  /// `POST /api/group-sessions/:code/order` — host only, and only once every
  /// participant is ready. Closes the session.
  static Future<Order> placeGroupOrder(String joinCode, String userId) async {
    final data = await _send('POST', '/group-sessions/$joinCode/order',
        body: {'userId': userId});
    return Order.fromJson(data as Map<String, dynamic>);
  }
}
