import 'product.dart';

/// A line in the personal cart, from `GET /api/users/:id/cart`.
///
/// [qty] is how many units are in the cart; `product.qty` is how much stock is
/// still available to add. They are different numbers — never add them.
class CartItem {
  final Product product;
  final int qty;

  const CartItem({required this.product, required this.qty});

  factory CartItem.fromJson(Map<String, dynamic> json) => CartItem(
        product: Product.fromJson(json['product'] as Map<String, dynamic>),
        qty: (json['qty'] as num).toInt(),
      );

  int get lineTotal => product.price * qty;
}

/// A line in the shared group cart, from the `group:state` payload.
/// [addedByName] is whoever last changed this line.
class GroupCartItem {
  final Product product;
  final int qty;
  final String addedById;
  final String addedByName;

  const GroupCartItem({
    required this.product,
    required this.qty,
    required this.addedById,
    required this.addedByName,
  });

  factory GroupCartItem.fromJson(Map<String, dynamic> json) {
    final addedBy = json['added_by'] as Map<String, dynamic>?;
    return GroupCartItem(
      product: Product.fromJson(json['product'] as Map<String, dynamic>),
      qty: (json['qty'] as num).toInt(),
      addedById: addedBy?['_id'] as String? ?? '',
      addedByName: addedBy?['username'] as String? ?? 'Unknown',
    );
  }

  int get lineTotal => product.price * qty;
}
