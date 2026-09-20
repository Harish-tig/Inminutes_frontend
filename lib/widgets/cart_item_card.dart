import 'package:flutter/material.dart';

import '../models/cart_item.dart';
import '../utils/app_theme.dart';
import '../utils/ui.dart';
import 'qty_stepper.dart';

/// One line of the personal cart.
class CartItemCard extends StatelessWidget {
  final CartItem item;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;
  final VoidCallback onRemove;

  const CartItemCard({
    super.key,
    required this.item,
    required this.onIncrease,
    required this.onDecrease,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.product.name.toUpperCase(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.itemName,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${formatPrice(item.product.price)} each',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    formatPrice(item.lineTotal),
                    style: const TextStyle(
                      color: AppTheme.violet,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),

            // Quantity controls (− at 1 removes the line)
            SizedBox(
              width: 116,
              height: 40,
              child: QtyStepper(
                qty: item.qty,
                onDecrease: item.qty == 1 ? onRemove : onDecrease,
                onIncrease: item.product.qty > 0 ? onIncrease : null,
              ),
            ),
            IconButton(
              tooltip: 'Remove',
              onPressed: onRemove,
              icon: const Icon(Icons.close, size: 18, color: AppTheme.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
