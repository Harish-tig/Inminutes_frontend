import 'package:flutter/material.dart';

import '../utils/app_theme.dart';

/// The reference's signature call to action: a slightly tapered block sitting
/// on a darker offset one. Used for the ADD / NO STOCK button on product cards.
class TaperedButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const TaperedButton({super.key, required this.label, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final face = enabled ? AppTheme.violet : AppTheme.muted;
    final shadow = enabled ? AppTheme.violetDeep : AppTheme.mutedDark;

    return SizedBox(
      height: 40,
      child: Stack(
        children: [
          // Offset block behind, which is what gives the button its depth
          Positioned(
            left: 0,
            right: 0,
            top: 4,
            bottom: 0,
            child: ClipPath(
              clipper: const _TaperClipper(),
              child: ColoredBox(color: shadow),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            bottom: 4,
            child: ClipPath(
              clipper: const _TaperClipper(),
              child: Material(
                color: face,
                child: InkWell(
                  onTap: onPressed,
                  child: Center(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: enabled ? Colors.white : AppTheme.mutedDark,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        fontStyle: FontStyle.italic,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Wider at the top than the bottom, like the reference's buttons.
class _TaperClipper extends CustomClipper<Path> {
  const _TaperClipper();

  @override
  Path getClip(Size size) {
    const inset = 10.0; // how much narrower the bottom edge is, per side
    const r = 8.0;
    final w = size.width;
    final h = size.height;

    return Path()
      ..moveTo(0, r)
      ..quadraticBezierTo(0, 0, r, 0)
      ..lineTo(w - r, 0)
      ..quadraticBezierTo(w, 0, w, r)
      ..lineTo(w - inset, h - r)
      ..quadraticBezierTo(w - inset, h, w - inset - r, h)
      ..lineTo(inset + r, h)
      ..quadraticBezierTo(inset, h, inset, h - r)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
