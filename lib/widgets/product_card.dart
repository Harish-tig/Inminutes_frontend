import 'package:flutter/material.dart';

import '../models/product.dart';
import '../utils/app_theme.dart';
import '../utils/ui.dart';
import 'qty_stepper.dart';
import 'tapered_button.dart';

/// One menu item, laid out as a grid tile. Used by both the personal home
/// screen and the group menu — only the callbacks differ.
///
/// [qtyInCart] is how many units the relevant cart already holds, while
/// `product.qty` is how much stock is still free to reserve. A product can be
/// in the cart and still show "no stock left".
class ProductCard extends StatelessWidget {
  /// Height the grid should give this card.
  static const double gridExtent = 232;

  final Product product;
  final int qtyInCart;

  /// Optional second line under the stock label — the group menu uses it to
  /// say what the whole group has on order, since the stepper only ever edits
  /// the caller's own quantity.
  final String? note;
  final VoidCallback? onAdd;
  final VoidCallback? onIncrease;
  final VoidCallback? onDecrease;

  const ProductCard({
    super.key,
    required this.product,
    required this.qtyInCart,
    this.note,
    this.onAdd,
    this.onIncrease,
    this.onDecrease,
  });

  @override
  Widget build(BuildContext context) {
    // Nothing left to reserve and nothing in the cart — the card goes grey,
    // the way the reference greys out unavailable items.
    final soldOut = !product.instock && qtyInCart == 0;

    return Card(
      clipBehavior: Clip.antiAlias,
      color: soldOut ? AppTheme.mutedSurface : AppTheme.violetSoft,
      child: Column(
        children: [
          // Product image, with the price pill on top of it
          _Thumbnail(product: product, soldOut: soldOut),

          // Name and live stock, centred in whatever space is left
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    product.name.toUpperCase(),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.itemName.copyWith(
                      fontSize: 13,
                      height: 1.15,
                      color: soldOut ? AppTheme.mutedDark : AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 3),
                  _StockLabel(product: product, soldOut: soldOut),
                  if (note != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        note!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.kicker.copyWith(
                          fontSize: 9,
                          color: AppTheme.violet,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Add button, or the stepper once the item is in the cart
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: qtyInCart > 0
                ? SizedBox(
                    height: 37,
                    child: QtyStepper(
                      qty: qtyInCart,
                      onDecrease: onDecrease,
                      // Nothing left to reserve — increase is unavailable.
                      onIncrease: product.qty > 0 ? onIncrease : null,
                    ),
                  )
                : TaperedButton(
                    label: soldOut ? 'NO STOCK' : 'ADD',
                    onPressed: soldOut ? null : onAdd,
                  ),
          ),
        ],
      ),
    );
  }
}

/// Product photo when the backend has one, an icon tile when it does not or
/// the image fails to load. The price pill sits over the bottom of it.
class _Thumbnail extends StatelessWidget {
  final Product product;
  final bool soldOut;

  const _Thumbnail({required this.product, required this.soldOut});

  // Drains the colour out of an unavailable item, as the reference does.
  static const ColorFilter _greyscale = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    Widget image = _buildImage();
    if (soldOut) {
      image = ColorFiltered(colorFilter: _greyscale, child: image);
    }

    return SizedBox(
      height: 104,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.bottomCenter,
        fit: StackFit.expand,
        children: [
          image,

          // Price pill
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: soldOut ? AppTheme.mutedDark : AppTheme.violet,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  formatPrice(product.price),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImage() {
    final url = product.thumbnailUrl;
    if (url == null) return _IconTile(product: product, soldOut: soldOut);

    return Image.network(
      url,
      fit: BoxFit.cover,
      // The media store may not be configured, so a broken URL must never
      // leave a grey hole in the grid.
      errorBuilder: (_, _, _) => _IconTile(product: product, soldOut: soldOut),
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : _IconTile(product: product, soldOut: soldOut),
    );
  }
}

/// Fallback tile: a tinted block with an icon guessed from the product name.
class _IconTile extends StatelessWidget {
  final Product product;
  final bool soldOut;

  const _IconTile({required this.product, required this.soldOut});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: soldOut ? AppTheme.mutedThumb : AppTheme.violetTint,
      alignment: Alignment.center,
      padding: const EdgeInsets.only(bottom: 16),
      child: Icon(
        _iconFor(product.name),
        size: 40,
        color: soldOut ? AppTheme.mutedDark : AppTheme.violet,
      ),
    );
  }

  /// Purely decorative — the backend has no category field, so the icon is
  /// guessed from the name and falls back to a generic one.
  static IconData _iconFor(String name) {
    final n = name.toLowerCase();
    if (n.contains('pizza')) return Icons.local_pizza;
    if (n.contains('burger')) return Icons.lunch_dining;
    if (n.contains('roll') || n.contains('shawarma')) return Icons.kebab_dining;
    if (n.contains('fries')) return Icons.fastfood;
    if (n.contains('rice') || n.contains('biryani')) return Icons.rice_bowl;
    if (n.contains('momo') || n.contains('manchurian')) {
      return Icons.ramen_dining;
    }
    if (n.contains('bread')) return Icons.bakery_dining;
    if (n.contains('coffee')) return Icons.coffee;
    if (n.contains('chai') || n.contains('tea')) {
      return Icons.emoji_food_beverage;
    }
    if (n.contains('lemonade') || n.contains('juice')) {
      return Icons.local_drink;
    }
    if (n.contains('brownie') || n.contains('jamun') || n.contains('cake')) {
      return Icons.cake;
    }
    return Icons.restaurant_menu;
  }
}

/// "24 available" / "Only 3 left" / "Out of stock", driven by the live `qty`.
class _StockLabel extends StatelessWidget {
  final Product product;
  final bool soldOut;

  const _StockLabel({required this.product, required this.soldOut});

  @override
  Widget build(BuildContext context) {
    final (String label, Color color) = switch (product.qty) {
      <= 0 => ('OUT OF STOCK', AppTheme.danger),
      <= 5 => ('ONLY ${product.qty} LEFT', AppTheme.warning),
      _ => ('${product.qty} AVAILABLE', AppTheme.success),
    };

    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTheme.kicker.copyWith(
        fontSize: 9,
        color: soldOut ? AppTheme.mutedDark : color,
      ),
    );
  }
}
