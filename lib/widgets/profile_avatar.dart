import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Round avatar: network photo when available, otherwise initial / guest glyph.
class ProfileAvatar extends StatelessWidget {
  final double size;
  final String? imageUrl;
  final String? label;

  const ProfileAvatar({super.key, this.size = 36, this.imageUrl, this.label});

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    final initial = (label ?? '').trim();
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppColors.accentGradient,
      ),
      alignment: Alignment.center,
      child: initial.isEmpty
          ? Icon(Icons.person_outline_rounded,
              size: size * 0.55, color: Colors.white)
          : Text(
              initial.substring(0, 1).toUpperCase(),
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.42,
                fontWeight: FontWeight.w800,
              ),
            ),
    );
    if (url == null || url.isEmpty) return fallback;
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallback,
          loadingBuilder: (ctx, child, progress) =>
              progress == null ? child : fallback,
        ),
      ),
    );
  }
}
