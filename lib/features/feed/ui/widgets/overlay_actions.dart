import 'package:coalition_app_v2/widgets/user_avatar.dart';
import 'package:flutter/material.dart';

class OverlayActions extends StatelessWidget {
  const OverlayActions({
    super.key,
    this.avatarUrl,
    required this.onProfileTap,
    required this.onCommentsTap,
    required this.onFavoriteTap,
    required this.onShareTap,
    required this.isFavorite,
  });

  final String? avatarUrl;
  final VoidCallback onProfileTap;
  final VoidCallback onCommentsTap;
  final VoidCallback onFavoriteTap;
  final VoidCallback onShareTap;
  final bool isFavorite;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          label: 'View profile',
          child: InkWell(
            onTap: onProfileTap,
            customBorder: const CircleBorder(),
            child: UserAvatar(
              url: avatarUrl,
              size: 52,
              backgroundColor: Colors.white24,
              iconColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 18),
        _ActionIcon(
          icon: Icons.message_outlined,
          onTap: onCommentsTap,
          semanticsLabel: 'Open comments (coming soon)',
        ),
        const SizedBox(height: 14),
        _ActionIcon(
          icon: isFavorite ? Icons.favorite : Icons.favorite_border,
          onTap: onFavoriteTap,
          semanticsLabel: isFavorite ? 'Unlike' : 'Like',
          iconColor: isFavorite ? Colors.redAccent : Colors.white,
        ),
        const SizedBox(height: 14),
        _ActionIcon(
          icon: Icons.share,
          onTap: onShareTap,
          semanticsLabel: 'Share (coming soon)',
        ),
      ],
    );
  }
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({
    required this.icon,
    required this.onTap,
    required this.semanticsLabel,
    this.iconColor = Colors.white,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String semanticsLabel;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: Material(
        color: Colors.white24,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Icon(icon, color: iconColor, size: 26),
          ),
        ),
      ),
    );
  }
}
