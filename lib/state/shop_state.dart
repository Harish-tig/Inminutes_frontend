import 'package:flutter/foundation.dart';

import '../models/cart_item.dart';
import '../models/order.dart';
import '../models/product.dart';
import '../services/api_service.dart';

/// Products and the personal cart.
///
/// They live together because they move together: adding to the cart reserves
/// stock, so every cart change also changes what the product list should show.
///
/// Cart changes are applied **optimistically**. The old version waited for the
/// write and then two more reads before the card redrew, which read as lag on
/// every tap. Now the local copy changes immediately, the request follows, and
/// a failure puts the previous state back.
class ShopState extends ChangeNotifier {
  List<Product> _products = [];
  List<CartItem> _cart = [];
  bool _loadingProducts = false;
  bool _loadingCart = false;
  String? _productsError;

  /// Bumped on every cart change so a slow reconcile can never overwrite a
  /// newer one. Without it, tapping + three times quickly could end with the
  /// first response deciding the final state.
  int _seq = 0;

  /// The most recent write request sent for each product. A second tap's
  /// optimistic update still shows instantly, but its actual network call
  /// waits for this, so — for example — a PATCH can never reach the server
  /// before the POST that creates the line it is trying to change.
  final Map<String, Future<void>> _pendingRequest = {};

  List<Product> get products => _products;
  List<CartItem> get cart => _cart;
  bool get loadingProducts => _loadingProducts;
  bool get loadingCart => _loadingCart;
  String? get productsError => _productsError;

  int get cartItemCount => _cart.fold(0, (sum, item) => sum + item.qty);
  int get cartTotal => _cart.fold(0, (sum, item) => sum + item.lineTotal);

  /// How many units of [productId] the user already has in their cart.
  int qtyInCart(String productId) {
    for (final item in _cart) {
      if (item.product.id == productId) return item.qty;
    }
    return 0;
  }

  Product? _productById(String id) {
    for (final p in _products) {
      if (p.id == id) return p;
    }
    return null;
  }

  // ------------------------------------------------------------------ loads

  Future<void> loadProducts({bool showSpinner = true}) async {
    if (showSpinner) {
      _loadingProducts = true;
      _productsError = null;
      notifyListeners();
    }
    try {
      _products = await ApiService.getProducts();
      _productsError = null;
    } on ApiException catch (e) {
      _productsError = e.message;
    } finally {
      _loadingProducts = false;
      notifyListeners();
    }
  }

  Future<void> loadCart(String userId, {bool showSpinner = true}) async {
    if (showSpinner) {
      _loadingCart = true;
      notifyListeners();
    }
    try {
      _cart = await ApiService.getCart(userId);
    } finally {
      _loadingCart = false;
      notifyListeners();
    }
  }

  /// Loads both — used on first paint and by pull-to-refresh.
  Future<void> refreshAll(String userId) async {
    await Future.wait([
      loadProducts(showSpinner: false),
      loadCart(userId, showSpinner: false),
    ]);
  }

  // -------------------------------------------------------------- mutations

  /// Shared shape for every cart change: show it, send it, put it back if the
  /// server disagrees, then quietly reconcile with what the server actually
  /// has.
  Future<void> _mutate({
    required String userId,
    required String productId,
    required void Function() optimistic,
    required Future<void> Function() request,
  }) async {
    final previousProducts = _products;
    final previousCart = _cart;
    final mySeq = ++_seq;

    optimistic();
    notifyListeners();

    try {
      await _sendAfterPending(productId, request);
    } catch (_) {
      // Only roll back if nothing newer has happened since.
      if (mySeq == _seq) {
        _products = previousProducts;
        _cart = previousCart;
        notifyListeners();
      }
      rethrow;
    }

    // The server is authoritative — another device may have moved stock — but
    // a stale reply must never clobber a newer local change.
    final results = await Future.wait([
      ApiService.getProducts(),
      ApiService.getCart(userId),
    ]);
    if (mySeq == _seq) {
      _products = results[0] as List<Product>;
      _cart = results[1] as List<CartItem>;
      notifyListeners();
    }
  }

  /// Runs [request] only after whatever was already in flight for
  /// [productId] has settled, so two taps in the same frame still send their
  /// real network calls in the order they happened — the optimistic update
  /// above already made the UI show that order instantly.
  Future<void> _sendAfterPending(
    String productId,
    Future<void> Function() request,
  ) {
    final previous = _pendingRequest[productId] ?? Future<void>.value();
    final chained = previous.catchError((_) {}).then((_) => request());
    // Whoever taps next waits for this one too, regardless of how it ends.
    _pendingRequest[productId] = chained.catchError((_) {});
    return chained;
  }

  /// Moves [delta] units out of available stock (negative puts them back).
  void _reserveLocally(String productId, int delta) {
    final product = _productById(productId);
    if (product == null) return;
    _products = [
      for (final p in _products)
        if (p.id == productId) p.withQty(p.qty - delta) else p,
    ];
  }

  Future<void> addToCart(String userId, String productId, int qty) {
    // Already in the cart — a fast double-tap can fire this before the ADD
    // button has swapped for the stepper. Bump the existing line instead of
    // sending a second POST, which the backend would reject as a duplicate
    // (and whose rejection text talks about PATCH, meaningless to a user).
    final existingQty = qtyInCart(productId);
    if (existingQty > 0) {
      return updateCartQty(userId, productId, existingQty + qty);
    }

    final product = _productById(productId);
    return _mutate(
      userId: userId,
      productId: productId,
      optimistic: () {
        if (product == null) return;
        _reserveLocally(productId, qty);
        final updated = _productById(productId) ?? product;
        _cart = [..._cart, CartItem(product: updated, qty: qty)];
      },
      request: () => ApiService.addToCart(userId, productId, qty),
    );
  }

  /// [qty] is the absolute new quantity the line should have.
  Future<void> updateCartQty(String userId, String productId, int qty) {
    final current = qtyInCart(productId);
    return _mutate(
      userId: userId,
      productId: productId,
      optimistic: () {
        _reserveLocally(productId, qty - current);
        final updated = _productById(productId);
        _cart = [
          for (final item in _cart)
            if (item.product.id == productId)
              CartItem(product: updated ?? item.product, qty: qty)
            else
              item,
        ];
      },
      request: () => ApiService.updateCartItem(userId, productId, qty),
    );
  }

  Future<void> removeFromCart(String userId, String productId) {
    final current = qtyInCart(productId);
    return _mutate(
      userId: userId,
      productId: productId,
      optimistic: () {
        _reserveLocally(productId, -current);
        _cart = [
          for (final item in _cart)
            if (item.product.id != productId) item,
        ];
      },
      request: () => ApiService.removeCartItem(userId, productId),
    );
  }

  /// Checkout does not change stock — it turns the already-reserved cart into
  /// an order — so only the cart is cleared here.
  Future<Order> placeOrder(String userId) async {
    final order = await ApiService.placeOrder(userId);
    _seq++;
    _cart = [];
    notifyListeners();
    await refreshAll(userId);
    return order;
  }

  /// Clears local data when the user is switched.
  void clear() {
    _seq++;
    _products = [];
    _cart = [];
    notifyListeners();
  }
}
