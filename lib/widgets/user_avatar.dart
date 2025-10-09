import 'package:flutter/material.dart';

class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    this.url,
    required this.size,
    this.overrideProvider,
    this.backgroundColor,
    this.iconColor,
  });

  final String? url;
  final double size;
  final ImageProvider? overrideProvider;
  final Color? backgroundColor;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final imageProvider = _effectiveImageProvider();

    final avatar = CircleAvatar(
      radius: size / 2,
      backgroundColor: backgroundColor,
      child: imageProvider == null
          ? _buildPlaceholder()
          : ClipOval(
              child: SizedBox(
                width: size,
                height: size,
                child: Image(
                  image: imageProvider,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      Center(child: _buildPlaceholder()),
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) {
                      return child;
                    }
                    return Center(child: _buildPlaceholder());
                  },
                ),
              ),
            ),
    );

    if (iconColor == null) {
      return avatar;
    }

    return IconTheme(
      data: IconThemeData(color: iconColor),
      child: avatar,
    );
  }

  ImageProvider? _effectiveImageProvider() {
    final override = _debugOverrideProvider();
    if (override != null) {
      return override;
    }

    if (url == null || url!.trim().isEmpty) {
      return null;
    }

    return NetworkImage(url!.trim());
  }

  Widget _buildPlaceholder() {
    return Icon(
      Icons.person,
      size: size * 0.6,
    );
  }

  ImageProvider? _debugOverrideProvider() {
    if (overrideProvider == null) {
      return null;
    }

    var useOverride = false;
    assert(() {
      useOverride = true;
      return true;
    }());

    return useOverride ? overrideProvider : null;
  }
}
