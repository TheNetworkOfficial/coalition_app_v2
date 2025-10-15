import 'dart:async';

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

  void update(VideoPlayerValue value) => setValue(value);
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

    when(() => video.value).thenAnswer((_) => currentValue);
    when(() => video.play()).thenAnswer((_) async {});
    when(() => video.pause()).thenAnswer((_) async {});
    when(() => video.seekTo(any())).thenAnswer((_) async {});
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
    verify(() => firstState.editor.dispose()).called(1);

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
      'type': 'progress',
      'progress': 0.5,
      'fallbackTriggered': true,
    });

    await Future.delayed(const Duration(milliseconds: 40));

    expect(controller.segments, isEmpty);
    expect(controller.editor, isNull);
    expect(bufferingCalls, 1);
    verify(() => firstState.editor.dispose()).called(1);

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
    expect(controller.editor, same(factory.states.last.editor));

    await controller.dispose();
    await events.close();
  });
}
