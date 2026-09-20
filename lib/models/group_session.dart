import 'cart_item.dart';
import 'participant.dart';

/// One member's share of the shared cart.
class MemberCart {
  final String userId;
  final String displayName;
  final List<GroupCartItem> items;

  const MemberCart({
    required this.userId,
    required this.displayName,
    required this.items,
  });

  int get total => items.fold(0, (sum, item) => sum + item.lineTotal);
  int get unitCount => items.fold(0, (sum, item) => sum + item.qty);
}

class GroupSession {
  final String joinCode;
  final bool active;
  final String hostId;
  final String hostName;

  /// What the host chose to be called in this session. Falls back to their
  /// username, which is what the backend does too.
  final String hostDisplayName;
  final List<Participant> participants;
  final List<GroupCartItem> cart;

  const GroupSession({
    required this.joinCode,
    required this.active,
    required this.hostId,
    required this.hostName,
    required this.hostDisplayName,
    required this.participants,
    required this.cart,
  });

  factory GroupSession.fromJson(Map<String, dynamic> json) {
    // `host` is `{user: {...}, display_name}`. Older responses put the user
    // fields directly on `host`, so fall back to that shape.
    final host = json['host'] as Map<String, dynamic>?;
    final hostUser = host?['user'] as Map<String, dynamic>? ?? host;
    final hostName = hostUser?['username'] as String? ?? '';

    return GroupSession(
      joinCode: json['join_code'] as String,
      active: json['active'] as bool? ?? false,
      hostId: hostUser?['_id'] as String? ?? '',
      hostName: hostName,
      hostDisplayName: host?['display_name'] as String? ?? hostName,
      participants: (json['participants'] as List<dynamic>? ?? [])
          .map((p) => Participant.fromJson(p as Map<String, dynamic>))
          .toList(),
      cart: (json['cart'] as List<dynamic>? ?? [])
          .map((c) => GroupCartItem.fromJson(c as Map<String, dynamic>))
          .toList(),
    );
  }

  int get total => cart.fold(0, (sum, item) => sum + item.lineTotal);

  /// Units on order across the whole group. Not `cart.length` — that counts
  /// lines, and the same dish has one line per member who ordered it.
  int get unitCount => cart.fold(0, (sum, item) => sum + item.qty);

  /// How many units of [productId] **this** user has on order. The cart holds
  /// one line per product per member, so this is the caller's own line only.
  int myQty(String productId, String userId) {
    for (final item in cart) {
      if (item.product.id == productId && item.addedById == userId) {
        return item.qty;
      }
    }
    return 0;
  }

  /// Units of [productId] the whole group has on order, across every member.
  int totalQtyFor(String productId) => cart
      .where((item) => item.product.id == productId)
      .fold(0, (sum, item) => sum + item.qty);

  /// The shared cart split into one basket per member, host first and then
  /// participants in join order. Members who added nothing are left out —
  /// the participants list above already shows they are here.
  List<MemberCart> get cartByMember {
    final order = <String, String>{
      if (hostId.isNotEmpty) hostId: hostDisplayName,
      for (final p in participants) p.userId: p.displayName,
    };

    final baskets = <MemberCart>[];
    for (final entry in order.entries) {
      final items =
          cart.where((item) => item.addedById == entry.key).toList();
      if (items.isNotEmpty) {
        baskets.add(MemberCart(
          userId: entry.key,
          displayName: entry.value,
          items: items,
        ));
      }
    }

    // Anything left over belongs to someone no longer in the session. It
    // should not happen — removing a member drops their lines — but dropping
    // it silently would make the baskets stop adding up to the total.
    final claimed = baskets.expand((b) => b.items).toSet();
    final orphans = cart.where((item) => !claimed.contains(item)).toList();
    if (orphans.isNotEmpty) {
      baskets.add(MemberCart(
        userId: '',
        displayName: 'Former member',
        items: orphans,
      ));
    }

    return baskets;
  }

  bool isHost(String userId) => hostId == userId;

  bool isParticipant(String userId) =>
      participants.any((p) => p.userId == userId);

  /// Host or participant — the backend lets either one change the shared cart.
  bool isMember(String userId) => isHost(userId) || isParticipant(userId);

  /// What this session calls [userId] — their display name, so the shared cart
  /// matches the participants list instead of showing raw usernames.
  /// Falls back to [fallback] for someone no longer in the session.
  String displayNameFor(String userId, {String fallback = ''}) {
    if (userId == hostId) return hostDisplayName;
    final participant = participantFor(userId);
    if (participant != null) return participant.displayName;
    return fallback;
  }

  Participant? participantFor(String userId) {
    for (final p in participants) {
      if (p.userId == userId) return p;
    }
    return null;
  }

  /// Mirrors the backend's checkout rules so the button state matches what the
  /// server would actually accept. The server still decides — this only avoids
  /// offering a tap that is guaranteed to fail.
  bool get canPlaceOrder =>
      active &&
      participants.isNotEmpty &&
      cart.isNotEmpty &&
      participants.every((p) => p.ready);
}
