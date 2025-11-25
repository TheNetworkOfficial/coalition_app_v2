import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/edit_manifest.dart';

class NativeEditorChannel {
  NativeEditorChannel()
      : _methodChannel = const MethodChannel('EditorChannel'),
        _eventChannel = const EventChannel('EditorChannelEvents');

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;
  Stream<dynamic>? _events;

  Stream<dynamic> get events => _events ??= _eventChannel.receiveBroadcastStream();

  Future<void> prepareTimeline({
    required String sourcePath,
    String? proxyPath,
    required Map<String, dynamic> manifest,
    required int surfaceId,
  }) async {
    try {
      await _methodChannel.invokeMethod('prepareTimeline', {
        'sourcePath': sourcePath,
        'proxyPath': proxyPath,
        'timelineJson': jsonEncode(manifest),
        'surfaceId': surfaceId,
      });
    } catch (error, stack) {
      if (kDebugMode) {
        debugPrint('NativeEditorChannel.prepareTimeline failed: $error\n$stack');
      }
      rethrow;
    }
  }

  Future<void> updateTimeline({
    required EditManifest manifest,
    int? surfaceId,
  }) async {
    try {
      await _methodChannel.invokeMethod('updateTimeline', {
        'timelineJson': jsonEncode(manifest.toJson()),
        if (surfaceId != null) 'surfaceId': surfaceId,
      });
    } catch (error, stack) {
      if (kDebugMode) {
        debugPrint('NativeEditorChannel.updateTimeline failed: $error\n$stack');
      }
    }
  }

  Future<void> seek(int positionMs) async {
    try {
      await _methodChannel.invokeMethod('seekPreview', {
        'positionMs': positionMs,
      });
    } catch (_) {}
  }

  Future<void> setPlayback({required bool playing, double? speed}) async {
    try {
      await _methodChannel.invokeMethod('setPlaybackState', {
        'playing': playing,
        if (speed != null) 'speed': speed,
      });
    } catch (_) {}
  }

  Future<void> release() async {
    try {
      await _methodChannel.invokeMethod('release');
    } catch (_) {}
  }
}

bool get supportsNativePreview =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS);
