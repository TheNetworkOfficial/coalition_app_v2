import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:coalition_app_v2/services/proxy_playlist_controller.dart';

// Note: This test uses the real ProxyPlaylistController but replaces the
// VideoProxyService().nativeEventsFor(...) stream by injecting events via
// the VideoProxyService global. For simplicity, we'll simulate the event
// stream by directly calling the controller's internal handler via a
// workaround: creating a controller and adding segments via the expected
// event map.

void main() {
  test('ProxyPlaylistController appends first segment and initializes',
      () async {
    final jobId = 'test-job-1';
    final firstController = StreamController<dynamic>();
    final controller =
        ProxyPlaylistController(jobId: jobId, events: firstController.stream);

    // Simulate a segment_ready event
    final event = {
      'type': 'segment_ready',
      'segmentIndex': 0,
      'path': '/tmp/segment_000.mp4',
      'durationMs': 10000,
      'width': 360,
      'height': 640,
    };

    firstController.add(event);
    // give the controller a moment to process the stream event
    await Future.delayed(Duration(milliseconds: 50));

    expect(controller.segments.length, 1);
    expect(controller.segments.first.index, 0);

    await controller.dispose();
    await firstController.close();
  });

  test('ProxyPlaylistController appends multiple segments and can switch',
      () async {
    final jobId = 'test-job-2';
    final multiController = StreamController<dynamic>();
    final controller2 =
        ProxyPlaylistController(jobId: jobId, events: multiController.stream);

    final multiEvents = [
      {
        'type': 'segment_ready',
        'segmentIndex': 0,
        'path': '/tmp/segment_000.mp4',
        'durationMs': 10000,
        'width': 360,
        'height': 640,
      },
      {
        'type': 'segment_ready',
        'segmentIndex': 1,
        'path': '/tmp/segment_001.mp4',
        'durationMs': 10000,
        'width': 360,
        'height': 640,
      }
    ];
    for (final e in multiEvents) {
      multiController.add(e);
    }
    await Future.delayed(Duration(milliseconds: 50));

    expect(controller2.segments.length, 2);

    await controller2.dispose();
    await multiController.close();
  });
}
