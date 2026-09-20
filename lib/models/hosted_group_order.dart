// Models for `GET /api/users/:userId/group-orders` — the log of group orders a
// user hosted, with a per-person breakdown of who owes what.

/// Someone in the session, with the name they used at the time.
class GroupMember {
  final String userId;
  final String username;
  final String displayName;

  const GroupMember({
    required this.userId,
    required this.username,
    required this.displayName,
  });

  /// `{user: {_id, username}, display_name}`. Orders placed before per-line
  /// attribution existed can have a null user, so the caller gets a blank id.
  factory GroupMember.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>?;
    return GroupMember(
      userId: user?['_id'] as String? ?? '',
      username: user?['username'] as String? ?? '',
      displayName: json['display_name'] as String? ?? 'Unattributed',
    );
  }
}

/// One ordered line, with the pre-computed total and who added it.
class HostedOrderLine {
  final String name;
  final int price;
  final int qty;
  final int lineAmt;
  final String addedByName;

  const HostedOrderLine({
    required this.name,
    required this.price,
    required this.qty,
    required this.lineAmt,
    required this.addedByName,
  });

  factory HostedOrderLine.fromJson(Map<String, dynamic> json) =>
      HostedOrderLine(
        name: json['name'] as String? ?? 'Item',
        price: (json['price'] as num?)?.toInt() ?? 0,
        qty: (json['qty'] as num?)?.toInt() ?? 0,
        lineAmt: (json['line_amt'] as num?)?.toInt() ?? 0,
        addedByName: json['added_by_name'] as String? ?? 'Unattributed',
      );
}

/// What one person owes for this order.
class BreakdownRow {
  final String displayName;
  final int lines;
  final int qty;
  final int amount;

  const BreakdownRow({
    required this.displayName,
    required this.lines,
    required this.qty,
    required this.amount,
  });

  factory BreakdownRow.fromJson(Map<String, dynamic> json) => BreakdownRow(
        displayName: json['display_name'] as String? ?? 'Unattributed',
        lines: (json['lines'] as num?)?.toInt() ?? 0,
        qty: (json['qty'] as num?)?.toInt() ?? 0,
        amount: (json['amount'] as num?)?.toInt() ?? 0,
      );

  bool get orderedNothing => qty == 0;
}

class HostedGroupOrder {
  final String id;
  final DateTime? orderDate;
  final int orderAmt;
  final String orderStatus;
  final String joinCode;
  final GroupMember? host;
  final List<GroupMember> members;
  final List<HostedOrderLine> products;
  final List<BreakdownRow> breakdown;

  const HostedGroupOrder({
    required this.id,
    required this.orderDate,
    required this.orderAmt,
    required this.orderStatus,
    required this.joinCode,
    required this.host,
    required this.members,
    required this.products,
    required this.breakdown,
  });

  factory HostedGroupOrder.fromJson(Map<String, dynamic> json) {
    final host = json['host'] as Map<String, dynamic>?;
    return HostedGroupOrder(
      id: json['_id'] as String,
      orderDate: DateTime.tryParse(json['order_date'] as String? ?? ''),
      orderAmt: (json['order_amt'] as num?)?.toInt() ?? 0,
      orderStatus: json['order_status'] as String? ?? 'placed',
      // Orders from before the session was recorded have no join code.
      joinCode: json['join_code'] as String? ?? '',
      host: host == null ? null : GroupMember.fromJson(host),
      members: (json['members'] as List<dynamic>? ?? [])
          .map((m) => GroupMember.fromJson(m as Map<String, dynamic>))
          .toList(),
      products: (json['products'] as List<dynamic>? ?? [])
          .map((p) => HostedOrderLine.fromJson(p as Map<String, dynamic>))
          .toList(),
      breakdown: (json['breakdown'] as List<dynamic>? ?? [])
          .map((b) => BreakdownRow.fromJson(b as Map<String, dynamic>))
          .toList(),
    );
  }

  int get itemCount => products.fold(0, (sum, p) => sum + p.qty);

  /// People counted in the split, including those who ordered nothing.
  int get peopleCount => breakdown.length;
}
