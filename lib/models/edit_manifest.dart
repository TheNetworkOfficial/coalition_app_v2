import 'dart:convert';

abstract class EditOp {
  const EditOp({required this.type, this.startMs, this.endMs});

  final String type;
  final int? startMs;
  final int? endMs;

  Map<String, dynamic> toJson();

  EditOp copy();

  static EditOp fromJson(Map<String, dynamic> json) {
    final type = json['type']?.toString();
    switch (type) {
      case TrimOp.typeKey:
        return TrimOp(
          startMs: (json['startMs'] as num?)?.toInt() ?? 0,
          endMs: (json['endMs'] as num?)?.toInt() ?? 0,
        );
      case RotateOp.typeKey:
        return RotateOp(turns: (json['turns'] as num?)?.toInt() ?? 0);
      case CropOp.typeKey:
        return CropOp(
          left: (json['left'] as num?)?.toDouble() ?? 0,
          top: (json['top'] as num?)?.toDouble() ?? 0,
          width: (json['width'] as num?)?.toDouble() ?? 1,
          height: (json['height'] as num?)?.toDouble() ?? 1,
        );
      case SpeedOp.typeKey:
        return SpeedOp(
          factor: (json['factor'] as num?)?.toDouble() ?? 1.0,
          startMs: (json['startMs'] as num?)?.toInt(),
          endMs: (json['endMs'] as num?)?.toInt(),
        );
      case FilterOp.typeKey:
        return FilterOp(
          id: json['id']?.toString() ?? '',
          intensity: (json['intensity'] as num?)?.toDouble() ?? 1.0,
        );
      case AudioGainOp.typeKey:
        return AudioGainOp(gain: (json['gain'] as num?)?.toDouble() ?? 1.0);
      case OverlayTextOp.typeKey:
        return OverlayTextOp(
          text: json['text']?.toString() ?? '',
          x: (json['x'] as num?)?.toDouble() ?? 0,
          y: (json['y'] as num?)?.toDouble() ?? 0,
          scale: (json['scale'] as num?)?.toDouble() ?? 1.0,
          rotationDeg: (json['rotationDeg'] as num?)?.toInt() ?? 0,
          startMs: (json['startMs'] as num?)?.toInt(),
          endMs: (json['endMs'] as num?)?.toInt(),
          color: json['color'] as String?,
          fontFamily: json['fontFamily'] as String?,
        );
      default:
        throw ArgumentError('Unsupported edit op: $type');
    }
  }
}

class EditManifest {
  const EditManifest({this.version = 1, this.ops = const [], this.posterFrameMs});

  final int version;
  final List<EditOp> ops;
  final int? posterFrameMs;

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'ops': ops.map((op) => op.toJson()).toList(),
      if (posterFrameMs != null) 'posterFrameMs': posterFrameMs,
    };
  }

  factory EditManifest.fromJson(Map<String, dynamic> json) {
    final opsJson = json['ops'];
    final ops = <EditOp>[];
    if (opsJson is List) {
      for (final entry in opsJson) {
        if (entry is Map<String, dynamic>) {
          ops.add(EditOp.fromJson(entry));
        } else if (entry is Map) {
          ops.add(EditOp.fromJson(entry.map((key, value) => MapEntry(key.toString(), value))));
        }
      }
    }
    return EditManifest(
      version: (json['version'] as num?)?.toInt() ?? 1,
      ops: ops,
      posterFrameMs: (json['posterFrameMs'] as num?)?.toInt(),
    );
  }

  EditManifest copyWith({int? version, List<EditOp>? ops, int? posterFrameMs}) {
    return EditManifest(
      version: version ?? this.version,
      ops: ops ?? this.ops,
      posterFrameMs: posterFrameMs ?? this.posterFrameMs,
    );
  }

  EditManifest copy() => copyWith(ops: ops.map((op) => op.copy()).toList());

  OverlayTextOp? get firstTextOverlay {
    for (final op in ops) {
      if (op is OverlayTextOp) {
        return op;
      }
    }
    return null;
  }

  EditManifest replaceTextOverlay(OverlayTextOp op) {
    final updated = <EditOp>[];
    for (final existing in ops) {
      if (existing is OverlayTextOp) {
        continue;
      }
      updated.add(existing.copy());
    }
    updated.add(op.copy());
    return copyWith(ops: updated);
  }

  bool isTrimOnly() {
    if (ops.isEmpty) {
      return true;
    }
    if (ops.length == 1 && ops.first is TrimOp) {
      return true;
    }
    return false;
  }

  @override
  String toString() => jsonEncode(toJson());
}

