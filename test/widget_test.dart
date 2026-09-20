// Widget-level checks that need no backend: first-run routing, stock states on
// the product card, and the host checkout gate.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:inminutes/main.dart';
import 'package:inminutes/models/cart_item.dart';
import 'package:inminutes/models/group_session.dart';
import 'package:inminutes/models/hosted_group_order.dart';
import 'package:inminutes/models/participant.dart';
import 'package:inminutes/models/product.dart';
import 'package:inminutes/utils/app_theme.dart';
import 'package:inminutes/widgets/group_cart_tile.dart';
import 'package:inminutes/widgets/product_card.dart';
import 'package:inminutes/widgets/qty_stepper.dart';
import 'package:inminutes/widgets/tapered_button.dart';

Product product({int qty = 10}) =>
    Product(id: 'p1', name: 'Veg Burger', price: 99, qty: qty, instock: qty > 0);

Widget wrap(Widget child) => MaterialApp(
      theme: AppTheme.build(),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('first run shows the create-user screen, not a login',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const InMinutesApp());
    await tester.pumpAndSettle();

    expect(find.text('GET STARTED'), findsOneWidget);
    expect(find.text('Choose a username'), findsOneWidget);
    expect(find.textContaining('Password'), findsNothing);
  });

  testWidgets('username shorter than 6 characters is rejected inline',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const InMinutesApp());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'abc');
    await tester.tap(find.text('GET STARTED'));
    await tester.pump();

    expect(find.text('Username must be at least 6 characters'), findsOneWidget);
  });

  testWidgets('the create/continue toggle changes what is required',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const InMinutesApp());
    await tester.pumpAndSettle();

    // Creating has to satisfy the backend's 6-character rule.
    expect(find.text('GET STARTED'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'abc');
    await tester.tap(find.text('GET STARTED'));
    await tester.pump();
    expect(find.text('Username must be at least 6 characters'), findsOneWidget);

    // Continuing as an existing user does not — the name already exists, and
    // rejecting it locally would lock people out of their own account.
    await tester.tap(find.text('I have one'));
    await tester.pumpAndSettle();
    expect(find.text('CONTINUE'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'abc');
    expect(find.text('Username must be at least 6 characters'), findsNothing);
  });

  test('optimistic stock changes never let a product go negative', () {
    final p = Product(
        id: 'p1', name: 'Veg Burger', price: 99, qty: 2, instock: true);

    expect(p.withQty(0).instock, isFalse);
    expect(p.withQty(5).instock, isTrue);
    // A rollback race could ask for a negative; clamp rather than propagate it.
    expect(p.withQty(-3).qty, 0);
    expect(p.withQty(-3).instock, isFalse);
    // Everything else is carried over untouched.
    expect(p.withQty(7).name, 'Veg Burger');
    expect(p.withQty(7).price, 99);
  });

  testWidgets('product card shows ADD, then a stepper once in the cart',
      (tester) async {
    await tester.pumpWidget(wrap(
      ProductCard(product: product(), qtyInCart: 0, onAdd: () {}),
    ));
    expect(find.text('ADD'), findsOneWidget);
    expect(find.text('10 AVAILABLE'), findsOneWidget);
    expect(find.text('VEG BURGER'), findsOneWidget);

    await tester.pumpWidget(wrap(
      ProductCard(product: product(qty: 8), qtyInCart: 2, onIncrease: () {}),
    ));
    expect(find.text('ADD'), findsNothing);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('out of stock shows a disabled NO STOCK button', (tester) async {
    await tester.pumpWidget(wrap(
      ProductCard(product: product(qty: 0), qtyInCart: 0, onAdd: () {}),
    ));

    expect(find.text('NO STOCK'), findsOneWidget);
    expect(find.text('ADD'), findsNothing);
    final button = tester.widget<TaperedButton>(find.byType(TaperedButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('an item already in the cart stays editable at zero stock',
      (tester) async {
    // cart qty and product qty are different numbers — this is the trap the
    // backend docs call out.
    await tester.pumpWidget(wrap(
      ProductCard(product: product(qty: 0), qtyInCart: 3, onDecrease: () {}),
    ));

    expect(find.text('NO STOCK'), findsNothing);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('OUT OF STOCK'), findsOneWidget);
  });

  test('group state parses the nested host shape the backend sends', () {
    // The backend wraps the host as {user: {...}, display_name}. Reading
    // host['_id'] directly gives an empty id, which silently breaks isHost —
    // and therefore the host's checkout button and re-entry.
    final session = GroupSession.fromJson({
      'join_code': 'ABCD1234',
      'active': true,
      'host': {
        'user': {'_id': 'h1', 'username': 'alice01'},
        'display_name': 'Alice',
      },
      'participants': [
        {
          'user': {'_id': 'u1', 'username': 'bobbob1'},
          'display_name': 'Bob',
          'ready': true,
        }
      ],
      'cart': [],
    });

    expect(session.hostId, 'h1');
    expect(session.hostName, 'alice01');
    expect(session.hostDisplayName, 'Alice');
    expect(session.isHost('h1'), isTrue);

    // Re-entry hinges on this: both the host and a returning participant are
    // members, so the entry screen must open the session instead of joining.
    expect(session.isMember('h1'), isTrue);
    expect(session.isMember('u1'), isTrue);
    expect(session.isMember('stranger'), isFalse);

    // The shared cart must name people the way the participants list does.
    expect(session.displayNameFor('h1'), 'Alice');
    expect(session.displayNameFor('u1'), 'Bob');
    expect(session.displayNameFor('gone', fallback: 'olduser'), 'olduser');
  });

  test('product parses image_urls and falls back when there are none', () {
    final withImages = Product.fromJson({
      '_id': 'p1',
      'name': 'Veg Burger',
      'price': 99,
      'qty': 10,
      'instock': true,
      'image_urls': ['https://cdn.example/thumb.jpg', 'https://cdn.example/full.jpg'],
    });
    expect(withImages.thumbnailUrl, 'https://cdn.example/thumb.jpg');

    final without = Product.fromJson({
      '_id': 'p2',
      'name': 'Veg Burger',
      'price': 99,
      'qty': 10,
      'instock': true,
    });
    expect(without.imageUrls, isEmpty);
    expect(without.thumbnailUrl, isNull);
  });

  test('hosted group order parses, and its breakdown sums to the total', () {
    final order = HostedGroupOrder.fromJson({
      '_id': 'o1',
      'order_date': '2026-09-20T00:28:39.860Z',
      'order_amt': 597,
      'order_status': 'placed',
      'join_code': 'JAB8RZ3A',
      'host': {
        'user': {'_id': 'h1', 'username': 'alice01'},
        'display_name': 'Alice',
      },
      'members': [
        {
          'user': {'_id': 'u1', 'username': 'bobbob1'},
          'display_name': 'Bob',
        },
      ],
      'products': [
        {
          'name': 'Margherita Pizza',
          'price': 249,
          'qty': 2,
          'line_amt': 498,
          'added_by_name': 'Bob',
        },
        {
          'name': 'Veg Burger',
          'price': 99,
          'qty': 1,
          'line_amt': 99,
          'added_by_name': 'Alice',
        },
      ],
      'breakdown': [
        {'display_name': 'Alice', 'lines': 1, 'qty': 1, 'amount': 99},
        {'display_name': 'Bob', 'lines': 1, 'qty': 2, 'amount': 498},
        {'display_name': 'Carol', 'lines': 0, 'qty': 0, 'amount': 0},
      ],
    });

    expect(order.joinCode, 'JAB8RZ3A');
    expect(order.host?.displayName, 'Alice');
    expect(order.itemCount, 3);
    expect(order.peopleCount, 3);
    expect(order.products.first.addedByName, 'Bob');

    // Someone who ordered nothing still appears, so nobody vanishes from the
    // split, and the rows must still add up to the order total.
    expect(order.breakdown.last.orderedNothing, isTrue);
    expect(
      order.breakdown.fold<int>(0, (sum, r) => sum + r.amount),
      order.orderAmt,
    );
  });

  test('a legacy order with no attribution still parses', () {
    // Orders placed before per-line attribution existed have no join_code,
    // host, members or added_by. They must not blow up the log.
    final order = HostedGroupOrder.fromJson({
      '_id': 'o2',
      'order_amt': 150,
      'products': [
        {'name': 'Veg Burger', 'price': 150, 'qty': 1, 'line_amt': 150}
      ],
      'breakdown': [
        {'user': null, 'display_name': null, 'lines': 1, 'qty': 1, 'amount': 150}
      ],
    });

    expect(order.joinCode, isEmpty);
    expect(order.host, isNull);
    expect(order.products.first.addedByName, 'Unattributed');
    expect(order.breakdown.single.displayName, 'Unattributed');
    expect(order.breakdown.single.amount, order.orderAmt);
  });

  test('two members ordering the same dish keep separate lines', () {
    // The exact case that used to collapse into one line owned by whoever
    // added it first: Alice wants 2 pizzas, Bob wants 2 more.
    final session = GroupSession.fromJson({
      'join_code': 'ABCD1234',
      'active': true,
      'host': {
        'user': {'_id': 'h1', 'username': 'alice01'},
        'display_name': 'Alice',
      },
      'participants': [
        {
          'user': {'_id': 'u1', 'username': 'bobbob1'},
          'display_name': 'Bob',
          'ready': true,
        },
        {
          'user': {'_id': 'u2', 'username': 'carol01'},
          'display_name': 'Carol',
          'ready': false,
        },
      ],
      'cart': [
        {
          'product': {
            '_id': 'p1', 'name': 'Margherita Pizza',
            'price': 100, 'qty': 5, 'instock': true,
          },
          'qty': 2,
          'added_by': {'_id': 'h1', 'username': 'alice01'},
        },
        {
          'product': {
            '_id': 'p1', 'name': 'Margherita Pizza',
            'price': 100, 'qty': 5, 'instock': true,
          },
          'qty': 2,
          'added_by': {'_id': 'u1', 'username': 'bobbob1'},
        },
      ],
    });

    // Four pizzas on order, but neither person "owns" all four.
    expect(session.totalQtyFor('p1'), 4);
    expect(session.myQty('p1', 'h1'), 2);
    expect(session.myQty('p1', 'u1'), 2);
    expect(session.myQty('p1', 'u2'), 0);

    // Split into baskets: host first, then participants in join order.
    final baskets = session.cartByMember;
    expect(baskets.length, 2, reason: 'Carol added nothing, so no basket');
    expect(baskets.first.displayName, 'Alice');
    expect(baskets.first.unitCount, 2);
    expect(baskets.first.total, 200);
    expect(baskets.last.displayName, 'Bob');
    expect(baskets.last.total, 200);

    // The baskets must account for the whole cart.
    expect(baskets.fold<int>(0, (sum, b) => sum + b.total), session.total);
    expect(session.total, 400);

    // Four units on order, across two lines — counting lines would say 2.
    expect(session.unitCount, 4);
    expect(session.cart.length, 2);
  });

  testWidgets('you cannot edit a line somebody else added', (tester) async {
    final line = GroupCartItem(
      product: product(),
      qty: 2,
      addedById: 'someone-else',
      addedByName: 'bobbob1',
    );

    // Your own line: the stepper and the remove button are there.
    await tester.pumpWidget(wrap(GroupCartTile(
      item: line,
      addedByName: 'Bob',
      editable: true,
      onIncrease: () {},
      onDecrease: () {},
      onRemove: () {},
    )));
    expect(find.byType(QtyStepper), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);

    // Somebody else's line: read-only, matching what the backend now enforces.
    await tester.pumpWidget(wrap(GroupCartTile(
      item: line,
      addedByName: 'Bob',
      editable: false,
      onIncrease: () {},
      onDecrease: () {},
      onRemove: () {},
    )));
    expect(find.byType(QtyStepper), findsNothing);
    expect(find.byIcon(Icons.close), findsNothing);
    expect(find.text('VEG BURGER'), findsOneWidget);
  });

  test('a line from someone no longer in the session still adds up', () {
    final session = GroupSession.fromJson({
      'join_code': 'ABCD1234',
      'active': true,
      'host': {
        'user': {'_id': 'h1', 'username': 'alice01'},
        'display_name': 'Alice',
      },
      'participants': [],
      'cart': [
        {
          'product': {
            '_id': 'p1', 'name': 'Veg Burger',
            'price': 99, 'qty': 5, 'instock': true,
          },
          'qty': 1,
          'added_by': {'_id': 'ghost', 'username': 'gone01'},
        },
      ],
    });

    final baskets = session.cartByMember;
    expect(baskets.single.displayName, 'Former member');
    expect(baskets.fold<int>(0, (sum, b) => sum + b.total), session.total);
  });

  test('host checkout is gated exactly like the backend gates it', () {
    GroupSession session({
      bool active = true,
      List<Participant> participants = const [],
      List<GroupCartItem> cart = const [],
    }) =>
        GroupSession(
          joinCode: 'ABCD1234',
          active: active,
          hostId: 'h1',
          hostName: 'alice01',
          hostDisplayName: 'Alice',
          participants: participants,
          cart: cart,
        );

    final bob = const Participant(
        userId: 'u1', username: 'bobbob1', displayName: 'Bob', ready: true);
    final carol = const Participant(
        userId: 'u2', username: 'carol01', displayName: 'Carol', ready: false);
    final line = GroupCartItem(
      product: product(),
      qty: 2,
      addedById: 'u1',
      addedByName: 'bobbob1',
    );

    expect(session().canPlaceOrder, isFalse, reason: 'no participants');
    expect(session(participants: [bob]).canPlaceOrder, isFalse,
        reason: 'empty cart');
    expect(session(participants: [bob, carol], cart: [line]).canPlaceOrder,
        isFalse,
        reason: 'Carol is not ready');
    expect(session(participants: [bob], cart: [line]).canPlaceOrder, isTrue);
    expect(
        session(active: false, participants: [bob], cart: [line]).canPlaceOrder,
        isFalse,
        reason: 'session already closed');

    // The host never appears in participants and has no ready flag.
    final s = session(participants: [bob], cart: [line]);
    expect(s.isHost('h1'), isTrue);
    expect(s.isParticipant('h1'), isFalse);
    expect(s.isMember('h1'), isTrue);
    expect(s.participantFor('h1'), isNull);
  });
}
