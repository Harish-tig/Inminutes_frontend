import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/product.dart';
import '../state/shop_state.dart';
import '../state/user_state.dart';
import '../utils/app_theme.dart';
import '../utils/ui.dart';
import '../widgets/product_card.dart';
import '../widgets/search_field.dart';
import '../widgets/state_views.dart';
import 'cart_screen.dart';
import 'group_entry_screen.dart';
import 'group_screen.dart';
import 'orders_screen.dart';

/// The default screen: individual ordering. Group ordering is one tap away at
/// the top, but it is never the default mode.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Kept on the State so realtime/refresh updates never reset the scroll.
  final ScrollController _scrollController = ScrollController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userId = context.read<UserState>().userId;
      context.read<ShopState>().loadProducts();
      context.read<ShopState>().loadCart(userId, showSpinner: false);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  List<Product> _visible(List<Product> products) {
    if (_query.isEmpty) return products;
    final q = _query.toLowerCase();
    return products.where((p) => p.name.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final userId = context.read<UserState>().userId;
    final username = context.select<UserState, String>(
      (s) => s.user?.username ?? '',
    );

    return Scaffold(
      // Header
      appBar: AppBar(
        titleSpacing: 16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('InMinutes'),
            Text(
              'Hi, $username',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.onVioletMuted,
                fontStyle: FontStyle.normal,
              ),
            ),
          ],
        ),
        actions: [
          // Cart access — always visible, badged with the current item count
          Consumer<ShopState>(
            builder: (context, shop, _) => IconButton(
              tooltip: 'Your cart',
              icon: Badge(
                label: Text('${shop.cartItemCount}'),
                isLabelVisible: shop.cartItemCount > 0,
                child: const Icon(Icons.shopping_cart_outlined),
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CartScreen()),
              ),
            ),
          ),
          IconButton(
            tooltip: 'My orders',
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const OrdersScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Switch user',
            icon: const Icon(Icons.logout),
            onPressed: () => _confirmSwitchUser(context),
          ),
          const SizedBox(width: 4),
        ],
      ),

      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () => context.read<ShopState>().refreshAll(userId),
          child: Consumer<ShopState>(
            builder: (context, shop, _) {
              if (shop.loadingProducts && shop.products.isEmpty) {
                return const LoadingView(message: 'Loading products...');
              }
              if (shop.productsError != null && shop.products.isEmpty) {
                return ErrorView(
                  message: shop.productsError!,
                  onRetry: () => shop.loadProducts(),
                );
              }

              final visible = _visible(shop.products);

              return CustomScrollView(
                controller: _scrollController,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  // Violet block: search and the Group Order action
                  SliverToBoxAdapter(
                    child: _HeaderBlock(
                      onSearch: (value) => setState(() => _query = value),
                    ),
                  ),

                  // Section heading
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('MENU', style: AppTheme.sectionHeading),
                          Text(
                            '${visible.length} items',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),

                  if (visible.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: EmptyView(
                        icon: Icons.no_food_outlined,
                        message: _query.isEmpty
                            ? 'No products available.'
                            : 'Nothing matches "$_query".',
                      ),
                    )
                  else
                    // Product grid
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      sliver: SliverGrid.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          mainAxisExtent: ProductCard.gridExtent,
                        ),
                        itemCount: visible.length,
                        itemBuilder: (context, index) {
                          final product = visible[index];
                          final inCart = shop.qtyInCart(product.id);
                          return ProductCard(
                            product: product,
                            qtyInCart: inCart,
                            onAdd: () => _run(
                              () => shop.addToCart(userId, product.id, 1),
                            ),
                            onIncrease: () => _run(
                              () => shop.updateCartQty(
                                  userId, product.id, inCart + 1),
                            ),
                            onDecrease: () => _run(
                              () => inCart == 1
                                  ? shop.removeFromCart(userId, product.id)
                                  : shop.updateCartQty(
                                      userId, product.id, inCart - 1),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),

      // Current cart summary
      bottomNavigationBar: const _CartSummaryBar(),
    );
  }

  Future<void> _confirmSwitchUser(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Switch user?'),
        content: const Text(
          'This device will forget the current user and ask for a new name. '
          'Nothing is deleted on the server.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Switch'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      context.read<ShopState>().clear();
      await context.read<UserState>().signOut();
    }
  }
}

/// Violet block under the app bar: search, plus the Group Order action and a
/// way back into a group this device is already in.
class _HeaderBlock extends StatelessWidget {
  final ValueChanged<String> onSearch;

  const _HeaderBlock({required this.onSearch});

  @override
  Widget build(BuildContext context) {
    final activeCode =
        context.select<UserState, String?>((s) => s.activeJoinCode);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      decoration: const BoxDecoration(
        color: AppTheme.violet,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Menu search
          SearchField(onChanged: onSearch),
          const SizedBox(height: 12),

          // Group Order action — lime, the accent used only on violet
          Row(
            children: [
              Expanded(
                child: _LimeBar(
                  icon: Icons.groups_rounded,
                  label: 'GROUP ORDER',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const GroupEntryScreen()),
                  ),
                ),
              ),
              // Back into the group this device is already in
              if (activeCode != null) ...[
                const SizedBox(width: 8),
                _RejoinButton(joinCode: activeCode),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _LimeBar extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _LimeBar({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.lime,
      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        child: SizedBox(
          height: 44,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: AppTheme.violetDeep),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.buttonLabel
                      .copyWith(color: AppTheme.violetDeep, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Re-enters the group this device last created or joined. Backing out of the
/// group screen is therefore not a one-way door.
class _RejoinButton extends StatelessWidget {
  final String joinCode;

  const _RejoinButton({required this.joinCode});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.violetDeep,
      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      child: InkWell(
        onTap: () =>
            Navigator.push(context, GroupScreen.route(context, joinCode)),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: SizedBox(
            height: 44,
            child: Row(
              children: [
                const Icon(Icons.meeting_room_outlined,
                    size: 16, color: AppTheme.lime),
                const SizedBox(width: 6),
                Text(
                  joinCode,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    fontStyle: FontStyle.italic,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Sticky bar showing the personal cart total; hidden when the cart is empty.
class _CartSummaryBar extends StatelessWidget {
  const _CartSummaryBar();

  @override
  Widget build(BuildContext context) {
    return Consumer<ShopState>(
      builder: (context, shop, _) {
        if (shop.cart.isEmpty) return const SizedBox.shrink();

        return SafeArea(
          minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: ElevatedButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CartScreen()),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    '${shop.cartItemCount} item(s) in cart',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(formatPrice(shop.cartTotal)),
                const SizedBox(width: 6),
                const Icon(Icons.arrow_forward, size: 18),
              ],
            ),
          ),
        );
      },
    );
  }
}
