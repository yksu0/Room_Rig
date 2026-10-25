import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Single password [TextField] with a show/hide suffix toggle.
class PasswordVisibilityField extends StatefulWidget {
  const PasswordVisibilityField({
    super.key,
    required this.controller,
    required this.label,
    this.enabled = true,
    this.onChanged,
    this.autofillHints = const [AutofillHints.password],
    this.errorText,
  });

  final TextEditingController controller;
  final String label;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final Iterable<String>? autofillHints;
  final String? errorText;

  @override
  State<PasswordVisibilityField> createState() =>
      _PasswordVisibilityFieldState();
}

class _PasswordVisibilityFieldState extends State<PasswordVisibilityField> {
  var _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: _obscure,
      enabled: widget.enabled,
      onChanged: widget.onChanged,
      autofillHints: widget.autofillHints,
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: widget.label,
        labelStyle: const TextStyle(color: AppColors.textMuted),
        errorText: widget.errorText,
        suffixIcon: IconButton(
          tooltip: _obscure ? 'Show password' : 'Hide password',
          onPressed: widget.enabled
              ? () => setState(() => _obscure = !_obscure)
              : null,
          icon: Icon(
            _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            color: AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}
