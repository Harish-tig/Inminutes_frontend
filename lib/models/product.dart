/// A menu item.
///
/// [qty] is stock **still available to reserve** — it drops as soon as anyone
/// puts the item in a cart, not at checkout. [instock] is always `qty > 0`.
class Product {
  final String id;
  final String name;
  final int price;
  final int qty;
  final bool instock;

  /// `[thumbnail, full size]` from the backend's media store. Empty when the
  /// backend has no media storage configured, so the UI must cope without it.
  final List<String> imageUrls;

  const Product({
    required this.id,
    required this.name,
    required this.price,
    required this.qty,
    required this.instock,
    this.imageUrls = const [],
  });

  factory Product.fromJson(Map<String, dynamic> json) => Product(
        id: json['_id'] as String,
        name: json['name'] as String,
        price: (json['price'] as num).toInt(),
        qty: (json['qty'] as num).toInt(),
        instock: json['instock'] as bool? ?? (json['qty'] as num) > 0,
        imageUrls: (json['image_urls'] as List<dynamic>? ?? [])
            .whereType<String>()
            .toList(),
      );

  /// The image a list or grid should show, or null to fall back to an icon.
  String? get thumbnailUrl => imageUrls.isEmpty ? null : imageUrls.first;

  /// Used for optimistic stock changes. [instock] is derived, never passed in,
  /// so it cannot drift away from `qty > 0`.
  Product withQty(int newQty) {
    final clamped = newQty < 0 ? 0 : newQty;
    return Product(
      id: id,
      name: name,
      price: price,
      qty: clamped,
      instock: clamped > 0,
      imageUrls: imageUrls,
    );
  }
}
