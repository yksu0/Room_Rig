import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Compact honesty strip for Scan (and similar approximate modes).
class ScanHonestyBanner extends StatelessWidget {
  final String summary;
  final bool compact;

  const ScanHonestyBanner({
    super.key,
    required this.summary,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.amber.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(Icons.science_outlined, size: compact ? 14 : 16, color: AppColors.amber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              summary,
              style: TextStyle(
                color: AppColors.amber,
                fontSize: compact ? 10 : 11,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
