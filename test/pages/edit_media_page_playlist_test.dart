import 'dart:async';

import 'package:coalition_app_v2/models/post_draft.dart';
import 'package:coalition_app_v2/models/video_proxy.dart';
import 'package:coalition_app_v2/pages/edit_media_page.dart';
import 'package:coalition_app_v2/services/proxy_playlist_controller.dart';
import 'package:flutter/material.dart';
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
    when(() => editor.isRotated).thenReturn(false);
    when(() => editor.isTrimming).thenReturn(false);
    when(() => editor.isTrimming = any()).thenAnswer((invocation) {
      final val = invocation.positionalArguments.first as bool;
      return val;
    });

    when(() => video.value).thenAnswer((_) => currentValue);
    when(() => video.playerId).thenReturn(0);
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

  testWidgets(
      'slider range grows with playlist segments and trim spans duration',
      (tester) async {
    final events = StreamController<dynamic>();
    final factory = _TestEditorFactory();
    final playlistController = ProxyPlaylistController(
      jobId: 'playlist-test',
      events: events.stream,
      editorBuilder: factory.call,
    );

    final media = EditMediaData(
      type: 'video',
      sourceAssetId: 'asset-1',
      originalFilePath: '/tmp/source.mp4',
      proxyRequest: const VideoProxyRequest(
        sourcePath: '/tmp/source.mp4',
        targetWidth: 1080,
        targetHeight: 1920,
        segmentedPreview: true,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: EditMediaPage(
          media: media,
          playlistControllerOverride: playlistController,
        ),
      ),
    );

    events.add({
      'type': 'segment_ready',
      'segmentIndex': 0,
      'path': '/tmp/segment_000.mp4',
      'durationMs': 6000,
      'width': 360,
      'height': 640,
    });

    await tester.pump(const Duration(milliseconds: 80));

    events.add({
      'type': 'segment_ready',
      'segmentIndex': 1,
      'path': '/tmp/segment_001.mp4',
      'durationMs': 5000,
      'width': 360,
      'height': 640,
    });

    await tester.pump(const Duration(milliseconds: 120));

    final state = tester.state<State<EditMediaPage>>(find.byType(EditMediaPage))
        as dynamic;

    final RangeValues? range = state.debugVideoTrimRangeMs as RangeValues?;
    expect(range, isNotNull);
    expect(range!.end, inInclusiveRange(10999, 11001));

    state.debugApplyTrimRange(const RangeValues(500, 10500));
    await tester.pump();

    final VideoTrimData? trim = state.debugBuildVideoTrim() as VideoTrimData?;
    expect(trim, isNotNull);
    expect(trim!.startMs, equals(500));
    expect(trim.endMs, equals(10500));
    expect(trim.durationMs, equals(10000));

    await tester.pumpWidget(const SizedBox.shrink());
    await playlistController.dispose();
    await events.close();
  });
}
