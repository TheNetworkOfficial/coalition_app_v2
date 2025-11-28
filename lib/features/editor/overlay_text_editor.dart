import 'package:flutter/material.dart';

import '../../models/edit_manifest.dart';

enum _TextEditorTab { style, color, background }

class OverlayTextEditorOverlay extends StatefulWidget {
  const OverlayTextEditorOverlay({
    Key? key,
    required this.initialOverlay,
    required this.videoDurationMs,
    required this.onChanged,
    required this.onDone,
    required this.onCancel,
  }) : super(key: key);

  final OverlayTextOp initialOverlay;
  final int videoDurationMs;
  final ValueChanged<OverlayTextOp> onChanged;
  final ValueChanged<OverlayTextOp> onDone;
  final VoidCallback onCancel;

  @override
  State<OverlayTextEditorOverlay> createState() =>
      _OverlayTextEditorOverlayState();
}

class _OverlayTextEditorOverlayState extends State<OverlayTextEditorOverlay> {
  late TextEditingController _textController;
  late RangeValues _visibleRange;
  late String _textColorHex;
  String? _backgroundColorHex;
  String? _fontFamily;
  _TextEditorTab _selectedTab = _TextEditorTab.style;
  bool _suspendTextListener = false;

  @override
  void initState() {
    super.initState();
    final overlay = widget.initialOverlay;
    final totalMs = widget.videoDurationMs > 0 ? widget.videoDurationMs : 1;
    _textController = TextEditingController(text: overlay.text);
    _textController.addListener(_handleTextChanged);
    _textColorHex = overlay.color ?? _overlayColorOptions.first.hex;
    _backgroundColorHex = overlay.backgroundColorHex;
    _fontFamily = overlay.fontFamily;
    final start = (overlay.startMs ?? 0).clamp(0, totalMs);
    final end = (overlay.endMs ?? totalMs).clamp(start, totalMs);
    _visibleRange = RangeValues(
      start.toDouble(),
      end.toDouble(),
    );
  }

  @override
  void didUpdateWidget(covariant OverlayTextEditorOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialOverlay == widget.initialOverlay &&
        oldWidget.videoDurationMs == widget.videoDurationMs) {
      return;
    }
    final overlay = widget.initialOverlay;
    final totalMs = widget.videoDurationMs > 0 ? widget.videoDurationMs : 1;
    final start = (overlay.startMs ?? 0).clamp(0, totalMs);
    final end = (overlay.endMs ?? totalMs).clamp(start, totalMs);
    final nextRange = RangeValues(start.toDouble(), end.toDouble());

    _suspendTextListener = true;
    if (_textController.text != overlay.text) {
      _textController.text = overlay.text;
    }
    _suspendTextListener = false;

