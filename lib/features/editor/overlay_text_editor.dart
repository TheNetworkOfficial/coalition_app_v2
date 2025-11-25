import 'package:flutter/material.dart';

import '../../models/edit_manifest.dart';

const _kOverlayMinScale = 0.5;
const _kOverlayMaxScale = 3.0;

Future<OverlayTextOp?> showOverlayTextEditor({
  required BuildContext context,
  required Duration total,
  OverlayTextOp? initial,
}) {
  return showModalBottomSheet<OverlayTextOp>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _OverlayTextEditorSheet(total: total, initial: initial),
      );
    },
  );
}

class _OverlayTextEditorSheet extends StatefulWidget {
  const _OverlayTextEditorSheet({required this.total, this.initial});

  final Duration total;
  final OverlayTextOp? initial;

  @override
  State<_OverlayTextEditorSheet> createState() => _OverlayTextEditorSheetState();
}

class _OverlayTextEditorSheetState extends State<_OverlayTextEditorSheet> {
  late final TextEditingController _textController;
  late double _x;
  late double _y;
  late double _scale;
  late double _rotation;
  late int _startMs;
  late int _endMs;
  late String _colorHex;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    final totalMs = _maxDurationMs;
    _textController = TextEditingController(text: initial?.text ?? '');
    _x = (initial?.x ?? 0.5).clamp(0.0, 1.0);
    _y = (initial?.y ?? 0.5).clamp(0.0, 1.0);
    _scale = initial?.scale ?? 1.0;
    _rotation = (initial?.rotationDeg ?? 0).toDouble().clamp(-180.0, 180.0);
    _startMs = (initial?.startMs ?? 0).clamp(0, totalMs);
    _endMs = (initial?.endMs ?? totalMs).clamp(_startMs, totalMs);
    _colorHex = initial?.color ?? _overlayColorOptions.first.hex;
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  int get _maxDurationMs {
    final total = widget.total.inMilliseconds;
    if (total <= 0) {
      return 1;
    }
    return total;
  }

  bool get _canApply => _textController.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Add Text', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _textController,
              textInputAction: TextInputAction.done,
              maxLines: 1,
              decoration: const InputDecoration(
                labelText: 'Overlay Text',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            Text('Color', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _overlayColorOptions.map((option) {
                final selected = option.hex == _colorHex;
                return ChoiceChip(
                  label: Text(option.label),
                  selected: selected,
                  avatar: CircleAvatar(backgroundColor: option.color),
                  onSelected: (_) => setState(() => _colorHex = option.hex),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            _buildSlider(
              label: 'Horizontal (X): ${_x.toStringAsFixed(3)}',
              value: _x,
              min: 0,
              max: 1,
              onChanged: (value) => setState(() => _x = value),
            ),
            _buildSlider(
              label: 'Vertical (Y): ${_y.toStringAsFixed(3)}',
              value: _y,
              min: 0,
              max: 1,
              onChanged: (value) => setState(() => _y = value),
            ),
            _buildSlider(
              label: 'Scale: ${_scale.toStringAsFixed(2)}x',
              value: _scale,
              min: _kOverlayMinScale,
              max: _kOverlayMaxScale,
              onChanged: (value) => setState(() => _scale = value),
            ),
            _buildSlider(
              label: 'Rotation: ${_rotation.round()}°',
              value: _rotation,
              min: -180,
              max: 180,
              onChanged: (value) => setState(() => _rotation = value),
            ),
            const SizedBox(height: 16),
            Text(
              'Visible: ${_formatDuration(_startMs)} - ${_formatDuration(_endMs)}',
              style: theme.textTheme.titleMedium,
            ),
            RangeSlider(
              min: 0,
              max: _maxDurationMs.toDouble(),
              values: RangeValues(
                _startMs.toDouble(),
                _endMs.toDouble(),
              ),
              divisions: widget.total.inSeconds > 0 ? widget.total.inSeconds : null,
              labels: RangeLabels(
                _formatDuration(_startMs),
                _formatDuration(_endMs),
              ),
              onChanged: (values) {
                final start = values.start.round().clamp(0, _maxDurationMs);
                final end = values.end.round().clamp(start, _maxDurationMs);
                setState(() {
                  _startMs = start;
                  _endMs = end;
                });
              },
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _canApply ? _handleApply : null,
                  child: const Text('Apply'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        Slider(
          value: value,
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ],
    );
  }

  void _handleApply() {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      return;
    }
    final normalizedX = _roundToThreeDecimals(_x.clamp(0.0, 1.0));
    final normalizedY = _roundToThreeDecimals(_y.clamp(0.0, 1.0));
    final normalizedScale = _roundToThreeDecimals(
      _scale.clamp(_kOverlayMinScale, _kOverlayMaxScale),
    );
    final rotation = _rotation.round().clamp(-180, 180);
    final overlay = OverlayTextOp(
      text: text,
      x: normalizedX,
      y: normalizedY,
      scale: normalizedScale,
      rotationDeg: rotation,
      startMs: _startMs,
      endMs: _endMs,
      color: _colorHex,
    );
    Navigator.of(context).pop(overlay);
  }

  double _roundToThreeDecimals(double value) {
    return (value * 1000).roundToDouble() / 1000;
  }

  String _formatDuration(int milliseconds) {
    final duration = Duration(milliseconds: milliseconds);
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = duration.inHours;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }
}

class _OverlayColorOption {
  const _OverlayColorOption(this.label, this.hex, this.color);

  final String label;
  final String hex;
  final Color color;
}

const List<_OverlayColorOption> _overlayColorOptions = [
  _OverlayColorOption('White', '#FFFFFF', Colors.white),
  _OverlayColorOption('Black', '#000000', Colors.black),
  _OverlayColorOption('Red', '#FF3A30', Colors.red),
  _OverlayColorOption('Yellow', '#FFCC00', Colors.yellow),
  _OverlayColorOption('Cyan', '#00C7FF', Colors.cyan),
];
