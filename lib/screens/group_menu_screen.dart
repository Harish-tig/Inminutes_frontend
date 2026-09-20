import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/group_state.dart';
import '../state/shop_state.dart';
import '../utils/app_theme.dart';
import '../utils/ui.dart';
import '../models/product.dart';
import '../widgets/product_card.dart';
import '../widgets/search_field.dart';
import '../widgets/state_views.dart';

/// The menu, but every action writes to the **shared** group cart.
///
/// It reads products from `ShopState` and cart quantities from `GroupState`.
/// `GroupState` refreshes the product list on every `group:state`, so stock
/// another device reserves turns to "Sold out" here without a manual refresh.
class GroupMenuScreen extends StatefulWidget {
  const GroupMenuScreen({super.key});

  @override
  State<GroupMenuScreen> createState() => _GroupMenuScreenState();
}

class _GroupMenuScreenState extends State<GroupMenuScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _busy = false;
  String _query = '';

  List<Product> _visible(List<Product> products) {
    if (_query.isEmpty) return products;
    final q = _query.toLowerCase();
    return products.where((p) => p.name.toLowerCase().contains(q)).toList();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ShopState>().loadProducts(showSpinner: false);
    });
  }

  @override
  void dispose() {
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

  @override
  Widget build(BuildContext context) {
    final group = context.read<GroupState>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('ADD TO GROUP CART'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(70),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Group ${group.joinCode}',
                  style: const TextStyle(
                      color: AppTheme.onVioletMuted, fontSize: 12),
                ),
                const SizedBox(height: 8),
                // Menu search
                SearchField(onChanged: (v) => setState(() => _query = v)),
              ],
            ),
          ),
        ),
      ),

      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () => context.read<ShopState>().loadProducts(showSpinner: false),
          // Products come from ShopState, quantities from the live group cart.
          child: Consumer2<ShopState, GroupState>(
            builder: (context, shop, group, _) {
              if (shop.loadingProducts && shop.products.isEmpty) {
                return const LoadingView(message: 'Loading products...');
              }
              if (!group.isActive) {
                return const EmptyView(
                  icon: Icons.lock_outline,
                  message: 'This session is closed — the order was placed.',
                );
              }

              final visible = _visible(shop.products);
              if (visible.isEmpty) {
                return EmptyView(
                  icon: Icons.no_food_outlined,
                  message: _query.isEmpty
                      ? 'No products available.'
                      : 'Nothing matches "$_query".',
                );
              }

              // Product grid
              return GridView.builder(
                controller: _scrollController,
                padding: AppTheme.pagePadding,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  mainAxisExtent: ProductCard.gridExtent,
                ),
                itemCount: visible.length,
                itemBuilder: (context, index) {
                  final product = visible[index];
                  // The stepper edits your own line; the note says what the
                  // whole group has on order for this dish.
                  final inCart = group.qtyInGroupCart(product.id);
                  final groupTotal = group.groupQtyFor(product.id);
                  return ProductCard(
                    product: product,
                    qtyInCart: inCart,
                    note: groupTotal > inCart
                        ? 'GROUP HAS $groupTotal'
                        : null,
                    onAdd: () => _run(() => group.addItem(product.id, 1)),
                    onIncrease: () =>
                        _run(() => group.updateQty(product.id, inCart + 1)),
                    onDecrease: () => _run(
                      () => inCart == 1
                          ? group.removeItem(product.id)
                          : group.updateQty(product.id, inCart - 1),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),

      // Shared cart summary
      bottomNavigationBar: Consumer<GroupState>(
        builder: (context, group, _) {
          final session = group.session;
          if (session == null || session.cart.isEmpty) {
            return const SizedBox.shrink();
          }
          return SafeArea(
            minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '${session.unitCount} item(s) in group cart',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(formatPrice(session.total)),
                  const SizedBox(width: 6),
                  const Icon(Icons.arrow_forward, size: 18),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
