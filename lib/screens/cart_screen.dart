import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/order.dart';
import '../state/shop_state.dart';
import '../state/user_state.dart';
import '../utils/app_theme.dart';
import '../utils/ui.dart';
import '../widgets/cart_item_card.dart';
import '../widgets/state_views.dart';

/// Personal cart: change quantities, remove lines, place the order.
class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _placing = false;

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

  Future<void> _placeOrder() async {
    final userId = context.read<UserState>().userId;
    setState(() => _placing = true);
    try {
      final order = await context.read<ShopState>().placeOrder(userId);
      if (mounted) await _showSuccessDialog(order);
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  Future<void> _showSuccessDialog(Order order) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.check_circle,
            color: AppTheme.success, size: 44),
        title: const Text('Order placed'),
        content: Text(
          '${order.itemCount} item(s) · ${formatPrice(order.orderAmt)}\n'
          'Status: ${order.orderStatus}',
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
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final userId = context.read<UserState>().userId;

    return Scaffold(
      appBar: AppBar(title: const Text('YOUR CART')),
      body: SafeArea(
        top: false,
        child: Consumer<ShopState>(
          builder: (context, shop, _) {
            if (shop.loadingCart && shop.cart.isEmpty) {
              return const LoadingView(message: 'Loading cart...');
            }
            if (shop.cart.isEmpty) {
              return EmptyView(
                icon: Icons.shopping_bag_outlined,
                message: 'Your cart is empty.',
                action: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Browse the menu'),
                ),
              );
            }

            // Cart items
            return ListView.separated(
              controller: _scrollController,
              padding: AppTheme.pagePadding,
              itemCount: shop.cart.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final item = shop.cart[index];
                return CartItemCard(
                  item: item,
                  onIncrease: () => _run(
                    () => shop.updateCartQty(
                        userId, item.product.id, item.qty + 1),
                  ),
                  onDecrease: () => _run(
                    () => shop.updateCartQty(
                        userId, item.product.id, item.qty - 1),
                  ),
                  onRemove: () =>
                      _run(() => shop.removeFromCart(userId, item.product.id)),
                );
              },
            );
          },
        ),
      ),

      // Order total and checkout
      bottomNavigationBar: Consumer<ShopState>(
        builder: (context, shop, _) {
          if (shop.cart.isEmpty) return const SizedBox.shrink();

          return SafeArea(
            minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('TOTAL', style: AppTheme.sectionHeading),
                      Text(
                        formatPrice(shop.cartTotal),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          fontStyle: FontStyle.italic,
                          color: AppTheme.violet,
                        ),
                      ),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: _placing ? null : _placeOrder,
                  child: _placing
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('PLACE ORDER'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
