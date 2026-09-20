import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/cart_item.dart';
import '../models/group_session.dart';
import '../models/order.dart';
import '../models/participant.dart';
import '../state/group_state.dart';
import '../state/shop_state.dart';
import '../state/user_state.dart';
import '../utils/app_theme.dart';
import '../utils/ui.dart';
import '../widgets/group_cart_tile.dart';
import '../widgets/participant_tile.dart';
import '../widgets/state_views.dart';
import 'group_menu_screen.dart';

/// The live group session: who is in it, what is in the shared cart, who is
/// ready, and — for the host — the checkout.
///
/// `GroupState` is created by [route] so its socket lives exactly as long as
/// this screen. Updates arrive as `group:state` and rebuild only the
/// `Consumer` subtrees below, so the scroll position survives them.
class GroupScreen extends StatefulWidget {
  const GroupScreen({super.key});

  /// Builds the route together with the GroupState that owns the socket.
  static Route<void> route(BuildContext context, String joinCode) {
    final shop = context.read<ShopState>();
    final userId = context.read<UserState>().userId;
    return MaterialPageRoute(
      builder: (_) => ChangeNotifierProvider(
        create: (_) =>
            GroupState(joinCode: joinCode, userId: userId, shop: shop),
        child: const GroupScreen(),
      ),
    );
  }

  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen> {
  // Held here so a realtime update never recreates it, and never scrolls back.
  final ScrollController _scrollController = ScrollController();
  bool _busy = false;
  bool _leaving = false;
  GroupState? _group;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _group = context.read<GroupState>()..addListener(_syncRemembered);
      _syncRemembered();
    });
  }

  /// Keeps the remembered join code in step with reality, so the home screen
  /// offers a way back in while the session is live and stops offering one the
  /// moment it is closed or gone.
  void _syncRemembered() {
    if (!mounted || _leaving) return;
    final group = _group;
    if (group == null) return;
    final user = context.read<UserState>();
    final session = group.session;

    // The host kicked us. State alone cannot say so — we would only see
    // ourselves missing — which is why the backend sends a separate event.
    if (group.wasRemoved) {
      _leaving = true;
      user.forgetGroup();
      WidgetsBinding.instance.addPostFrameCallback((_) => _showRemoved());
      return;
    }

    if (session == null) {
      if (group.error != null) user.forgetGroup();
    } else if (!session.active) {
      user.forgetGroup();
    } else if (session.isMember(user.userId)) {
      user.rememberGroup(group.joinCode);
    }
  }

  Future<void> _showRemoved() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.person_remove, color: AppTheme.danger, size: 40),
        title: const Text('You were removed'),
        content: const Text(
          'The host removed you from this group. Anything you added has been '
          'put back. You can join again with the code.',
          textAlign: TextAlign.center,
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  /// Leaves the session on this device only — the backend has no "leave"
  /// endpoint, so this just stops offering a way back in.
  Future<void> _leaveGroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Leave this group?'),
        content: const Text(
          'You stay a member on the server and anything you added stays in the '
          'shared cart. You can come back with the join code.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    _leaving = true;
    await context.read<UserState>().forgetGroup();
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _group?.removeListener(_syncRemembered);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Host removing a member. Their cart lines go with them and that stock is
  /// released, so it is worth confirming first.
  Future<void> _confirmRemove(GroupState group, Participant p) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove ${p.displayName}?'),
        content: Text(
          'Everything ${p.displayName} added to the shared cart is removed and '
          'that stock goes back on sale. They can rejoin with the code.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await _run(() => group.removeParticipant(p.userId));
    if (mounted) showSnack(context, '${p.displayName} was removed');
  }

  Future<void> _placeOrder(GroupState group) async {
    setState(() => _busy = true);
    try {
      final order = await group.placeOrder();
      if (mounted) await _showSuccessDialog(order);
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showSuccessDialog(Order order) async {
    await context.read<UserState>().forgetGroup();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: AppTheme.success, size: 44),
        title: const Text('Group order placed'),
        content: Text(
          '${order.itemCount} item(s) · ${formatPrice(order.orderAmt)}\n'
          'The session is now closed.',
          textAlign: TextAlign.center,
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GROUP ORDER'),
        actions: [
          // Leave on this device
          IconButton(
            tooltip: 'Leave group',
            icon: const Icon(Icons.exit_to_app),
            onPressed: _leaveGroup,
          ),
          // Live / reconnecting indicator
          Consumer<GroupState>(
            builder: (context, group, _) => Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: StatusChip(
                  label: group.connected ? 'LIVE' : 'CONNECTING',
                  color: AppTheme.violetDeep,
                  background:
                      group.connected ? AppTheme.lime : AppTheme.onVioletMuted,
                  icon: group.connected
                      ? Icons.wifi_tethering
                      : Icons.wifi_tethering_off,
                ),
              ),
            ),
          ),
        ],
      ),

      body: SafeArea(
        top: false,
        child: Consumer<GroupState>(
          builder: (context, group, _) {
            if (group.loading) {
              return const LoadingView(message: 'Loading group...');
            }
            final session = group.session;
            if (session == null) {
              return ErrorView(
                message: group.error ?? 'Group session not found.',
                onRetry: () => Navigator.pop(context),
              );
            }

            return ListView(
              controller: _scrollController,
              padding: AppTheme.pagePadding,
              children: [
                // Join code header
                _JoinCodeCard(session: session),
                const SizedBox(height: 20),

                // Participants
                _SectionHeading(
                  title: 'PARTICIPANTS',
                  trailing: '${session.participants.length} joined',
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    child: Column(
                      children: [
                        ParticipantTile(
                          name: session.hostDisplayName,
                          isHost: true,
                          isYou: group.isHost,
                        ),
                        if (session.participants.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              'No participants have joined yet. Share the code above.',
                              style: TextStyle(
                                  color: AppTheme.textMuted, fontSize: 13),
                            ),
                          )
                        else
                          ...session.participants.map(
                            (p) => ParticipantTile(
                              name: p.displayName,
                              isHost: false,
                              isYou: p.userId == group.userId,
                              participant: p,
                              // Only the host can remove someone, and only
                              // while the session is still open.
                              onRemove: group.isHost && session.active && !_busy
                                  ? () => _confirmRemove(group, p)
                                  : null,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Shared cart
                _SectionHeading(
                  title: 'SHARED CART',
                  trailing: session.cart.isEmpty
                      ? null
                      : formatPrice(session.total),
                ),
                if (session.cart.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: 14, vertical: 22),
                      child: Text(
                        'The shared cart is empty. Add something from the menu.',
                        style: TextStyle(
                            color: AppTheme.textMuted, fontSize: 13),
                      ),
                    ),
                  )
                else
                  // One basket per member, so two people ordering the same
                  // dish are shown as two orders rather than one big number.
                  ...session.cartByMember.map(
                    (basket) => _MemberBasket(
                      basket: basket,
                      isYou: basket.userId == group.userId,
                      // The backend only lets you change your own lines.
                      editable: session.active &&
                          basket.userId == group.userId &&
                          !_busy,
                      onIncrease: (item) => _run(() =>
                          group.updateQty(item.product.id, item.qty + 1)),
                      onDecrease: (item) => _run(() =>
                          group.updateQty(item.product.id, item.qty - 1)),
                      onRemove: (item) =>
                          _run(() => group.removeItem(item.product.id)),
                    ),
                  ),
                const SizedBox(height: 12),

                // Add items to the shared cart
                if (session.active && group.isMember)
                  OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChangeNotifierProvider.value(
                          value: group,
                          child: const GroupMenuScreen(),
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add items from the menu'),
                  ),
                const SizedBox(height: 24),
              ],
            );
          },
        ),
      ),

      // Ready toggle (participants) or checkout (host)
      bottomNavigationBar: Consumer<GroupState>(
        builder: (context, group, _) {
          final session = group.session;
          if (session == null) return const SizedBox.shrink();
          return _GroupActionBar(
            group: group,
            session: session,
            busy: _busy,
            onToggleReady: () => _run(() => group.setReady(!group.isReady)),
            onPlaceOrder: () => _placeOrder(group),
          );
        },
      ),
    );
  }
}

/// One member's items inside the shared cart, with their own subtotal.
class _MemberBasket extends StatelessWidget {
  final MemberCart basket;
  final bool isYou;
  final bool editable;
  final void Function(GroupCartItem item) onIncrease;
  final void Function(GroupCartItem item) onDecrease;
  final void Function(GroupCartItem item) onRemove;

  const _MemberBasket({
    required this.basket,
    required this.isYou,
    required this.editable,
    required this.onIncrease,
    required this.onDecrease,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Whose basket this is, and what it comes to
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor:
                      isYou ? AppTheme.violetSoft : AppTheme.neutralSoft,
                  child: Text(
                    basket.displayName.isEmpty
                        ? '?'
                        : basket.displayName.characters.first.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: isYou ? AppTheme.violet : AppTheme.textMuted,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isYou
                        ? '${basket.displayName} (you)'
                        : basket.displayName,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.itemName.copyWith(fontSize: 14),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${basket.unitCount} item(s) · ${formatPrice(basket.total)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),

          // That member's lines
          ...basket.items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GroupCartTile(
                item: item,
                addedByName: basket.displayName,
                showAddedBy: false,
                editable: editable,
                onIncrease: () => onIncrease(item),
                onDecrease: () => onDecrease(item),
                onRemove: () => onRemove(item),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Big join code with a copy action and the session status.
class _JoinCodeCard extends StatelessWidget {
  final GroupSession session;
  const _JoinCodeCard({required this.session});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('JOIN CODE', style: AppTheme.kicker),
                ),
                if (session.active)
                  const StatusChip(
                    label: 'ACTIVE',
                    color: AppTheme.success,
                    background: AppTheme.successSoft,
                  )
                else
                  const StatusChip(
                    label: 'ORDER PLACED',
                    color: AppTheme.textMuted,
                    background: AppTheme.neutralSoft,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: FittedBox(
                    alignment: Alignment.centerLeft,
                    fit: BoxFit.scaleDown,
                    child: Text(
                      session.joinCode,
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 4,
                        color: AppTheme.textDark,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Copy code',
                  icon: const Icon(Icons.copy_rounded, color: AppTheme.violet),
                  onPressed: () async {
                    await Clipboard.setData(
                        ClipboardData(text: session.joinCode));
                    if (context.mounted) {
                      showSnack(context, 'Join code copied');
                    }
                  },
                ),
              ],
            ),
            Text(
              'Hosted by ${session.hostDisplayName}',
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom bar: Ready for participants, Place Order for the host.
class _GroupActionBar extends StatelessWidget {
  final GroupState group;
  final GroupSession session;
  final bool busy;
  final VoidCallback onToggleReady;
  final VoidCallback onPlaceOrder;

  const _GroupActionBar({
    required this.group,
    required this.session,
    required this.busy,
    required this.onToggleReady,
    required this.onPlaceOrder,
  });

  @override
  Widget build(BuildContext context) {
    if (!session.active) {
      return const SafeArea(
        minimum: EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Text(
          'This session is closed — the order has been placed.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.textMuted),
        ),
      );
    }

    if (group.isHost) {
      // The button is enabled only when the state the server sent allows it.
      final canOrder = session.canPlaceOrder;
      return SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!canOrder)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _blockedReason(session),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppTheme.textMuted, fontSize: 12),
                ),
              ),
            ElevatedButton(
              onPressed: canOrder && !busy ? onPlaceOrder : null,
              child: busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      'PLACE ORDER · ${formatPrice(session.total)}',
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
          ],
        ),
      );
    }

    if (!group.isMember) {
      return const SafeArea(
        minimum: EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Text(
          'You are viewing this session but have not joined it.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.textMuted),
        ),
      );
    }

    // Participant ready toggle
    final ready = group.isReady;
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: ElevatedButton.icon(
        onPressed: busy ? null : onToggleReady,
        style: ElevatedButton.styleFrom(
          backgroundColor: ready ? AppTheme.success : AppTheme.violet,
        ),
        icon: Icon(ready ? Icons.check_circle : Icons.check_circle_outline),
        label: Text(
          ready ? 'READY · TAP TO UNDO' : "I'M READY",
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  /// Why the host cannot check out yet — straight from the server's rules.
  String _blockedReason(GroupSession session) {
    if (session.participants.isEmpty) {
      return 'Waiting for someone to join.';
    }
    if (session.cart.isEmpty) {
      return 'Add something to the shared cart first.';
    }
    final notReady =
        session.participants.where((p) => !p.ready).map((p) => p.displayName);
    return 'Waiting for ${notReady.join(', ')} to be ready.';
  }
}

/// Section title with an optional right-hand label.
class _SectionHeading extends StatelessWidget {
  final String title;
  final String? trailing;

  const _SectionHeading({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.sectionHeading,
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            Text(trailing!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}
