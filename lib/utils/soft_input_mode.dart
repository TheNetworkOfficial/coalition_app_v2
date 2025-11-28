import 'package:flutter/services.dart';

class SoftInputModeController {
  SoftInputModeController._();

  static const MethodChannel _channel = MethodChannel('soft_input_mode');

  static Future<void> setAdjustNothing() async {
    try {
      await _channel.invokeMethod('setAdjustNothing');
    } catch (_) {
      // Ignore on platforms that don't implement this (e.g. iOS)
    }
  }

  static Future<void> setAdjustResize() async {
    try {
      await _channel.invokeMethod('setAdjustResize');
    } catch (_) {
      // Ignore on platforms that don't implement this
    }
  }
}
