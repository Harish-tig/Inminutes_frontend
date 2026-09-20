// ignore_for_file: avoid_print

// Dev tool: end-to-end check of ApiService + models + SocketService against a
// running backend. Not part of the app — run with
// `dart run --define=SERVER_URL=http://localhost:3000 tool/api_smoke.dart`.
import 'dart:async';

import 'package:inminutes/models/group_session.dart';
import 'package:inminutes/services/api_service.dart';
import 'package:inminutes/services/socket_service.dart';

int passed = 0, failed = 0;

void check(String label, bool ok, [String extra = '']) {
  if (ok) {
    passed++;
    print('  PASS  $label ${extra.isEmpty ? '' : '($extra)'}');
  } else {
    failed++;
    print('  FAIL  $label ${extra.isEmpty ? '' : '($extra)'}');
  }
}

Future<void> main() async {
  final stamp = DateTime.now().millisecondsSinceEpoch.toString().substring(7);
  final hostName = 'host$stamp';
  final guestName = 'guest$stamp';

  print('\n== users ==');
  final host = await ApiService.createUser(hostName);
  final guest = await ApiService.createUser(guestName);
  check('createUser parses {id,name}', host.id.length == 24 && host.username == hostName);
  final fetched = await ApiService.getUser(host.id);
  check('getUser parses full doc', fetched.id == host.id && fetched.username == hostName);

  try {
    await ApiService.createUser(hostName);
    check('duplicate username -> 409', false);
  } on ApiException catch (e) {
    check('duplicate username -> 409 with backend wording', e.statusCode == 409, e.message);
  }
  try {
    await ApiService.createUser('abc');
    check('short username -> 400', false);
  } on ApiException catch (e) {
    check('short username -> 400 with zod message', e.statusCode == 400, e.message);
  }

  print('\n== products ==');
  final products = await ApiService.getProducts();
  check('getProducts returns list', products.length == 17, '${products.length} products');
  final pizza = products.firstWhere((p) => p.name == 'Margherita Pizza');
  final burgerForLog = products.firstWhere((p) => p.name == 'Veg Burger');
  final soldOut = products.firstWhere((p) => p.qty == 0);
  check('instock derived correctly', pizza.instock && !soldOut.instock);
  final gulab = products.firstWhere((p) => p.name == 'Gulab Jamun (2 pc)');
  check('low-stock item present', gulab.qty > 0,
      'qty=${gulab.qty} — reseed if this is 0');
  check('products carry image_urls', pizza.imageUrls.isNotEmpty,
      '${pizza.imageUrls.length} url(s)');

  print('\n== personal cart (stock reserved on add) ==');
  final stockBefore = pizza.qty;
  await ApiService.addToCart(host.id, pizza.id, 2);
  var cart = await ApiService.getCart(host.id);
  check('cart line parses with populated product',
      cart.length == 1 && cart.first.product.name == 'Margherita Pizza' && cart.first.qty == 2);
  var after = (await ApiService.getProducts()).firstWhere((p) => p.id == pizza.id);
  check('adding reserved stock', after.qty == stockBefore - 2, '$stockBefore -> ${after.qty}');
  check('lineTotal', cart.first.lineTotal == pizza.price * 2);

  try {
    await ApiService.addToCart(host.id, pizza.id, 1);
    check('duplicate cart line -> 409', false);
  } on ApiException catch (e) {
    check('duplicate cart line -> 409', e.statusCode == 409, e.message);
    // The backend's own wording for this one references its own
    // implementation ("use PATCH"), which ApiService rewrites before a
    // widget ever sees it — a user has no reason to know what PATCH means.
    check('duplicate-cart message has no HTTP-verb jargon',
        !e.message.toUpperCase().contains('PATCH'), e.message);
  }

  await ApiService.updateCartItem(host.id, pizza.id, 5);
  after = (await ApiService.getProducts()).firstWhere((p) => p.id == pizza.id);
  check('PATCH qty is absolute (2->5 reserves 3 more)', after.qty == stockBefore - 5, 'qty=${after.qty}');

  await ApiService.updateCartItem(host.id, pizza.id, 1);
  after = (await ApiService.getProducts()).firstWhere((p) => p.id == pizza.id);
  check('reducing releases stock', after.qty == stockBefore - 1, 'qty=${after.qty}');

  await ApiService.removeCartItem(host.id, pizza.id);
  after = (await ApiService.getProducts()).firstWhere((p) => p.id == pizza.id);
  check('removing releases all stock', after.qty == stockBefore, 'qty=${after.qty}');
  cart = await ApiService.getCart(host.id);
  check('cart is empty after remove', cart.isEmpty);

  try {
    await ApiService.addToCart(host.id, soldOut.id, 1);
    check('out-of-stock add -> 409 Insufficient stock', false);
  } on ApiException catch (e) {
    check('out-of-stock add -> 409 "${e.message}"',
        e.statusCode == 409 && e.message == 'Insufficient stock');
  }

  print('\n== existing-user sign in (demo) ==');
  final allUsers = await ApiService.getUsers();
  check('GET /users lists users for the lookup',
      allUsers.any((u) => u.id == host.id && u.username == hostName),
      '${allUsers.length} users');
  check('lookup is case-insensitive',
      allUsers.any((u) => u.username.toLowerCase() == hostName.toLowerCase()));

  print('\n== personal order ==');
  try {
    await ApiService.placeOrder(host.id);
    check('empty cart -> 400', false);
  } on ApiException catch (e) {
    check('empty cart -> 400 "${e.message}"', e.statusCode == 400);
  }
  await ApiService.addToCart(host.id, pizza.id, 2);
  final order = await ApiService.placeOrder(host.id);
  check('order parses', order.orderType == 'normal' && order.itemCount == 2,
      '₹${order.orderAmt}, status=${order.orderStatus}');
  check('checkout does not change stock',
      (await ApiService.getProducts()).firstWhere((p) => p.id == pizza.id).qty == stockBefore - 2);
  final history = await ApiService.getOrders(host.id);
  check('order history returns it', history.length == 1 && history.first.id == order.id);

  print('\n== group session + realtime ==');
  final code = await ApiService.createGroupSession(host.id);
  check('createGroupSession returns 8-char code', code.length == 8, code);

  // A third socket, like a device watching the room.
  final events = <GroupSession>[];
  final firstEvent = Completer<void>();
  final socket = SocketService();
  socket.connect(
    joinCode: code,
    onState: (json) {
      events.add(GroupSession.fromJson(json));
      if (!firstEvent.isCompleted) firstEvent.complete();
    },
  );
  await Future<void>.delayed(const Duration(milliseconds: 800));

  var state = await ApiService.getGroupSession(code);
  check('initial state: host set, no participants, active',
      state.hostName == hostName && state.participants.isEmpty && state.active,
      'host=${state.hostName} display=${state.hostDisplayName}');
  check('host is not a participant', !state.isParticipant(host.id) && state.isHost(host.id));
  check('host counts as a member', state.isMember(host.id));

  try {
    await ApiService.joinGroupSession(code, host.id, 'Me');
    check('host joining own group -> 409', false);
  } on ApiException catch (e) {
    check('host joining own group -> 409 "${e.message}"', e.statusCode == 409);
  }

  state = await ApiService.joinGroupSession(code, guest.id, 'Bob');
  check('join returns full state', state.participants.length == 1 &&
      state.participants.first.displayName == 'Bob' && !state.participants.first.ready);

  await firstEvent.future.timeout(const Duration(seconds: 5));
  check('socket received group:state on join', events.isNotEmpty,
      '${events.length} event(s)');
  check('socket payload parses identically',
      events.last.participants.length == 1 && events.last.participants.first.displayName == 'Bob');

  try {
    await ApiService.joinGroupSession(code, guest.id, 'Bobby');
    check('double join -> 409', false);
  } on ApiException catch (e) {
    check('double join -> 409 "${e.message}"', e.statusCode == 409);
  }

  print('\n== two members ordering the same dish ==');
  final sameStock =
      (await ApiService.getProducts()).firstWhere((p) => p.id == pizza.id).qty;
  await ApiService.addGroupCartItem(code, guest.id, pizza.id, 2);
  var shared = await ApiService.addGroupCartItem(code, host.id, pizza.id, 2);

  final pizzaLines =
      shared.cart.where((c) => c.product.id == pizza.id).toList();
  check('both members get their own line', pizzaLines.length == 2,
      '${pizzaLines.length} lines');
  check('each line keeps its own owner and qty',
      pizzaLines.every((l) => l.qty == 2) &&
          pizzaLines.map((l) => l.addedById).toSet().length == 2);
  check('the group total is the sum of the lines',
      shared.totalQtyFor(pizza.id) == 4);
  check('each member sees only their own quantity',
      shared.myQty(pizza.id, guest.id) == 2 &&
          shared.myQty(pizza.id, host.id) == 2);
  check('stock was reserved for all four units',
      (await ApiService.getProducts()).firstWhere((p) => p.id == pizza.id).qty ==
          sameStock - 4,
      '$sameStock -> ${sameStock - 4}');

  final baskets = shared.cartByMember;
  check('baskets split by member and still add up',
      baskets.length == 2 &&
          baskets.fold<int>(0, (sum, b) => sum + b.total) == shared.total);

  try {
    await ApiService.addGroupCartItem(code, host.id, pizza.id, 1);
    check('adding your own line twice -> 409', false);
  } on ApiException catch (e) {
    check('adding your own line twice -> 409 "${e.message}"',
        e.statusCode == 409);
    check('group duplicate-add message has no HTTP-verb jargon',
        !e.message.toUpperCase().contains('PATCH'), e.message);
  }

  // Editing is per line, so nobody can change what someone else ordered.
  shared = await ApiService.updateGroupCartItem(code, host.id, pizza.id, 3);
  check('changing your own line leaves the other alone',
      shared.myQty(pizza.id, host.id) == 3 &&
          shared.myQty(pizza.id, guest.id) == 2);

  shared = await ApiService.removeGroupCartItem(code, host.id, pizza.id);
  check('removing your line keeps theirs',
      shared.myQty(pizza.id, host.id) == 0 &&
          shared.myQty(pizza.id, guest.id) == 2);
  try {
    await ApiService.updateGroupCartItem(code, host.id, pizza.id, 2);
    check('editing a line you do not own -> 404', false);
  } on ApiException catch (e) {
    check('editing a line you do not own -> 404 "${e.message}"',
        e.statusCode == 404);
  }
  await ApiService.removeGroupCartItem(code, guest.id, pizza.id);

  final eventsBeforeAdd = events.length;
  final gulabStock = (await ApiService.getProducts()).firstWhere((p) => p.id == gulab.id).qty;
  state = await ApiService.addGroupCartItem(code, guest.id, gulab.id, 2);
  check('group cart line parses with added_by',
      state.cart.length == 1 && state.cart.first.addedByName == guestName && state.cart.first.qty == 2);
  check('group total', state.total == gulab.price * 2, '₹${state.total}');
  check('group add reserved stock',
      state.cart.first.product.qty == gulabStock - 2,
      'product.qty=${state.cart.first.product.qty} while cart qty=${state.cart.first.qty}');

  await Future<void>.delayed(const Duration(milliseconds: 500));
  check('socket broadcast on group cart add', events.length > eventsBeforeAdd,
      '${events.length - eventsBeforeAdd} new event(s)');

  // Host may also edit the shared cart.
  state = await ApiService.updateGroupCartItem(code, guest.id, gulab.id, 3);
  check('the owner can change their own line, attribution untouched',
      state.cart.first.qty == 3 && state.cart.first.addedByName == guestName,
      'added_by=${state.cart.first.addedByName}');
  check('increase reserved one more', state.cart.first.product.qty == gulabStock - 3);

  try {
    await ApiService.updateGroupCartItem(code, guest.id, gulab.id, 99);
    check('over-ordering -> 409', false);
  } on ApiException catch (e) {
    check('over-ordering -> 409 "${e.message}"', e.statusCode == 409);
  }

  print('\n== checkout gating ==');
  try {
    await ApiService.placeGroupOrder(code, guest.id);
    check('non-host checkout -> 403', false);
  } on ApiException catch (e) {
    check('non-host checkout -> 403 "${e.message}"', e.statusCode == 403);
  }
  check('canPlaceOrder false while Bob is not ready', !state.canPlaceOrder);
  try {
    await ApiService.placeGroupOrder(code, host.id);
    check('not-everyone-ready checkout -> 409', false);
  } on ApiException catch (e) {
    check('not-everyone-ready checkout -> 409 "${e.message}"', e.statusCode == 409);
  }

  state = await ApiService.setReady(code, guest.id, true);
  check('ready toggle reflected in state', state.participants.first.ready);
  check('canPlaceOrder true once everyone is ready', state.canPlaceOrder);

  final groupOrder = await ApiService.placeGroupOrder(code, host.id);
  check('group order parses',
      groupOrder.orderType == 'group' && groupOrder.itemCount == 3,
      '₹${groupOrder.orderAmt}');

  await Future<void>.delayed(const Duration(milliseconds: 500));
  check('final group:state broadcast has active:false',
      events.last.active == false, 'total events: ${events.length}');

  state = await ApiService.getGroupSession(code);
  check('closed session still readable', !state.active && state.cart.length == 1);
  try {
    await ApiService.addGroupCartItem(code, guest.id, pizza.id, 1);
    check('cart change on closed session -> 404', false);
  } on ApiException catch (e) {
    check('cart change on closed session -> 404 "${e.message}"', e.statusCode == 404);
  }
  try {
    await ApiService.placeGroupOrder(code, host.id);
    check('double checkout -> 409', false);
  } on ApiException catch (e) {
    check('double checkout -> 409 "${e.message}"', e.statusCode == 409);
  }

  print('\n== re-entry (host backing out of the group) ==');
  final reCode = await ApiService.createGroupSession(host.id);
  await ApiService.joinGroupSession(reCode, guest.id, 'Bob');

  // What the entry screen does: read the session, and only join when the
  // caller is not already a member.
  var reState = await ApiService.getGroupSession(reCode);
  check('host is a member, so re-entry needs no join call',
      reState.isMember(host.id));
  check('a returning participant is a member too',
      reState.isMember(guest.id));
  final stranger = await ApiService.createUser('stran$stamp');
  check('a stranger is not a member, so they must join',
      !reState.isMember(stranger.id));

  // The calls the old build made, which is why re-entry used to be impossible.
  try {
    await ApiService.joinGroupSession(reCode, host.id, 'Host');
    check('host join still rejected -> 409', false);
  } on ApiException catch (e) {
    check('host join still rejected -> 409 "${e.message}"', e.statusCode == 409);
  }
  try {
    await ApiService.joinGroupSession(reCode, guest.id, 'Bob2');
    check('repeat join still rejected -> 409', false);
  } on ApiException catch (e) {
    check('repeat join still rejected -> 409 "${e.message}"', e.statusCode == 409);
  }

  print('\n== added_by attribution ==');
  final attrProduct = (await ApiService.getProducts())
      .firstWhere((p) => p.name == 'Veg Burger');
  reState = await ApiService.addGroupCartItem(reCode, guest.id, attrProduct.id, 1);
  check('the adder is recorded', reState.cart.first.addedById == guest.id);
  try {
    await ApiService.updateGroupCartItem(reCode, host.id, attrProduct.id, 3);
    check('the host cannot edit a line the guest added -> 404', false);
  } on ApiException catch (e) {
    check('the host cannot edit a line the guest added -> 404 "${e.message}"',
        e.statusCode == 404);
  }
  reState = await ApiService.updateGroupCartItem(reCode, guest.id, attrProduct.id, 3);
  check('the owner changing their own qty keeps attribution',
      reState.cart.first.addedById == guest.id && reState.cart.first.qty == 3,
      'added_by=${reState.cart.first.addedByName}');

  print('\n== remove a participant (host only) ==');
  final kickCode = await ApiService.createGroupSession(host.id,
      displayName: 'TheHost');
  final kicked = await ApiService.createUser('kickd$stamp');
  await ApiService.joinGroupSession(kickCode, guest.id, 'Bob');
  await ApiService.joinGroupSession(kickCode, kicked.id, 'Carol');

  final kickEvents = <String>[];
  final kickSocket = SocketService();
  kickSocket.connect(
    joinCode: kickCode,
    onState: (_) {},
    onParticipantRemoved: (userId, displayName) => kickEvents.add(displayName),
  );
  await Future<void>.delayed(const Duration(milliseconds: 800));

  final beforeKick =
      (await ApiService.getProducts()).firstWhere((p) => p.id == pizza.id).qty;
  await ApiService.addGroupCartItem(kickCode, kicked.id, pizza.id, 2);
  var kickState = await ApiService.getGroupSession(kickCode);
  check('the removable member has a line in the cart',
      kickState.cart.length == 1 && kickState.cart.first.addedById == kicked.id);

  try {
    await ApiService.removeParticipant(kickCode, guest.id, kicked.id);
    check('non-host cannot remove -> 403', false);
  } on ApiException catch (e) {
    check('non-host cannot remove -> 403 "${e.message}"', e.statusCode == 403);
  }
  try {
    await ApiService.removeParticipant(kickCode, host.id, host.id);
    check('host cannot remove themselves -> 400', false);
  } on ApiException catch (e) {
    check('host cannot remove themselves -> 400 "${e.message}"',
        e.statusCode == 400);
  }

  kickState = await ApiService.removeParticipant(kickCode, host.id, kicked.id);
  check('removed member is gone from participants',
      kickState.participants.length == 1 &&
          !kickState.isParticipant(kicked.id));
  check('their cart lines went with them', kickState.cart.isEmpty);
  check('and their reserved stock was released',
      (await ApiService.getProducts()).firstWhere((p) => p.id == pizza.id).qty ==
          beforeKick,
      'qty back to $beforeKick');

  await Future<void>.delayed(const Duration(milliseconds: 500));
  check('group:participant_removed reached the socket',
      kickEvents.contains('Carol'), 'events: $kickEvents');

  // Being removed is not a ban.
  final rejoined = await ApiService.joinGroupSession(kickCode, kicked.id, 'Carol');
  check('a removed member can join again', rejoined.isParticipant(kicked.id));
  kickSocket.dispose(kickCode);

  print('\n== host group order log ==');
  await ApiService.addGroupCartItem(kickCode, guest.id, pizza.id, 2);
  await ApiService.addGroupCartItem(kickCode, host.id, burgerForLog.id, 1);
  await ApiService.setReady(kickCode, guest.id, true);
  await ApiService.setReady(kickCode, kicked.id, true);
  final hostedOrder = await ApiService.placeGroupOrder(kickCode, host.id);

  final log = await ApiService.getHostedGroupOrders(host.id);
  check('the hosted order is in the log', log.any((o) => o.id == hostedOrder.id));
  final entry = log.firstWhere((o) => o.id == hostedOrder.id);
  check('log carries the session code', entry.joinCode == kickCode);
  check('host display name survives the session',
      entry.host?.displayName == 'TheHost');
  check('lines are attributed',
      entry.products.every((l) => l.addedByName.isNotEmpty) &&
          entry.products.any((l) => l.addedByName == 'Bob'));
  check('breakdown covers everyone incl. the host',
      entry.breakdown.length == 3, '${entry.breakdown.length} rows');
  check('someone who ordered nothing is still listed',
      entry.breakdown.any((r) => r.orderedNothing));
  check('breakdown sums to the order total',
      entry.breakdown.fold<int>(0, (sum, r) => sum + r.amount) ==
          entry.orderAmt,
      '₹${entry.orderAmt}');

  final guestLog = await ApiService.getHostedGroupOrders(guest.id);
  check('a participant sees none of the host\'s sessions',
      !guestLog.any((o) => o.id == hostedOrder.id));

  final guestHistory = await ApiService.getOrders(guest.id);
  check('group order lands in the participant history',
      guestHistory.any((o) => o.id == groupOrder.id && o.isGroup));

  socket.dispose(code);
  print('\n================  $passed passed, $failed failed  ================\n');
}