    final nextTextColor = overlay.color ?? _overlayColorOptions.first.hex;
    if (_visibleRange != nextRange ||
        _textColorHex != nextTextColor ||
        _backgroundColorHex != overlay.backgroundColorHex ||
        _fontFamily != overlay.fontFamily) {
      setState(() {
        _visibleRange = nextRange;
        _textColorHex = nextTextColor;
        _backgroundColorHex = overlay.backgroundColorHex;
        _fontFamily = overlay.fontFamily;
      });
    }
  }

  @override
  void dispose() {
    _textController.removeListener(_handleTextChanged);
    _textController.dispose();
    super.dispose();
  }

  OverlayTextOp _currentOverlay() {
    return widget.initialOverlay.copyWith(
      text: _textController.text,
      color: _textColorHex,
      backgroundColorHex: _backgroundColorHex,
      fontFamily: _fontFamily,
      startMs: _visibleRange.start.toInt(),
      endMs: _visibleRange.end.toInt(),
    );
  }

  void _handleTextChanged() {
    if (_suspendTextListener) {
      return;
    }
    _notifyChanged();
  }

  void _notifyChanged() {
    widget.onChanged(_currentOverlay());
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          widget.onCancel();
        }
      },
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(color: Colors.black.withValues(alpha: 0.35)),
            ),
            Align(
              alignment: Alignment.topCenter,
              child: SafeArea(
                top: true,
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: _buildTopToolbar(),
                ),
              ),
            ),
            _buildPositionedTextField(),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildTabContent(),
                    const SizedBox(height: 8),
                    _buildVisibleSlider(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopToolbar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: widget.onCancel,
        ),
        Row(
          children: [
            _buildTabIcon(
              tab: _TextEditorTab.style,
              icon: Icons.text_fields,
            ),
            _buildTabIcon(
              tab: _TextEditorTab.color,
              icon: Icons.color_lens,
            ),
            _buildTabIcon(
              tab: _TextEditorTab.background,
              icon: Icons.format_color_fill,
            ),
          ],
        ),
        TextButton(
          onPressed: _onDonePressed,
          child: const Text('Done'),
        ),
      ],
    );
  }

  Widget _buildTabIcon({
    required _TextEditorTab tab,
    required IconData icon,
  }) {
    final isSelected = _selectedTab == tab;
    return IconButton(
      onPressed: () {
        setState(() {
          _selectedTab = tab;
        });
      },
      icon: Icon(
        icon,
        color: isSelected
            ? Theme.of(context).colorScheme.primary
            : Colors.white,
      ),
    );
  }

  Widget _buildPositionedTextField() {
    final textColor = _parseColorHex(_textColorHex) ?? Colors.white;
    final backgroundColor = _backgroundColorHex != null
        ? _parseColorHex(_backgroundColorHex!)
        : null;

    return Align(
      alignment: Alignment(
        widget.initialOverlay.x * 2 - 1,
        widget.initialOverlay.y * 2 - 1,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: backgroundColor != null
              ? BoxDecoration(
                  color: backgroundColor.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(8),
                )
              : null,
          child: TextField(
            controller: _textController,
            autofocus: true,
            maxLines: null,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: textColor,
              fontFamily: _fontFamily,
            ),
            decoration: const InputDecoration(
              border: InputBorder.none,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabContent() {
    final textColor = _parseColorHex(_textColorHex) ?? Colors.white;
    final backgroundColor = _backgroundColorHex != null
        ? _parseColorHex(_backgroundColorHex!)
        : null;
    switch (_selectedTab) {
      case _TextEditorTab.style:
        return _buildStyleTab(textColor);
      case _TextEditorTab.color:
        return _buildTextColorTab();
      case _TextEditorTab.background:
        return _buildBackgroundTab(backgroundColor);
    }
  }

  Widget _buildStyleTab(Color textColor) {
    return SizedBox(
      height: 64,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _fontOptions.map((option) {
            final selected = option.fontFamily == _fontFamily;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(
                  'Aa',
                  style: TextStyle(
                    fontFamily: option.fontFamily,
                    color: textColor,
                  ),
                ),
                selected: selected,
                onSelected: (_) => _updateFontFamily(option.fontFamily),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildTextColorTab() {
    return SizedBox(
      height: 64,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _overlayColorOptions.map((option) {
            final selected = option.hex == _textColorHex;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(
                  option.label,
                  style: const TextStyle(color: Colors.white),
                ),
                selected: selected,
                avatar: CircleAvatar(backgroundColor: option.color),
                onSelected: (_) => _updateTextColor(option.hex),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildBackgroundTab(Color? backgroundColor) {
    final selectedColor = backgroundColor != null
        ? backgroundColor.withValues(alpha: 0.35)
        : Colors.white12;
    return SizedBox(
      height: 64,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: const Text(
                  'None',
                  style: TextStyle(color: Colors.white),
                ),
                selected: _backgroundColorHex == null,
                selectedColor: selectedColor,
                onSelected: (_) => _updateBackgroundColor(null),
              ),
            ),
            ..._overlayColorOptions.map((option) {
              final selected = option.hex == _backgroundColorHex;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(
                    option.label,
                    style: const TextStyle(color: Colors.white),
                  ),
                  selected: selected,
                  selectedColor: selectedColor,
                  avatar: CircleAvatar(backgroundColor: option.color),
                  onSelected: (_) => _updateBackgroundColor(option.hex),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildVisibleSlider() {
    final double maxRange =
        widget.videoDurationMs > 0 ? widget.videoDurationMs.toDouble() : 1.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Visible: ${_formatMs(_visibleRange.start.toInt())} - '
            '${_formatMs(_visibleRange.end.toInt())}',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.white),
          ),
        ),
        RangeSlider(
          min: 0.0,
          max: maxRange,
          values: RangeValues(
            _visibleRange.start.clamp(0.0, maxRange),
            _visibleRange.end.clamp(0.0, maxRange),
          ),
          onChanged: (values) {
            final clampedStart = values.start.clamp(0.0, maxRange);
            final clampedEnd = values.end.clamp(clampedStart, maxRange);
            setState(() {
              _visibleRange = RangeValues(clampedStart, clampedEnd);
            });
            _notifyChanged();
          },
        ),
      ],
    );
  }

  void _updateTextColor(String hex) {
    setState(() {
      _textColorHex = hex;
    });
    _notifyChanged();
  }

  void _updateBackgroundColor(String? hex) {
    setState(() {
      _backgroundColorHex = hex;
    });
    _notifyChanged();
  }

  void _updateFontFamily(String? fontFamily) {
    setState(() {
      _fontFamily = fontFamily;
    });
    _notifyChanged();
  }

  void _onDonePressed() {
    widget.onDone(_currentOverlay());
  }
}

class _OverlayColorOption {
  const _OverlayColorOption(this.label, this.hex, this.color);

  final String label;
  final String hex;
  final Color color;
}

class _FontOption {
  const _FontOption({required this.label, this.fontFamily});

  final String label;
  final String? fontFamily;
}

const List<_OverlayColorOption> _overlayColorOptions = [
  _OverlayColorOption('White', '#FFFFFF', Colors.white),
  _OverlayColorOption('Black', '#000000', Colors.black),
  _OverlayColorOption('Red', '#FF3A30', Colors.red),
  _OverlayColorOption('Yellow', '#FFCC00', Colors.yellow),
  _OverlayColorOption('Cyan', '#00C7FF', Colors.cyan),
  _OverlayColorOption('Green', '#34C759', Colors.green),
  _OverlayColorOption('Purple', '#AF52DE', Colors.purple),
];

const _fontOptions = <_FontOption>[
  _FontOption(label: 'Default', fontFamily: null),
  _FontOption(label: 'Serif', fontFamily: 'serif'),
  _FontOption(label: 'Mono', fontFamily: 'monospace'),
  _FontOption(label: 'Display', fontFamily: 'fantasy'),
];

Color? _parseColorHex(String? hex) {
  if (hex == null || hex.length != 7 || !hex.startsWith('#')) {
    return null;
  }
  final value = int.tryParse(hex.substring(1), radix: 16);
  if (value == null) {
    return null;
  }
  return Color(0xFF000000 | value);
}

String _formatMs(int milliseconds) {
  final duration = Duration(milliseconds: milliseconds);
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  final hours = duration.inHours;
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:$minutes:$seconds';
  }
  return '$minutes:$seconds';
}
