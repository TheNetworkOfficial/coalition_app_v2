import 'dart:async';

import 'package:coalition_app_v2/models/video_proxy.dart';
import 'package:coalition_app_v2/services/proxy_playlist_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:video_editor_2/video_editor.dart';
import 'package:video_player/video_player.dart';

class _MockVideoEditorController extends Mock
    implements VideoEditorController {}

class _MockVideoPlayerController extends Mock
    implements VideoPlayerController {}

class _ControllerState {
  _ControllerState({
    required this.editor,
    required this.video,
    required this.setValue,
    required this.getValue,
  });

  final _MockVideoEditorController editor;
  final _MockVideoPlayerController video;
  void Function()? listener;
  final void Function(VideoPlayerValue value) setValue;
  final VideoPlayerValue Function() getValue;
  double trimMinFraction = 0;
  double trimMaxFraction = 1;
  Duration? lastSeek;

  void update(VideoPlayerValue value) => setValue(value);

  int get trimStartMs =>
      (trimMinFraction * getValue().duration.inMilliseconds).round();

  int get trimEndMs =>
      (trimMaxFraction * getValue().duration.inMilliseconds).round();
}

class _TestEditorFactory {
  final List<_ControllerState> states = [];

  VideoEditorController call(PlaylistSegment segment) {
    final editor = _MockVideoEditorController();
    final video = _MockVideoPlayerController();
    final durationMs = segment.durationMs > 0 ? segment.durationMs : 1000;
    VideoPlayerValue currentValue = VideoPlayerValue(
      duration: Duration(milliseconds: durationMs),
      position: Duration.zero,
      isInitialized: true,
    );

    late _ControllerState state;

    when(() => editor.initialize(aspectRatio: any(named: 'aspectRatio')))
        .thenAnswer((_) async {});
    when(() => editor.dispose()).thenAnswer((_) async {});
    when(() => editor.addListener(any())).thenAnswer((invocation) {
      final listener = invocation.positionalArguments.first as void Function()?;
      state.listener = listener;
    });
    when(() => editor.removeListener(any())).thenAnswer((invocation) {
      final listener = invocation.positionalArguments.first as void Function()?;
      if (state.listener == listener) {
        state.listener = null;
      }
    });
    when(() => editor.video).thenReturn(video);
    var trimMin = 0.0;
    var trimMax = 1.0;
    var isTrimming = false;
    when(() => editor.updateTrim(any(), any())).thenAnswer((invocation) {
      trimMin = invocation.positionalArguments[0] as double;
      trimMax = invocation.positionalArguments[1] as double;
      state.trimMinFraction = trimMin;
      state.trimMaxFraction = trimMax;
    });
    when(() => editor.startTrim).thenAnswer(
        (_) => Duration(milliseconds: (trimMin * durationMs).round()));
    when(() => editor.endTrim).thenAnswer(
        (_) => Duration(milliseconds: (trimMax * durationMs).round()));
    when(() => editor.videoDuration)
        .thenReturn(Duration(milliseconds: durationMs));
    when(() => editor.isTrimming).thenAnswer((_) => isTrimming);
    when(() => editor.isTrimming = any()).thenAnswer((invocation) {
      isTrimming = invocation.positionalArguments.first as bool;
      return isTrimming;
    });

    when(() => video.value).thenAnswer((_) => currentValue);
    when(() => video.play()).thenAnswer((_) async {});
    when(() => video.pause()).thenAnswer((_) async {});
    when(() => video.seekTo(any())).thenAnswer((invocation) async {
      state.lastSeek = invocation.positionalArguments.first as Duration;
    });
    when(() => video.dispose()).thenAnswer((_) async {});

    state = _ControllerState(
      editor: editor,
      video: video,
      setValue: (value) {
        currentValue = value;
      },
      getValue: () => currentValue,
    );
    states.add(state);
    return editor;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(Duration.zero);
    registerFallbackValue(0.0);
  });

  test('segment_ready initializes the editor and notifies ready', () async {
    final jobId = 'test-job-1';
    final events = StreamController<dynamic>();
    final factory = _TestEditorFactory();
    final controller = ProxyPlaylistController(
      jobId: jobId,
      events: events.stream,
      editorBuilder: factory.call,
    );

    var readyCalled = false;
    controller.onReady = () {
      readyCalled = true;
    };

    events.add({
      'type': 'segment_ready',
      'segmentIndex': 0,
      'path': '/tmp/segment_000.mp4',
      'durationMs': 1200,
      'width': 360,
      'height': 640,
    });

    await Future.delayed(const Duration(milliseconds: 20));

    expect(factory.states.length, 1);
    expect(controller.segments, hasLength(1));
    expect(controller.editor, same(factory.states.first.editor));
    expect(controller.isReady, isTrue);
    expect(readyCalled, isTrue);
    verify(() => factory.states.first.editor
        .initialize(aspectRatio: any(named: 'aspectRatio'))).called(1);

    await controller.dispose();
    await events.close();
  });

  test('segment_ready prefetches controller for upcoming segment', () async {
    final jobId = 'test-job-prefetch';
    final events = StreamController<dynamic>();
    final factory = _TestEditorFactory();
    final controller = ProxyPlaylistController(
      jobId: jobId,
      events: events.stream,
      editorBuilder: factory.call,
    );

    events.add({
      'type': 'segment_ready',
      'segmentIndex': 0,
      'path': '/tmp/segment_000.mp4',
      'durationMs': 1200,
      'width': 360,
      'height': 640,
    });

    await Future.delayed(const Duration(milliseconds: 20));
    expect(factory.states.length, 1);

    events.add({
      'type': 'segment_ready',
      'segmentIndex': 1,
      'path': '/tmp/segment_001.mp4',
      'durationMs': 1400,
      'width': 360,
      'height': 640,
    });

    await Future.delayed(const Duration(milliseconds: 40));

    expect(factory.states.length, 2);
    expect(controller.editor, same(factory.states.first.editor));

    await controller.dispose();
    await events.close();
  });

  test('synthetic segment_upgraded events upgrade existing segments', () async {
    final jobId = 'test-job-upgrade';
    final events = StreamController<dynamic>();
    final synthetic = StreamController<dynamic>();
    final factory = _TestEditorFactory();
    final controller = ProxyPlaylistController(
      jobId: jobId,
      events: events.stream,
      syntheticEvents: synthetic.stream,
      editorBuilder: factory.call,
    );

    events.add({
      'type': 'segment_ready',
      'segmentIndex': 0,
      'path': '/tmp/segment_low.mp4',
      'durationMs': 1200,
      'width': 360,
      'height': 640,
      'quality': 'PREVIEW',
    });

    await Future.delayed(const Duration(milliseconds: 20));
    expect(controller.segments.single.path, '/tmp/segment_low.mp4');

    var upgradeNotified = false;
    controller.onSegmentUpgraded = (segment) {
      upgradeNotified = true;
      expect(segment.path, '/tmp/segment_high.mp4');
      expect(segment.quality, ProxyQuality.proxy);
    };

    synthetic.add({
      'type': 'segment_upgraded',
      'segmentIndex': 0,
      'path': '/tmp/segment_high.mp4',
      'durationMs': 1200,
      'width': 720,
      'height': 1280,
      'quality': 'PROXY',
    });

    await Future.delayed(const Duration(milliseconds: 40));

    expect(upgradeNotified, isTrue);
    expect(controller.segments.single.path, '/tmp/segment_high.mp4');
    expect(controller.segments.single.quality, ProxyQuality.proxy);

    await controller.dispose();
    await events.close();
    await synthetic.close();
  });

  test('playback completion advances to the next segment', () async {
    final jobId = 'test-job-2';
    final events = StreamController<dynamic>();
    final factory = _TestEditorFactory();
    final controller = ProxyPlaylistController(
      jobId: jobId,
      events: events.stream,
      editorBuilder: factory.call,
    );

    events.add({
      'type': 'segment_ready',
      'segmentIndex': 0,
      'path': '/tmp/segment_000.mp4',
      'durationMs': 1000,
      'width': 360,
      'height': 640,
    });
    events.add({
      'type': 'segment_ready',
      'segmentIndex': 1,
      'path': '/tmp/segment_001.mp4',
      'durationMs': 1000,
      'width': 360,
      'height': 640,
    });

    await Future.delayed(const Duration(milliseconds: 40));

    expect(factory.states.length, 2);
    final firstState = factory.states.first;
    final secondState = factory.states[1];
    expect(controller.editor, same(firstState.editor));

    final current = firstState.getValue();
    firstState.update(current.copyWith(
      position: current.duration,
      isInitialized: true,
    ));
    firstState.listener?.call();

    await Future.delayed(const Duration(milliseconds: 40));

    expect(controller.editor, same(secondState.editor));
    expect(factory.states.length, 2);
    verify(() => firstState.editor.dispose()).called(1);
    verify(() => secondState.editor
        .initialize(aspectRatio: any(named: 'aspectRatio'))).called(1);

    await controller.dispose();
    await events.close();
  });

  test('fallback progress clears existing segments and editor state', () async {
    final jobId = 'test-job-3';
    final events = StreamController<dynamic>();
    final factory = _TestEditorFactory();
    final controller = ProxyPlaylistController(
      jobId: jobId,
      events: events.stream,
      editorBuilder: factory.call,
    );

    var bufferingCalls = 0;
    controller.onBuffering = () {
      bufferingCalls += 1;
    };

    events.add({
      'type': 'segment_ready',
      'segmentIndex': 0,
      'path': '/tmp/segment_000.mp4',
      'durationMs': 800,
      'width': 360,
      'height': 640,
    });

    await Future.delayed(const Duration(milliseconds: 20));
    expect(controller.segments, hasLength(1));
    final firstState = factory.states.first;

    events.add({
      'type': 'segment_ready',
      'segmentIndex': 1,
      'path': '/tmp/segment_001.mp4',
      'durationMs': 900,
      'width': 360,
      'height': 640,
    });

    await Future.delayed(const Duration(milliseconds: 20));
    expect(controller.segments, hasLength(2));
    final secondState = factory.states[1];

    events.add({
      'type': 'progress',
      'progress': 0.5,
      'fallbackTriggered': true,
    });

    await Future.delayed(const Duration(milliseconds: 40));

    expect(controller.segments, isEmpty);
    expect(controller.editor, isNull);
    expect(bufferingCalls, 1);
    verify(() => firstState.editor.dispose()).called(1);
    verify(() => secondState.editor.dispose()).called(1);

    events.add({
      'type': 'segment_ready',
      'segmentIndex': 0,
      'path': '/tmp/segment_restart.mp4',
      'durationMs': 900,
      'width': 360,
      'height': 640,
    });

    await Future.delayed(const Duration(milliseconds: 40));

    expect(controller.segments, hasLength(1));
    expect(factory.states.length, 3);
    expect(controller.editor, same(factory.states.last.editor));

    await controller.dispose();
    await events.close();
  });

  test('updateGlobalTrim applies offsets to active and prepared controllers',
      () async {
    final jobId = 'trim-job-1';
    final events = StreamController<dynamic>();
    final factory = _TestEditorFactory();
    final controller = ProxyPlaylistController(
      jobId: jobId,
      events: events.stream,
      editorBuilder: factory.call,
    );

    events
      ..add({
        'type': 'segment_ready',
        'segmentIndex': 0,
        'path': '/tmp/segment_000.mp4',
        'durationMs': 6000,
        'width': 360,
        'height': 640,
      })
      ..add({
        'type': 'segment_ready',
        'segmentIndex': 1,
        'path': '/tmp/segment_001.mp4',
        'durationMs': 5000,
        'width': 360,
        'height': 640,
      });

    await Future.delayed(const Duration(milliseconds: 60));

    expect(factory.states.length, 2);
    await controller.updateGlobalTrim(startMs: 2000, endMs: 9000);

    expect(controller.editor, same(factory.states.first.editor));
    expect(factory.states.first.trimStartMs, inInclusiveRange(1999, 2001));
    expect(factory.states.first.trimEndMs, equals(6000));
    expect(factory.states.first.lastSeek,
        equals(const Duration(milliseconds: 2000)));
    expect(factory.states[1].trimStartMs, equals(0));
    expect(factory.states[1].trimEndMs, inInclusiveRange(2999, 3001));

    await controller.dispose();
    await events.close();
  });

  test('updateGlobalTrim seeks into later segments with correct offsets',
      () async {
    final jobId = 'trim-job-2';
    final events = StreamController<dynamic>();
    final factory = _TestEditorFactory();
    final controller = ProxyPlaylistController(
      jobId: jobId,
      events: events.stream,
      editorBuilder: factory.call,
    );

    events
      ..add({
        'type': 'segment_ready',
        'segmentIndex': 0,
        'path': '/tmp/segment_000.mp4',
        'durationMs': 6000,
        'width': 360,
        'height': 640,
      })
      ..add({
        'type': 'segment_ready',
        'segmentIndex': 1,
        'path': '/tmp/segment_001.mp4',
        'durationMs': 5000,
        'width': 360,
        'height': 640,
      });

    await Future.delayed(const Duration(milliseconds: 60));

    await controller.updateGlobalTrim(startMs: 6500, endMs: 9000);

    expect(controller.editor, same(factory.states[1].editor));
    expect(factory.states[1].trimStartMs, inInclusiveRange(499, 501));
    expect(factory.states[1].trimEndMs, inInclusiveRange(2999, 3001));
    expect(
        factory.states[1].lastSeek, equals(const Duration(milliseconds: 500)));

    await controller.dispose();
    await events.close();
  });
}
