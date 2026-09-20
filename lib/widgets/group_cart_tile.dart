import 'package:flutter/material.dart';

import '../models/cart_item.dart';
import '../utils/app_theme.dart';
import '../utils/ui.dart';
import 'qty_stepper.dart';

/// One line of the shared group cart, showing who last changed it.
class GroupCartTile extends StatelessWidget {
  final GroupCartItem item;
  /// Resolved through the session, so this is the display name the
  /// participants list shows rather than the raw username.
  final String addedByName;

  /// Off when the surrounding section already names the member.
  final bool showAddedBy;
  final bool editable;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;
  final VoidCallback onRemove;

  const GroupCartTile({
    super.key,
    required this.item,
    required this.addedByName,
    this.showAddedBy = true,
    required this.editable,
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
                    'Qty: ${item.qty}  ·  ${formatPrice(item.lineTotal)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (showAddedBy) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.person_outline,
                            size: 13, color: AppTheme.textMuted),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            'Added by $addedByName',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // Quantity controls — hidden once the session is closed
            if (editable) ...[
              SizedBox(
                width: 104,
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
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(width: 34, height: 34),
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.close,
                    size: 18, color: AppTheme.textMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
