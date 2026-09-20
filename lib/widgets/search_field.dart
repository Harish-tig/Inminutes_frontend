import 'package:flutter/material.dart';

import '../utils/app_theme.dart';

/// Menu search. Filtering happens on the list already in memory — the backend
/// has no search endpoint and the catalogue is small.
class SearchField extends StatelessWidget {
  final ValueChanged<String> onChanged;
  final String hint;

  const SearchField({
    super.key,
    required this.onChanged,
    this.hint = 'Search the menu',
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      style: const TextStyle(color: AppTheme.textDark),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 14),
        prefixIcon: const Icon(Icons.search, color: AppTheme.textMuted, size: 20),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
