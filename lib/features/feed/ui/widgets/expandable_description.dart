import 'package:flutter/material.dart';

/// Displays the poster name with a small snippet of the description.
/// Tapping the snippet expands an overlay sheet that shows the full text.
class ExpandableDescription extends StatefulWidget {
  const ExpandableDescription({
    super.key,
    required this.displayName,
    this.description,
    this.onDisplayNameTap,
  });

  final String displayName;
  final String? description;
  final VoidCallback? onDisplayNameTap;

  @override
  State<ExpandableDescription> createState() => _ExpandableDescriptionState();
}

class _ExpandableDescriptionState extends State<ExpandableDescription> {
  OverlayEntry? _overlayEntry;

  bool get _hasDescription {
    final description = widget.description;
    return description != null && description.trim().isNotEmpty;
  }

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  void _showOverlay() {
    if (!_hasDescription || _overlayEntry != null) {
      return;
    }
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) {
      return;
    }

    _overlayEntry = OverlayEntry(
      builder: (_) => _DescriptionOverlay(
        displayName: widget.displayName,
        description: widget.description!.trim(),
        onClose: _removeOverlay,
      ),
    );
    overlay.insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: widget.onDisplayNameTap,
          child: Text(
            widget.displayName,
            style: theme.textTheme.titleMedium?.copyWith(
              color: onSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (_hasDescription) ...[
          const SizedBox(height: 8),
          Semantics(
            button: true,
            label: 'Show more about ${widget.displayName}',
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _showOverlay,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.description!.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'More',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: onSurface.withValues(alpha: 0.70),
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _DescriptionOverlay extends StatelessWidget {
  const _DescriptionOverlay({
    required this.displayName,
    required this.description,
    required this.onClose,
  });

  final String displayName;
  final String description;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onClose,
        child: Material(
          color: colorScheme.scrim.withValues(alpha: 0.70),
          child: SafeArea(
            minimum: const EdgeInsets.all(16),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              displayName,
                              style: theme.textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    color: colorScheme.onSurface,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ),
                          IconButton(
                            onPressed: onClose,
                            color: colorScheme.onSurface
                                .withValues(alpha: 0.70),
                            tooltip: 'Close description',
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        description,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
