/// One line of a placed order — a snapshot, so name and price stay correct
/// even if the product changes later.
class OrderLine {
  final String name;
  final int price;
  final int qty;

  /// Who put this line in the shared cart. Group orders only — normal orders
  /// have one person, and orders placed before attribution existed have none.
  final String? addedByName;

  const OrderLine({
    required this.name,
    required this.price,
    required this.qty,
    this.addedByName,
  });

  factory OrderLine.fromJson(Map<String, dynamic> json) => OrderLine(
        name: json['name'] as String? ?? 'Item',
        price: (json['price'] as num?)?.toInt() ?? 0,
        qty: (json['qty'] as num?)?.toInt() ?? 0,
        addedByName: json['added_by_name'] as String?,
      );

  int get lineTotal => price * qty;
}

class Order {
  final String id;
  final DateTime? orderDate;
  final int orderAmt;
  final String orderStatus;
  final String orderType; // "normal" or "group"
  final List<OrderLine> products;

  const Order({
    required this.id,
    required this.orderDate,
    required this.orderAmt,
    required this.orderStatus,
    required this.orderType,
    required this.products,
  });

  factory Order.fromJson(Map<String, dynamic> json) => Order(
        id: json['_id'] as String,
        orderDate: DateTime.tryParse(json['order_date'] as String? ?? ''),
        orderAmt: (json['order_amt'] as num?)?.toInt() ?? 0,
        orderStatus: json['order_status'] as String? ?? 'placed',
        orderType: json['order_type'] as String? ?? 'normal',
        products: (json['products'] as List<dynamic>? ?? [])
            .map((p) => OrderLine.fromJson(p as Map<String, dynamic>))
            .toList(),
      );

  bool get isGroup => orderType == 'group';

  int get itemCount => products.fold(0, (sum, p) => sum + p.qty);
}
