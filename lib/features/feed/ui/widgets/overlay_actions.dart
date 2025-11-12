import 'package:coalition_app_v2/widgets/user_avatar.dart';
import 'package:flutter/material.dart';

class OverlayActions extends StatelessWidget {
  const OverlayActions({
    super.key,
    this.avatarUrl,
    required this.onProfileTap,
    required this.onCommentsTap,
    required this.onFavoriteTap,
    this.onFavoriteLongPress,
    required this.onLikersTap,
    required this.onShareTap,
    required this.isFavorite,
    required this.likeCount,
  });

  final String? avatarUrl;
  final VoidCallback onProfileTap;
  final VoidCallback onCommentsTap;
  final VoidCallback onFavoriteTap;
  final VoidCallback? onFavoriteLongPress;
  final VoidCallback onLikersTap;
  final VoidCallback onShareTap;
  final bool isFavorite;
  final int likeCount;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
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
              backgroundColor:
                  colorScheme.onSurface.withValues(alpha: 0.24),
              iconColor: colorScheme.onSurface,
            ),
          ),
        ),
        const SizedBox(height: 18),
        _ActionIcon(
          icon: Icons.message_outlined,
          onTap: onCommentsTap,
          semanticsLabel: 'Open comments',
        ),
        const SizedBox(height: 14),
        _ActionIcon(
          icon: isFavorite ? Icons.favorite : Icons.favorite_border,
          onTap: onFavoriteTap,
          onLongPress: onFavoriteLongPress,
          semanticsLabel: isFavorite ? 'Unlike' : 'Like',
          iconColor: isFavorite
              ? colorScheme.error
              : colorScheme.onSurface,
        ),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: onLikersTap,
          child: Text(
            _formatLikeCount(likeCount),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
          ),
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
    this.iconColor,
    this.onLongPress,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String semanticsLabel;
  final Color? iconColor;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveIconColor = iconColor ?? colorScheme.onSurface;
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: Material(
        color: colorScheme.onSurface.withValues(alpha: 0.24),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Icon(icon, color: effectiveIconColor, size: 26),
          ),
        ),
      ),
    );
  }
}

String _formatLikeCount(int count) {
  if (count >= 1000000) {
    return '${_trimmedFixed(count / 1000000)}M';
  }
  if (count >= 1000) {
    return '${_trimmedFixed(count / 1000)}K';
  }
  return count.toString();
}

String _trimmedFixed(double value) {
  final text = value.toStringAsFixed(1);
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}
