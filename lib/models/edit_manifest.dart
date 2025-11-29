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
        return OverlayTextOp.fromJson(json);
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

  /// Attempts to parse a raw editTimeline (string, map, or double-encoded string)
  /// into an [EditManifest]. Returns null if the payload is missing or invalid.
  static EditManifest? tryParseFromRawTimeline(dynamic raw) {
    final decoded = _decodeTimeline(raw);
    if (decoded == null) return null;
    try {
      return EditManifest.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  /// Parses the raw editTimeline into a Map, handling both map inputs and
  /// single/double-encoded JSON strings. Returns null if it cannot be parsed.
  static Map<String, dynamic>? parseTimelineMap(dynamic value) {
    return _decodeTimeline(value);
  }

  static Map<String, dynamic>? _decodeTimeline(dynamic raw) {
    if (raw == null) return null;

    dynamic decoded = raw;

    try {
      if (decoded is String) {
        decoded = jsonDecode(decoded);
        if (decoded is String) {
          decoded = jsonDecode(decoded);
        }
      }
    } catch (_) {
      return null;
    }

    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.map((key, v) => MapEntry(key.toString(), v));
    }
    return null;
  }

  /// Converts the raw editTimeline to a JSON string if possible. Accepts maps
  /// or already-encoded strings; returns null if it cannot produce a string.
  static String? stringifyTimeline(dynamic value) {
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    if (value is Map<String, dynamic>) {
      return jsonEncode(value);
    }
    if (value is Map) {
      return jsonEncode(value.map((key, v) => MapEntry(key.toString(), v)));
    }
    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'ops': ops.map((op) => op.toJson()).toList(),
      'overlayTextOps': overlayTextOps.map((op) => op.toJson()).toList(),
      if (posterFrameMs != null) 'posterFrameMs': posterFrameMs,
    };
  }

  factory EditManifest.fromJson(Map<String, dynamic> json) {
    final ops = <EditOp>[];

    bool _looksLikeOverlay(Map<String, dynamic> map) {
      final type = map['type']?.toString();
      if (type == OverlayTextOp.typeKey) {
        return true;
      }
      if (type == null) {
        return map.containsKey('text') &&
            (map.containsKey('x') || map.containsKey('y') || map.containsKey('scale'));
      }
      return false;
    }

    final overlayOpsJson = json['overlayTextOps'];
    if (overlayOpsJson is List) {
      for (final entry in overlayOpsJson) {
        if (entry is Map<String, dynamic>) {
          ops.add(OverlayTextOp.fromJson(entry));
        } else if (entry is Map) {
          ops.add(OverlayTextOp.fromJson(
              entry.map((key, value) => MapEntry(key.toString(), value))));
        }
      }
    }

    final parsedOverlayCount = ops.whereType<OverlayTextOp>().length;

    final opsJson = json['ops'];
    if (opsJson is List) {
      for (final entry in opsJson) {
        if (entry is Map<String, dynamic>) {
          if (_looksLikeOverlay(entry)) {
            if (parsedOverlayCount > 0) continue;
            ops.add(OverlayTextOp.fromJson(entry));
            continue;
          }
          try {
            ops.add(EditOp.fromJson(entry));
          } catch (_) {}
        } else if (entry is Map) {
          final mapped = entry.map((key, value) => MapEntry(key.toString(), value));
          if (_looksLikeOverlay(mapped)) {
            if (parsedOverlayCount > 0) continue;
            ops.add(OverlayTextOp.fromJson(mapped));
            continue;
          }
          try {
            ops.add(EditOp.fromJson(mapped));
          } catch (_) {}
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
    final overlays = overlayTextOps;
    return overlays.isNotEmpty ? overlays.first : null;
  }

  List<OverlayTextOp> get overlayTextOps =>
      ops.whereType<OverlayTextOp>().toList();

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

  EditManifest replaceOverlayTextAt(int overlayIndex, OverlayTextOp updated) {
    int seen = 0;
    final List<EditOp> newOps = <EditOp>[];
    for (final op in ops) {
      if (op is OverlayTextOp) {
        if (seen == overlayIndex) {
          newOps.add(updated.copy());
        } else {
          newOps.add(op.copy());
        }
        seen++;
      } else {
        newOps.add(op.copy());
      }
    }
    return copyWith(ops: newOps);
  }

  EditManifest addOverlayText(OverlayTextOp newOverlay) {
    final List<EditOp> newOps = ops.map((op) => op.copy()).toList()
      ..add(newOverlay.copy());
    return copyWith(ops: newOps);
  }

  EditManifest removeOverlayTextAt(int overlayIndex) {
    int seen = 0;
    final List<EditOp> newOps = <EditOp>[];
    for (final op in ops) {
      if (op is OverlayTextOp) {
        if (seen != overlayIndex) {
          newOps.add(op.copy());
        }
        seen++;
      } else {
        newOps.add(op.copy());
      }
    }
    return copyWith(ops: newOps);
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
    this.backgroundColorHex,
  }) : super(type: typeKey, startMs: startMs, endMs: endMs);

  final String text;
  final double x;
  final double y;
  // Scales text size; this must round-trip through editTimeline JSON.
  final double scale;
  final double rotationDeg;
  final String? color;
  final String? fontFamily;
  final String? backgroundColorHex;

  factory OverlayTextOp.fromJson(Map<String, dynamic> json) {
    final bg = json['backgroundColorHex'] ?? json['backgroundColor'];
    double _readDouble(dynamic value, double fallback) {
      if (value is num) {
        return value.toDouble();
      }
      if (value is String) {
        final parsed = double.tryParse(value);
        if (parsed != null) {
          return parsed;
        }
      }
      return fallback;
    }

    int _readInt(dynamic value, int fallback) {
      if (value is num) {
        return value.toInt();
      }
      if (value is String) {
        final parsed = int.tryParse(value);
        if (parsed != null) {
          return parsed;
        }
        final parsedDouble = double.tryParse(value);
        if (parsedDouble != null) {
          return parsedDouble.round();
        }
      }
      return fallback;
    }

    double _readScale(Map<String, dynamic> source) {
      if (!source.containsKey('scale')) {
        return 1.0;
      }
      final parsed = _readDouble(source['scale'], 1.0);
      if (!parsed.isFinite || parsed <= 0) {
        return 1.0;
      }
      return parsed.clamp(0.5, 3.0).toDouble();
    }

    return OverlayTextOp(
      text: json['text'] as String? ?? '',
      x: _readDouble(json['x'], 0.5),
      y: _readDouble(json['y'], 0.5),
      scale: _readScale(json),
      rotationDeg: _readDouble(json['rotationDeg'], 0.0),
      startMs: _readInt(json['startMs'], 0),
      endMs: _readInt(json['endMs'], 0),
      color: json['color'] as String?,
      fontFamily: json['fontFamily'] as String?,
      backgroundColorHex: bg is String ? bg : null,
    );
  }

  OverlayTextOp copyWith({
    String? text,
    double? x,
    double? y,
    double? scale,
    double? rotationDeg,
    int? startMs,
    int? endMs,
    String? color,
    String? fontFamily,
    String? backgroundColorHex,
  }) {
    return OverlayTextOp(
      text: text ?? this.text,
      x: x ?? this.x,
      y: y ?? this.y,
      scale: scale ?? this.scale,
      rotationDeg: rotationDeg ?? this.rotationDeg,
      startMs: startMs ?? this.startMs,
      endMs: endMs ?? this.endMs,
      color: color ?? this.color,
      fontFamily: fontFamily ?? this.fontFamily,
      backgroundColorHex: backgroundColorHex ?? this.backgroundColorHex,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'text': text,
        'x': x,
        'y': y,
        'scale': (!scale.isFinite || scale <= 0)
            ? 1.0
            : scale.clamp(0.5, 3.0).toDouble(),
        'rotationDeg': rotationDeg,
        'startMs': startMs,
        'endMs': endMs,
        'color': color,
        'fontFamily': fontFamily,
        'backgroundColorHex': backgroundColorHex,
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
        backgroundColorHex: backgroundColorHex,
      );
}
