import 'package:flutter/material.dart';

import '../services/api_service.dart';
import 'app_theme.dart';

/// Short confirmation message.
void showSnack(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Shows a failure. [error] is expected to be an [ApiException]; anything else
/// falls back to a generic line so a raw exception never reaches the user.
void showErrorSnack(BuildContext context, Object error) {
  if (!context.mounted) return;
  final message = error is ApiException
      ? error.message
      : 'Something went wrong. Please try again.';
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppTheme.danger),
    );
}

/// Formats a price the way the backend stores it — whole rupees.
String formatPrice(num amount) => '₹${amount.toStringAsFixed(0)}';
