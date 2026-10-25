import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../utils/password_strength.dart';

/// Password + confirm fields with strength meter and generate action.
class PasswordFormFields extends StatelessWidget {
  const PasswordFormFields({
    super.key,
    required this.password,
    required this.confirm,
    required this.onChanged,
    this.enabled = true,
    this.autofillNewPassword = true,
  });

  final TextEditingController password;
  final TextEditingController confirm;
  final VoidCallback onChanged;
  final bool enabled;
  final bool autofillNewPassword;

  @override
  Widget build(BuildContext context) {
    final score = PasswordStrength.score(password.text);
    final match = confirm.text.isEmpty || confirm.text == password.text;
    final barColor = switch (score) {
      0 || 1 => AppColors.red,
      2 => AppColors.amber,
      3 => AppColors.cyanDim,
      _ => AppColors.green,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: password,
          obscureText: true,
          enabled: enabled,
          onChanged: (_) => onChanged(),
          autofillHints: autofillNewPassword
              ? const [AutofillHints.newPassword]
              : const [AutofillHints.password],
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(
            labelText: 'New password',
            labelStyle: TextStyle(color: AppColors.textMuted),
          ),
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: score / 4,
            minHeight: 6,
            backgroundColor: AppColors.border,
            color: barColor,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          password.text.isEmpty
              ? 'Use 8+ characters with mixed case, a number, and a symbol.'
              : PasswordStrength.label(score),
          style: TextStyle(color: barColor, fontSize: 12),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: !enabled
                ? null
                : () {
                    final generated = PasswordStrength.generate();
                    password.text = generated;
                    confirm.text = generated;
                    Clipboard.setData(ClipboardData(text: generated));
                    onChanged();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Strong password generated and copied to clipboard.',
                        ),
                      ),
                    );
                  },
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: const Text('Generate strong password'),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: confirm,
          obscureText: true,
          enabled: enabled,
          onChanged: (_) => onChanged(),
          autofillHints: autofillNewPassword
              ? const [AutofillHints.newPassword]
              : const [AutofillHints.password],
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            labelText: 'Confirm password',
            labelStyle: const TextStyle(color: AppColors.textMuted),
            errorText: match ? null : 'Passwords do not match',
          ),
        ),
      ],
    );
  }
}
