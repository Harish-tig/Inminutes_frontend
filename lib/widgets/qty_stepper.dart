import 'package:flutter/material.dart';

import '../utils/app_theme.dart';

/// − 2 +  control, styled to sit in the same footprint as the ADD button.
///
/// It fills whatever box its parent gives it, so callers size it with a
/// [SizedBox] rather than it choosing its own height.
class QtyStepper extends StatelessWidget {
  final int qty;
  final VoidCallback? onDecrease;
  final VoidCallback? onIncrease;

  const QtyStepper({
    super.key,
    required this.qty,
    this.onDecrease,
    this.onIncrease,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.violet,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        // Hard offset, no blur — the same depth the ADD button has.
        boxShadow: const [
          BoxShadow(color: AppTheme.violetDeep, offset: Offset(0, 3)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // − becomes a delete icon on the last unit
          _StepButton(
            icon: qty == 1 ? Icons.delete_outline : Icons.remove,
            onPressed: onDecrease,
          ),
          Text(
            '$qty',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w900,
              fontStyle: FontStyle.italic,
            ),
          ),
          _StepButton(icon: Icons.add, onPressed: onIncrease),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;

  const _StepButton({required this.icon, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Icon(
          icon,
          size: 18,
          // Dimmed rather than hidden, so the control does not jump around.
          color: onPressed == null ? Colors.white38 : Colors.white,
        ),
      ),
    );
  }
}