class TrimOp extends EditOp {
  static const typeKey = 'trim';

  TrimOp({required int startMs, required int endMs})
      : super(type: typeKey, startMs: startMs, endMs: endMs);

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'startMs': startMs,
        'endMs': endMs,
      };

  @override
  TrimOp copy() => TrimOp(startMs: startMs ?? 0, endMs: endMs ?? 0);
}

class RotateOp extends EditOp {
  static const typeKey = 'rotate';

  RotateOp({required this.turns}) : super(type: typeKey);

  final int turns;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'turns': turns,
      };

  @override
  RotateOp copy() => RotateOp(turns: turns);
}

class CropOp extends EditOp {
  static const typeKey = 'crop';

  CropOp({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  }) : super(type: typeKey);

  final double left;
  final double top;
  final double width;
  final double height;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'left': left,
        'top': top,
        'width': width,
        'height': height,
      };

  @override
  CropOp copy() => CropOp(left: left, top: top, width: width, height: height);
}

class SpeedOp extends EditOp {
  static const typeKey = 'speed';

  SpeedOp({
    required this.factor,
    int? startMs,
    int? endMs,
  }) : super(type: typeKey, startMs: startMs, endMs: endMs);

  final double factor;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'factor': factor,
        if (startMs != null) 'startMs': startMs,
        if (endMs != null) 'endMs': endMs,
      };

  @override
  SpeedOp copy() => SpeedOp(factor: factor, startMs: startMs, endMs: endMs);
}

class FilterOp extends EditOp {
  static const typeKey = 'filter';

  FilterOp({required this.id, this.intensity = 1.0}) : super(type: typeKey);

  final String id;
  final double intensity;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'id': id,
        'intensity': intensity,
      };

  @override
  FilterOp copy() => FilterOp(id: id, intensity: intensity);
}

class AudioGainOp extends EditOp {
  static const typeKey = 'audio_gain';

  AudioGainOp({required this.gain}) : super(type: typeKey);

  final double gain;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'gain': gain,
      };

  @override
  AudioGainOp copy() => AudioGainOp(gain: gain);
}

class OverlayTextOp extends EditOp {
  static const typeKey = 'overlay_text';

  OverlayTextOp({
    required this.text,
    required this.x,
    required this.y,
    required this.scale,
    required this.rotationDeg,
    int? startMs,
    int? endMs,
    this.color,
    this.fontFamily,
  }) : super(type: typeKey, startMs: startMs, endMs: endMs);

  final String text;
  final double x;
  final double y;
  final double scale;
  final int rotationDeg;
  final String? color;
  final String? fontFamily;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'text': text,
        'x': x,
        'y': y,
        'scale': scale,
        'rotationDeg': rotationDeg,
        if (startMs != null) 'startMs': startMs,
        if (endMs != null) 'endMs': endMs,
        if (color != null) 'color': color,
        if (fontFamily != null) 'fontFamily': fontFamily,
      };

  @override
  OverlayTextOp copy() => OverlayTextOp(
        text: text,
        x: x,
        y: y,
        scale: scale,
        rotationDeg: rotationDeg,
        startMs: startMs,
        endMs: endMs,
        color: color,
        fontFamily: fontFamily,
      );
}
