import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:flutter/services.dart';
import 'package:video_editor_2/video_editor.dart';
import 'package:video_player/video_player.dart';

import '../env.dart';
import '../features/editor/overlay_text_editor.dart';
import '../models/edit_manifest.dart';
import '../models/post_draft.dart';
import '../models/video_proxy.dart';
import '../router/route_observers.dart';
import '../services/video_proxy_service.dart';
import '../services/native_editor_channel.dart';
import '../utils/soft_input_mode.dart';
import '../widgets/video_proxy_dialog.dart';
import 'post_review_page.dart';

class EditMediaData {
  const EditMediaData({
    required this.type,
    required this.sourceAssetId,
    required this.originalFilePath,
    this.originalDurationMs,
    this.proxyResult,
    this.proxyRequest,
    this.proxyPosterBytes,
    this.proxyJob,
  }) : assert(type == 'image' || type == 'video');

  final String type;
  final String sourceAssetId;
  final String originalFilePath;
  final int? originalDurationMs;
  final VideoProxyResult? proxyResult;
  final VideoProxyRequest? proxyRequest;
  final Uint8List? proxyPosterBytes;
  final VideoProxyJob? proxyJob;
}

class EditMediaPage extends StatefulWidget {
  const EditMediaPage({
    super.key,
    required this.media,
  });

  final EditMediaData media;

  @override
  State<EditMediaPage> createState() => _EditMediaPageState();
}

enum _EditorTool { trim, text }

class _EditMediaPageState extends State<EditMediaPage> with RouteAware {
  static const _videoTrimHeight = 72.0;
  static const int _preparingBarrierMaxMs = 300;

  VideoEditorController? _videoController;
  VideoProxyJob? _activeJob;
  VideoProxyResult? _activeProxy;
  bool _usingFallbackProxy = false;
  bool _usingProxyPreview = false;
  bool _isPreparingFallback = false;
  bool _retainProxyForNextStep = false;
  bool _videoInitialized = false;
  Object? _videoInitError;
  Duration? _videoDuration;
  RangeValues? _videoTrimRangeMs;
  RangeValues? _globalTrimMs;
  Timer? _trimSeekDebounce;
  double? _optimizingProgress;
  StreamSubscription<VideoProxyProgress>? _jobProgressSub;
  EditManifest _editManifest = const EditManifest();
  final NativeEditorChannel _nativeEditorChannel = NativeEditorChannel();
  int? _nativePreviewViewId;
  final Stopwatch _editorReadyStopwatch = Stopwatch()..start();
  bool _editorReadyMetricSent = false;
  bool _releasedForNavigation = false;
  bool _isNavigatingToReview = false;
  bool _routeAwareSubscribed = false;
  bool _releasingForNavigation = false;
  OverlayTextOp? _editingOverlay;
  int? _editingOverlayIndex;
  _EditorTool _selectedTool = _EditorTool.trim;
  int? _draggingOverlayIndex;
  bool _draggingOverTrash = false;

  double? _imageWidth;
  double? _imageHeight;
  bool _imageLoading = false;
  bool _imageLoadFailed = false;

  String _selectedAspectId = _AspectRatioOption.original.id;
  int _rotationTurns = 0;
  double? _fullEditorHeight;

  @override
  void initState() {
    super.initState();
    // Prevent keyboard from resizing this screen; it will be restored on dispose.
    SoftInputModeController.setAdjustNothing();
    if (widget.media.type == 'video') {
      final proxyResult = widget.media.proxyResult;
      final proxyJob = widget.media.proxyJob;
      final request = widget.media.proxyRequest;

      unawaited(
        _initVideoControllerWithSource(
          path: widget.media.originalFilePath,
          sourceDurationMs: widget.media.originalDurationMs,
          isProxySource: false,
        ),
      );

      if (proxyResult != null) {
        _activeProxy = proxyResult;
        _usingFallbackProxy =
            proxyResult.metadata.resolution == VideoProxyResolution.p360;
        unawaited(_switchPreviewToProxyResult(proxyResult));
      } else if (proxyJob != null) {
        _attachProxyJob(proxyJob);
      } else if (request != null) {
        final job = VideoProxyService().createJob(
          request: request,
          enableLogging: true,
        );
        _attachProxyJob(job);
      } else {
        debugPrint(
          '[EditMediaPage] Proxy request missing; continuing with original source.',
        );
      }
    } else {
      _loadImageMetadata();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _subscribeToRouteObserver();
  }

  void _subscribeToRouteObserver() {
    if (_routeAwareSubscribed) {
      return;
    }
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      appRouteObserver.subscribe(this, route);
      _routeAwareSubscribed = true;
    }
  }

  void _attachProxyJob(VideoProxyJob job) {
    _activeJob = job;
    setState(() {
      _videoInitError = null;
      _optimizingProgress = 0;
    });

    final session = job.session;
    session?.firstPreview.then((preview) {
      if (!mounted) return;
      _handleProxyPreview(preview);
    }).catchError((error) {
      debugPrint('[EditMediaPage] Proxy preview stream failed: $error');
    });

    _listenToProxyProgress(job);

    job.future.then((result) {
      if (!mounted) return;
      _jobProgressSub?.cancel();
      _jobProgressSub = null;
      setState(() {
        _activeProxy = result;
        _usingFallbackProxy =
            result.metadata.resolution == VideoProxyResolution.p360;
        _activeJob = null;
        _optimizingProgress = 1;
      });
      debugPrint(
        '[EditMediaPage] Proxy ready ${result.metadata.width}x${result.metadata.height} '
        '(${result.metadata.durationMs}ms)',
      );
      unawaited(_switchPreviewToProxyResult(result));
    }).catchError((error) {
      if (!mounted) return;
      _jobProgressSub?.cancel();
      _jobProgressSub = null;
      setState(() {
        _activeJob = null;
        _optimizingProgress = null;
      });
      _handleProxyError(error);
    });
  }

  void _listenToProxyProgress(VideoProxyJob job) {
    _jobProgressSub?.cancel();
    _jobProgressSub = job.progress.listen((event) {
      if (!mounted) return;
      setState(() {
        _optimizingProgress = event.fraction;
      });
    });
  }

  Future<void> _handleProxyPreview(ProxyPreview preview) async {
    if (!mounted) return;
    final previewPath = preview.filePath;
    if (previewPath.isEmpty) {
      return;
    }
    final originalDuration = widget.media.originalDurationMs;
    final previewDuration = preview.metadata.durationMs;
    final coversFullClip = originalDuration == null ||
        previewDuration >= (originalDuration * 0.8);
    if (!coversFullClip) {
      debugPrint(
        '[EditMediaPage] Skipping partial proxy preview (${previewDuration}ms of ${originalDuration}ms)',
      );
      return;
    }
    if (_usingProxyPreview) {
      return;
    }
    await _initVideoControllerWithSource(
      path: previewPath,
      sourceDurationMs: preview.metadata.durationMs,
      isProxySource: true,
    );
  }

  Future<void> _switchPreviewToProxyResult(VideoProxyResult result) async {
    if (!mounted) return;
    await _initVideoControllerWithSource(
      path: result.filePath,
      sourceDurationMs: result.metadata.durationMs,
      isProxySource: true,
    );
  }

  @override
  void dispose() {
    // Restore default keyboard behavior for other screens.
    SoftInputModeController.setAdjustResize();
    if (_routeAwareSubscribed) {
      appRouteObserver.unsubscribe(this);
      _routeAwareSubscribed = false;
    }
    final controller = _videoController;
    if (controller != null) {
      controller.removeListener(_handleVideoControllerUpdate);
      unawaited(controller.dispose());
    }
    if (_activeProxy == null) {
      final job = _activeJob;
      if (job != null) {
        unawaited(job.cancel());
      }
    }
    if (!_retainProxyForNextStep) {
      final proxy = _activeProxy;
      if (proxy != null) {
        unawaited(VideoProxyService().deleteProxy(proxy.filePath));
      }
    }
    unawaited(_jobProgressSub?.cancel());
    _jobProgressSub = null;
    _trimSeekDebounce?.cancel();
    unawaited(_nativeEditorChannel.release());
    super.dispose();
  }

  Future<void> _initVideoControllerWithSource({
    required String path,
    required int? sourceDurationMs,
    required bool isProxySource,
  }) async {
    if (path.isEmpty) {
      setState(() {
        _videoInitError =
            const VideoProxyException('Video source missing. Please retry.');
      });
      return;
    }

    final previous = _videoController;
    final previousTrim = _videoTrimRangeMs;
    final previousGlobal = _globalTrimMs;

    final controller = VideoEditorController.file(
      XFile(path),
      maxDuration: _buildMaxDuration(
        sourceDurationMs ?? widget.media.originalDurationMs,
      ),
      minDuration: Duration.zero,
    );

    setState(() {
      _videoController = controller;
      _videoInitialized = false;
      _videoInitError = null;
    });

    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      controller.addListener(_handleVideoControllerUpdate);
      await controller.video.setLooping(true);
      if (kEnableNativeEditorPreview) {
        // Native preview owns playback; keep Flutter video silent.
        await controller.video.setVolume(0.0);
        if (controller.video.value.isPlaying) {
          await controller.video.pause();
        }
      } else {
        await controller.video.setVolume(1.0);
        if (!controller.video.value.isPlaying) {
          await controller.video.play();
        }
      }

      final appliedTrim =
          previousTrim != null ? _applyTrimRange(controller, previousTrim) : null;

      setState(() {
        _videoInitialized = true;
        _videoDuration = controller.videoDuration;
        _videoTrimRangeMs = appliedTrim ??
            RangeValues(
              controller.startTrim.inMilliseconds.toDouble(),
              controller.endTrim.inMilliseconds.toDouble(),
            );
        _globalTrimMs = previousGlobal ?? _videoTrimRangeMs;
        _usingProxyPreview = isProxySource;
      });
      _markEditorReady();
      _maybePrepareNativePreview();
    } catch (error, stackTrace) {
      debugPrint(
        '[EditMediaPage] Failed to initialize ${isProxySource ? 'proxy' : 'original'} preview: $error\n$stackTrace',
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _videoInitError ??= error;
        _videoInitialized = false;
      });
      if (!isProxySource) {
        final fallbackSucceeded = await _attemptFallback(error);
        if (fallbackSucceeded) {
          return;
        }
      }
    } finally {
      if (previous != null && previous != controller) {
        previous.removeListener(_handleVideoControllerUpdate);
        unawaited(previous.dispose());
      }
    }
  }

  Duration _buildMaxDuration(int? durationMs) {
    if (durationMs != null && durationMs > 0) {
      return Duration(milliseconds: durationMs);
    }
    return const Duration(days: 1);
  }

  RangeValues _applyTrimRange(
    VideoEditorController controller,
    RangeValues range,
  ) {
    final durationMs = controller.videoDuration.inMilliseconds.toDouble();
    if (durationMs <= 0) {
      return range;
    }
    final start = range.start.clamp(0, durationMs).toDouble();
    final end = range.end.clamp(start + 1, durationMs).toDouble();
    final min = start / durationMs;
    final max = end / durationMs;
    controller.updateTrim(min, max);
    unawaited(
      controller.video.seekTo(Duration(milliseconds: start.round())),
    );
    _enforceNativePreviewSilence(controller);
    return RangeValues(start, end);
  }

  void _enforceNativePreviewSilence(VideoEditorController controller) {
    if (!kEnableNativeEditorPreview) {
      return;
    }
    final video = controller.video;
    unawaited(video.setVolume(0.0));
    if (video.value.isPlaying) {
      unawaited(video.pause());
    }
  }

  void _markEditorReady() {
    if (_editorReadyMetricSent) {
      return;
    }
    _editorReadyMetricSent = true;
    final elapsed = _editorReadyStopwatch.elapsedMilliseconds;
    if (elapsed > 200) {
      debugPrint('[EditMediaPage][metric] editor_waited_for_proxy_ms=$elapsed');
    }
  }

  void _handleProxyError(Object error) {
    final message =
        error is VideoProxyException ? error.message : error.toString();
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text('Unable to optimize video: $message')),
    );
    setState(() {
      _videoInitError = error;
      _videoInitialized = false;
    });
  }

  Future<bool> _attemptFallback(Object error) async {
    if (_usingFallbackProxy || _isPreparingFallback) {
      return false;
    }
    final request = widget.media.proxyRequest;
    if (request == null) {
      return false;
    }

    debugPrint(
        '[EditMediaPage] Video initialization failed, attempting fallback: $error');

    setState(() {
      _isPreparingFallback = true;
    });

    final service = VideoProxyService();
    final fallbackJob = service.createJob(request: request.fallbackPreview());
    final outcome = await showDialog<VideoProxyDialogOutcome>(
      context: context,
      barrierDismissible: false,
      builder: (context) => VideoProxyProgressDialog(
        job: fallbackJob,
        title: 'Preparing smaller video…',
        allowCancel: true,
      ),
    );

    if (!mounted) {
      setState(() {
        _isPreparingFallback = false;
      });
      return false;
    }

    setState(() {
      _isPreparingFallback = false;
    });

    if (outcome == null || outcome.cancelled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Video optimization canceled.')),
      );
      setState(() {
        _videoInitError =
            const VideoProxyException('Video optimization canceled');
      });
      return false;
    }

    if (outcome.error != null) {
      final errorMessage = outcome.error is VideoProxyException
          ? (outcome.error as VideoProxyException).message
          : outcome.error.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to prepare fallback: $errorMessage')),
      );
      setState(() {
        _videoInitError = VideoProxyException('Fallback failed: $errorMessage');
      });
      return false;
    }

    final result = outcome.result;
    if (result == null) {
      return false;
    }

    final previousProxy = _activeProxy;
    if (previousProxy != null) {
      unawaited(service.deleteProxy(previousProxy.filePath));
    }

    setState(() {
      _activeProxy = result;
      _usingFallbackProxy = true;
      _videoInitError = null;
    });

    debugPrint('[EditMediaPage] Playing fallback proxy (360p).');

    debugPrint(
      '[EditMediaPage] Fallback proxy ready ${result.metadata.width}x${result.metadata.height} in ${result.transcodeDurationMs}ms',
    );

    await _switchPreviewToProxyResult(result);
    return true;
  }

  Future<void> _loadImageMetadata() async {
    setState(() {
      _imageLoading = true;
      _imageLoadFailed = false;
    });

    final imageProvider = Image.file(File(widget.media.originalFilePath)).image;
    final completer = Completer<ImageInfo>();
    late final ImageStreamListener listener;
    final stream = imageProvider.resolve(const ImageConfiguration());

    listener = ImageStreamListener(
      (info, _) {
        completer.complete(info);
      },
      onError: (error, __) {
        completer.completeError(error);
      },
    );

    stream.addListener(listener);

    try {
      final info = await completer.future;
      if (!mounted) return;
      setState(() {
        _imageWidth = info.image.width.toDouble();
        _imageHeight = info.image.height.toDouble();
        _imageLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _imageLoading = false;
        _imageLoadFailed = true;
      });
    } finally {
      stream.removeListener(listener);
    }
  }

  bool get _isVideo => widget.media.type == 'video';
  bool get _useNativePreview =>
      kEnableNativeEditorPreview && supportsNativePreview && !kIsWeb;

  bool get _shouldShowFlutterOverlay => true;
  int get _videoDurationMs => _videoDuration?.inMilliseconds ?? 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final maxHeight = constraints.maxHeight;
          final fullHeight = _fullEditorHeight ?? maxHeight;
          if (_fullEditorHeight == null && maxHeight > 0) {
            _fullEditorHeight = maxHeight;
          }

          return OverflowBox(
            alignment: Alignment.topCenter,
            minHeight: fullHeight,
            maxHeight: fullHeight,
            minWidth: constraints.maxWidth,
            maxWidth: constraints.maxWidth,
            child: SizedBox(
              height: fullHeight,
              width: constraints.maxWidth,
              child: _buildEditBody(context),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEditBody(BuildContext context) {
    if (_isVideo) {
      return _buildEditStack(context);
    }
    return SafeArea(child: _buildImageLayout(context));
  }

  Widget _buildEditStack(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: _buildVideoCanvas(context),
        ),
        Positioned(
          left: 8,
          top: 0,
          child: SafeArea(
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ),
        Positioned(
          right: 16,
          top: 0,
          bottom: 0,
          child: SafeArea(
            child: _EditorToolRail(
              selectedTool: _selectedTool,
              onSelectTrim: () {
                setState(() {
                  _selectedTool = _EditorTool.trim;
                });
              },
              onSelectText: () {
                setState(() {
                  _selectedTool = _EditorTool.text;
                });
                _onTextOverlayPressed();
              },
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            top: false,
            child: _buildBottomControls(context),
          ),
        ),
        if (_draggingOverlayIndex != null)
          Positioned(
            bottom: 32,
            left: 0,
            right: 0,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _draggingOverTrash
                      ? Colors.redAccent.withValues(alpha: 0.9)
                      : Colors.black54,
                ),
                child: const Icon(
                  Icons.delete,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
          ),
        if (_editingOverlay != null && _editingOverlayIndex != null)
          Positioned.fill(
            child: OverlayTextEditorOverlay(
              initialOverlay: _editingOverlay!,
              videoDurationMs: _videoDurationMs,
              onChanged: (updated) {
                setState(() {
                  _editingOverlay = updated;
                });
              },
              onCancel: () {
                setState(() {
                  _editingOverlay = null;
                  _editingOverlayIndex = null;
                });
              },
              onDone: (updated) {
                setState(() {
                  if (_editingOverlayIndex != null &&
                      _editingOverlayIndex! <
                          _editManifest.overlayTextOps.length) {
                    _editManifest = _editManifest.replaceOverlayTextAt(
                      _editingOverlayIndex!,
                      updated,
                    );
                  } else {
                    _editManifest = _editManifest.addOverlayText(updated);
                  }
                  _editingOverlay = null;
                  _editingOverlayIndex = null;
                });
                _updateNativeTimelineIfNeeded();
              },
            ),
          ),
      ],
    );
  }

  Widget _buildImageLayout(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _buildImageEditor(),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            MediaQuery.of(context).padding.bottom + 16,
          ),
          child: ElevatedButton(
            onPressed: _canContinue ? () => _onContinuePressed() : null,
            child: const Text('Continue'),
          ),
        ),
      ],
    );
  }

  bool get _canContinue {
    if (_isVideo) {
      return _videoInitialized &&
          _videoInitError == null &&
          !_isPreparingFallback;
    }
    if (_imageLoadFailed) {
      return false;
    }
    return true;
  }

  Widget _buildVideoCanvas(BuildContext context) {
    final controller = _videoController;
    if (_videoInitError != null) {
      return Center(
        child: Text(
          'Unable to load video',
          style: Theme.of(context)
              .textTheme
              .bodyLarge
              ?.copyWith(color: Theme.of(context).colorScheme.error),
        ),
      );
    }

    if (controller == null || !_videoInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    final videoValue = controller.video.value;
    final aspectRatio = videoValue.isInitialized && videoValue.aspectRatio > 0
        ? videoValue.aspectRatio
        : 9 / 16;
    final isProxyJobRunning = _activeJob != null && _activeProxy == null;
    final optimizingLabel = () {
      final progress = _optimizingProgress;
      if (progress == null) return 'Optimizing…';
      final clamped = progress.clamp(0.0, 1.0);
      final percent = (clamped * 100).round();
      return 'Optimizing… $percent%';
    }();

    final overlays = _editManifest.overlayTextOps;
    final showFlutterOverlay =
        _shouldShowFlutterOverlay &&
            _editingOverlayIndex == null &&
            _editingOverlay == null;

    return Center(
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildVideoPreview(controller),
                  if (showFlutterOverlay)
                    for (int i = 0; i < overlays.length; i++)
                      _OverlayTextPreview(
                        overlay: overlays[i],
                        videoListenable: controller.video,
                        onOverlayChanged: (updated) =>
                            _onOverlayChangedAt(i, updated),
                        onOverlayTap: (op) => _onOverlayTapped(i, op),
                        onOverlayDragStart: () => _onOverlayDragStart(i),
                        onOverlayDragUpdate: (pos) =>
                            _onOverlayDragUpdate(i, pos),
                        onOverlayDragEnd: () => _onOverlayDragEnd(i),
                      ),
                ],
              ),
            ),
            if (isProxyJobRunning)
              Positioned(
                top: 12,
                left: 12,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    optimizingLabel,
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium
                        ?.copyWith(color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoPreview(VideoEditorController controller) {
    return _buildPreviewSurface(controller);
  }

  Widget _buildPreviewSurface(
    VideoEditorController controller,
  ) {
    if (_useNativePreview) {
      return _buildNativePreviewSurface();
    }
    return Container(
      color: Colors.black,
      child: CropGridViewer.preview(controller: controller),
    );
  }

  Widget _buildBottomControls(BuildContext context) {
    if (!_isVideo) {
      return const SizedBox.shrink();
    }

    final duration = _videoDuration;
    final range = _videoTrimRangeMs;
    final totalMs = duration?.inMilliseconds.toDouble() ?? 0;
    final sliderDivisions =
        duration != null && duration.inSeconds > 0 ? duration.inSeconds : null;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.0),
            Colors.black.withValues(alpha: 0.4),
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (range != null &&
              duration != null &&
              _selectedTool == _EditorTool.trim) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Trim: ${_formatMs(range.start.toInt())} - '
                    '${_formatMs(range.end.toInt())}',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.white),
              ),
            ),
            SizedBox(
              height: _videoTrimHeight,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  overlayShape: SliderComponentShape.noOverlay,
                  trackHeight: 4,
                  rangeThumbShape:
                      const RoundRangeSliderThumbShape(enabledThumbRadius: 10),
                ),
                child: RangeSlider(
                  min: 0,
                  max: totalMs,
                  divisions: sliderDivisions,
                  values: RangeValues(
                    range.start.clamp(0, totalMs),
                    range.end.clamp(0, totalMs),
                  ),
                  labels: RangeLabels(
                    _formatDuration(range.start),
                    _formatDuration(range.end),
                  ),
                  onChangeStart: (_) => _onTrimChangeStart(),
                  onChanged: (values) => _onTrimChanged(values, duration),
                  onChangeEnd: (values) => _onTrimChangeEnd(values, duration),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _canContinue ? _onContinuePressed : null,
              child: const Text('Continue'),
            ),
          ),
        ],
      ),
    );
  }

  void _onOverlayChangedAt(int index, OverlayTextOp updatedOp) {
    setState(() {
      _editManifest = _editManifest.replaceOverlayTextAt(index, updatedOp);
    });
    _updateNativeTimelineIfNeeded();
  }

  OverlayTextOp _createDefaultTextOverlay() {
    final controller = _videoController;
    final startMs = controller?.startTrim.inMilliseconds ?? 0;
    final endMs = controller?.endTrim.inMilliseconds ?? _videoDurationMs;
    return OverlayTextOp(
      text: 'Your text',
      x: 0.5,
      y: 0.5,
      scale: 1.0,
      rotationDeg: 0.0,
      startMs: startMs,
      endMs: endMs,
      color: '#FFFFFF',
      fontFamily: null,
      backgroundColorHex: null,
    );
  }

  void _onTextOverlayPressed() {
    if (!_isVideo) {
      return;
    }
    final controller = _videoController;
    if (_videoDuration == null || controller == null) {
      return;
    }
    final newOverlay = _createDefaultTextOverlay();
    setState(() {
      _editingOverlayIndex = _editManifest.overlayTextOps.length;
      _editingOverlay = newOverlay;
    });
  }

  void _onOverlayTapped(int index, OverlayTextOp overlay) {
    setState(() {
      _editingOverlayIndex = index;
      _editingOverlay = overlay;
    });
  }

  void _onOverlayDragStart(int index) {
    setState(() {
      _draggingOverlayIndex = index;
      _draggingOverTrash = false;
    });
  }

  void _onOverlayDragUpdate(int index, Offset normalizedPos) {
    const double trashZoneTop = 0.9;
    const double trashZoneHalfWidth = 0.08;

    final double x = normalizedPos.dx;
    final double y = normalizedPos.dy;

    final bool inVerticalZone = y >= trashZoneTop;
    final bool inHorizontalZone =
        x >= 0.5 - trashZoneHalfWidth && x <= 0.5 + trashZoneHalfWidth;

    final bool overTrash = inVerticalZone && inHorizontalZone;

    if (_draggingOverlayIndex == index) {
      setState(() {
        _draggingOverTrash = overTrash;
      });
    }
  }

  void _onOverlayDragEnd(int index) {
    if (_draggingOverlayIndex == index && _draggingOverTrash) {
      setState(() {
        _editManifest = _editManifest.removeOverlayTextAt(index);
        _draggingOverlayIndex = null;
        _draggingOverTrash = false;
      });
      _updateNativeTimelineIfNeeded();
    } else {
      setState(() {
        _draggingOverlayIndex = null;
        _draggingOverTrash = false;
      });
    }
  }

  Widget _buildNativePreviewSurface() {
    if (Platform.isAndroid) {
      return PlatformViewLink(
        viewType: 'EditorPreviewView',
        surfaceFactory: (context, controller) {
          return PlatformViewSurface(
            controller: controller,
            hitTestBehavior: PlatformViewHitTestBehavior.opaque,
            gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
          );
        },
        onCreatePlatformView: (params) {
          final controller = PlatformViewsService.initSurfaceAndroidView(
            id: params.id,
            viewType: params.viewType,
            layoutDirection: TextDirection.ltr,
            creationParams: null,
            creationParamsCodec: const StandardMessageCodec(),
            onFocus: () => params.onFocusChanged(true),
          );
          controller.addOnPlatformViewCreatedListener((id) {
            params.onPlatformViewCreated(id);
            setState(() {
              _nativePreviewViewId = id;
            });
            _maybePrepareNativePreview();
          });
          controller.create();
          return controller;
        },
      );
    }
    return UiKitView(
      viewType: 'EditorPreviewView',
      layoutDirection: TextDirection.ltr,
      creationParams: null,
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: (id) {
        setState(() {
          _nativePreviewViewId = id;
        });
        _maybePrepareNativePreview();
      },
    );
  }

  Widget _buildImageEditor() {
    if (_imageLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_imageLoadFailed) {
      return Center(
        child: Text(
          'Unable to load image metadata',
          style: Theme.of(context)
              .textTheme
              .bodyLarge
              ?.copyWith(color: Theme.of(context).colorScheme.error),
        ),
      );
    }

    final aspect = _currentImageAspect;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: AspectRatio(
            aspectRatio: aspect,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final cropRect = _currentCropRect();
                final cropLeft = constraints.maxWidth * cropRect.left;
                final cropTop = constraints.maxHeight * cropRect.top;
                final cropWidth = constraints.maxWidth * cropRect.width;
                final cropHeight = constraints.maxHeight * cropRect.height;

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(
                      color: Colors.black12,
                      child: FittedBox(
                        fit: BoxFit.cover,
                        child: RotatedBox(
                          quarterTurns: _rotationTurns % 4,
                          child: Image.file(
                            File(widget.media.originalFilePath),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: cropLeft,
                      top: cropTop,
                      width: cropWidth,
                      height: cropHeight,
                      child: IgnorePointer(
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Theme.of(context).colorScheme.primary,
                              width: 2,
                            ),
                            color: Colors.black.withValues(alpha: 0.1),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Aspect Ratio',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: _aspectRatioOptions.map((option) {
            final selected = option.id == _selectedAspectId;
            return ChoiceChip(
              label: Text(option.label),
              selected: selected,
              onSelected: (value) {
                if (value) {
                  setState(() {
                    _selectedAspectId = option.id;
                    _applyCropOpLocked();
                  });
                }
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        Text(
          'Rotation',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            IconButton(
              tooltip: 'Rotate left',
              onPressed: () => setState(() {
                _rotationTurns = (_rotationTurns + 1) % 4;
                _applyRotateOpLocked();
              }),
              icon: const Icon(Icons.rotate_left),
            ),
            IconButton(
              tooltip: 'Rotate right',
              onPressed: () => setState(() {
                _rotationTurns = (_rotationTurns - 1) % 4;
                _applyRotateOpLocked();
              }),
              icon: const Icon(Icons.rotate_right),
            ),
          ],
        ),
      ],
    );
  }

  Rect _currentCropRect() {
    final option = _aspectRatioOptions
        .firstWhere((element) => element.id == _selectedAspectId);
    final aspect = option.ratio;
    final imageAspect = _currentImageAspect;

    if (aspect == null) {
      return const Rect.fromLTWH(0, 0, 1, 1);
    }

    if (imageAspect == 0) {
      return const Rect.fromLTWH(0, 0, 1, 1);
    }

    double cropWidth = 1.0;
    double cropHeight = 1.0;

    if (aspect > imageAspect) {
      cropHeight = imageAspect / aspect;
    } else {
      cropWidth = aspect / imageAspect;
    }

    final left = (1 - cropWidth) / 2;
    final top = (1 - cropHeight) / 2;
    return Rect.fromLTWH(left, top, cropWidth, cropHeight);
  }

  double get _currentImageAspect {
    final width = _imageWidth ?? 1;
    final height = _imageHeight ?? 1;
    if (height == 0 || width == 0) {
      return 1;
    }
    final baseAspect = width / height;
    return _rotationTurns.isOdd ? 1 / baseAspect : baseAspect;
  }

  Future<void> _withPreparingOverlay(
    Future<void> Function() releaseAction,
  ) async {
    if (!kShowEditContinueBarrier) {
      await releaseAction();
      return;
    }
    final OverlayState overlay = Overlay.of(context, rootOverlay: true);
    final entry = OverlayEntry(
      builder: (context) => const _PreparingOverlay(),
    );
    final stopwatch = Stopwatch()..start();
    overlay.insert(entry);
    try {
      await releaseAction();
    } finally {
      final elapsedMs = stopwatch.elapsedMilliseconds;
      final remaining = _preparingBarrierMaxMs - elapsedMs;
      if (remaining > 0) {
        await Future<void>.delayed(Duration(milliseconds: remaining));
      }
      entry.remove();
    }
  }

  Future<void> _releaseForNavigation() async {
    if (_releasedForNavigation) {
      return;
    }
    final controller = _videoController;
    if (controller != null) {
      unawaited(controller.video.pause());
    }
    if (_releasingForNavigation) {
      // Another release is already running; wait for it to complete.
      while (_releasingForNavigation) {
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
      return;
    }
    _releasingForNavigation = true;
    PostReviewTelemetry.recordDualDecoderGuardTriggered();
    final stopwatch = Stopwatch()..start();
    try {
      if (controller != null) {
        controller.removeListener(_handleVideoControllerUpdate);
        if (mounted) {
          setState(() {
            _videoController = null;
            _videoInitialized = false;
          });
        } else {
          _videoController = null;
          _videoInitialized = false;
        }
        try {
          final videoCtrl = controller.video;
          if (videoCtrl.value.isInitialized && videoCtrl.value.isPlaying) {
            await videoCtrl.pause();
          }
        } catch (error, stackTrace) {
          debugPrint(
            '[EditMediaPage] Failed to pause editor video: $error\n$stackTrace',
          );
        }
        await controller.dispose();
      }
      await _jobProgressSub?.cancel();
      _jobProgressSub = null;
      if (_useNativePreview) {
        await _nativeEditorChannel.release();
      }
      _releasedForNavigation = true;
      PostReviewTelemetry.recordEditorTeardown(
        elapsedMs: stopwatch.elapsedMilliseconds,
      );
    } finally {
      _releasingForNavigation = false;
    }
  }

  void _reinitializeEditorAfterReturn() {
    if (!_isVideo) {
      return;
    }
    final proxy = _activeProxy;
    final path = proxy?.filePath ?? widget.media.originalFilePath;
    final durationMs =
        proxy?.metadata.durationMs ?? widget.media.originalDurationMs;
    final job = _activeJob;
    if (job != null && _jobProgressSub == null) {
      _listenToProxyProgress(job);
    }
    unawaited(
      _initVideoControllerWithSource(
        path: path,
        sourceDurationMs: durationMs,
        isProxySource: proxy != null,
      ),
    );
  }

  void _maybePrepareNativePreview() {
    if (!_useNativePreview || !_videoInitialized) {
      return;
    }
    final viewId = _nativePreviewViewId;
    if (viewId == null) {
      return;
    }
    final mediaPath = _activeProxy?.filePath ?? widget.media.originalFilePath;
    if (mediaPath.isEmpty) {
      return;
    }
    final manifest = currentManifest.toJson();
    unawaited(
      _nativeEditorChannel
          .prepareTimeline(
            sourcePath: widget.media.originalFilePath,
            proxyPath: _activeProxy?.filePath,
            manifest: manifest,
            surfaceId: viewId,
          )
          .then((_) => _nativeEditorChannel.setPlayback(playing: true, speed: 1))
          .catchError((error, stack) {
        debugPrint('Native preview init failed: $error\n$stack');
      }),
    );
  }

  @override
  void didPopNext() {
    super.didPopNext();
    if (!_releasedForNavigation) {
      return;
    }
    _releasedForNavigation = false;
    _reinitializeEditorAfterReturn();
  }

  Future<void> _onContinuePressed() async {
    if (_isNavigatingToReview) {
      return;
    }
    _retainProxyForNextStep = true;
    _isNavigatingToReview = true;

    try {
      await _withPreparingOverlay(_releaseForNavigation);
      if (!mounted) {
        return;
      }

      final draft = PostDraft(
        originalFilePath: widget.media.originalFilePath,
        proxyFilePath: _activeProxy?.filePath,
        proxyMetadata: _activeProxy?.metadata,
        originalDurationMs: widget.media.originalDurationMs,
        type: widget.media.type,
        description: '',
        videoTrim: _buildVideoTrim(),
        coverFrameMs: _buildCoverFrameMs(),
        imageCrop: _buildImageCrop(),
        sourceAssetId: widget.media.sourceAssetId,
        editManifest: currentManifest,
      );

      final route = MaterialPageRoute(
        builder: (_) => PostReviewPage(draft: draft),
      );

      if (kUsePushReplacementForReview) {
        await Navigator.of(context).pushReplacement(route);
      } else {
        await Navigator.of(context).push(route);
      }
    } finally {
      if (mounted) {
        setState(() {
          _retainProxyForNextStep = false;
        });
      } else {
        _retainProxyForNextStep = false;
      }
      if (!_routeAwareSubscribed && mounted && _releasedForNavigation) {
        _releasedForNavigation = false;
        _reinitializeEditorAfterReturn();
      }
      _isNavigatingToReview = false;
    }
  }

  VideoTrimData? _buildVideoTrim() {
    if (!_isVideo) {
      return null;
    }
    final controller = _videoController;
    if (controller == null) {
      return null;
    }
    final start = controller.startTrim.inMilliseconds;
    final end = controller.endTrim.inMilliseconds;
    if (!controller.isTrimmed && start == 0) {
      final duration = controller.videoDuration.inMilliseconds;
      if (end == duration) {
        return null;
      }
    }
    final total = controller.videoDuration.inMilliseconds;
    final trimmed = (end - start).clamp(0, total);
    final durationMs = trimmed.round();
    return VideoTrimData(
      startMs: start,
      endMs: end,
      durationMs: durationMs,
      proxyStartMs: start,
      proxyEndMs: end,
    );
  }

  @visibleForTesting
  RangeValues? get debugVideoTrimRangeMs => _videoTrimRangeMs;

  @visibleForTesting
  RangeValues? get debugGlobalTrimRangeMs => _globalTrimMs;

  @visibleForTesting
  Duration? get debugVideoDuration => _videoDuration;

  @visibleForTesting
  void debugApplyTrimRange(RangeValues range) {
    final duration = _videoDuration;
    if (duration == null) {
      return;
    }
    _onTrimChangeEnd(range, duration);
  }

  @visibleForTesting
  VideoTrimData? debugBuildVideoTrim() => _buildVideoTrim();

  int? _buildCoverFrameMs() {
    if (!_isVideo) {
      return null;
    }
    final controller = _videoController;
    if (controller == null) {
      return null;
    }
    final coverMs = controller.selectedCoverVal?.timeMs;
    if (coverMs == null) {
      return null;
    }
    return coverMs;
  }

  ImageCropData? _buildImageCrop() {
    if (_isVideo) {
      return null;
    }
    if (_imageWidth == null || _imageHeight == null) {
      return null;
    }
    final cropRect = _currentCropRect();
    final rotation = (_rotationTurns % 4) * 90;
    final isIdentity = cropRect.left == 0 &&
        cropRect.top == 0 &&
        cropRect.width == 1 &&
        cropRect.height == 1 &&
        rotation == 0;
    if (isIdentity) {
      return null;
    }
    return ImageCropData(
      x: cropRect.left,
      y: cropRect.top,
      width: cropRect.width,
      height: cropRect.height,
      rotation: rotation.toDouble(),
    );
  }

  void _applyCropOpLocked() {
    if (_isVideo) {
      return;
    }
    final cropRect = _currentCropRect();
    final isIdentity = cropRect.left == 0 &&
        cropRect.top == 0 &&
        cropRect.width == 1 &&
        cropRect.height == 1;
    final replacement = isIdentity
        ? null
        : CropOp(
            left: cropRect.left,
            top: cropRect.top,
            width: cropRect.width,
            height: cropRect.height,
          );
    _editManifest = _editManifest.copyWith(
      ops: _opsWithReplacement(
        predicate: (op) => op is CropOp,
        replacement: replacement,
      ),
    );
    _syncNativeTimeline();
  }

  void _onTrimChangeStart() {
    final controller = _videoController;
    if (controller == null) return;
    controller.isTrimming = true;
    final video = controller.video;
    if (video.value.isInitialized && video.value.isPlaying) {
      video.pause();
    }
    _enforceNativePreviewSilence(controller);
    _trimSeekDebounce?.cancel();
  }

  void _onTrimChanged(RangeValues values, Duration duration) {
    final controller = _videoController;
    if (controller == null) return;
    final totalMs = duration.inMilliseconds.toDouble();
    final clamped = RangeValues(
      values.start.clamp(0, totalMs),
      values.end.clamp(0, totalMs),
    );

    setState(() {
      _videoTrimRangeMs = clamped;
      _globalTrimMs = clamped;
    });

    _trimSeekDebounce?.cancel();
    _trimSeekDebounce = Timer(const Duration(milliseconds: 120), () {
      final video = controller.video;
      if (!video.value.isInitialized) return;
      unawaited(
        video.seekTo(Duration(milliseconds: clamped.start.round())),
      );
      _enforceNativePreviewSilence(controller);
      if (_useNativePreview) {
        unawaited(_nativeEditorChannel.seek(clamped.start.round()));
      }
    });
  }

  void _onTrimChangeEnd(RangeValues values, Duration duration) {
    final controller = _videoController;
    if (controller == null) return;
    _trimSeekDebounce?.cancel();
    final totalMs = duration.inMilliseconds.toDouble();
    final clampedStart = values.start.clamp(0, totalMs);
    final clampedEnd = values.end.clamp(0, totalMs);
    if (clampedEnd <= clampedStart) {
      return;
    }

    controller.isTrimming = false;
    final min = clampedStart / totalMs;
    final max = clampedEnd / totalMs;
    controller.updateTrim(min, max);
    final video = controller.video;
    if (video.value.isInitialized) {
      unawaited(video.seekTo(Duration(milliseconds: clampedStart.round())));
      _enforceNativePreviewSilence(controller);
    }

    _setTrimOp(clampedStart.round(), clampedEnd.round());
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

  String _formatDuration(double milliseconds) {
    final duration = Duration(milliseconds: milliseconds.round());
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    final buffer = StringBuffer();

    if (hours > 0) {
      buffer.write(hours.toString().padLeft(2, '0'));
      buffer.write(':');
    }

    buffer.write(minutes.toString().padLeft(2, '0'));
    buffer.write(':');
    buffer.write(seconds.toString().padLeft(2, '0'));

    return buffer.toString();
  }

  void _handleVideoControllerUpdate() {
    if (!mounted) return;
    final controller = _videoController;
    final duration = _videoDuration;
    if (controller == null || duration == null) {
      return;
    }
    final nextRange = RangeValues(
      controller.startTrim.inMilliseconds.toDouble(),
      controller.endTrim.inMilliseconds.toDouble(),
    );
    if (_videoTrimRangeMs == nextRange) {
      return;
    }
    setState(() {
      _videoTrimRangeMs = nextRange;
    });
  }

  void _applyRotateOpLocked() {
    final normalizedTurns = (_rotationTurns % 4 + 4) % 4;
    _editManifest = _editManifest.copyWith(
      ops: _opsWithReplacement(
        predicate: (op) => op is RotateOp,
        replacement: normalizedTurns == 0 ? null : RotateOp(turns: normalizedTurns),
      ),
    );
    _syncNativeTimeline();
  }

  void _setTrimOp(int startMs, int endMs) {
    if (!mounted) {
      return;
    }
    setState(() {
      _editManifest = _editManifest.copyWith(
        ops: _opsWithReplacement(
          predicate: (op) => op is TrimOp,
          replacement: TrimOp(startMs: startMs, endMs: endMs),
        ),
      );
    });
    _syncNativeTimeline();
  }

  List<EditOp> _opsWithReplacement({
    required bool Function(EditOp op) predicate,
    EditOp? replacement,
  }) {
    final updated = <EditOp>[];
    for (final op in _editManifest.ops) {
      if (!predicate(op)) {
        updated.add(op.copy());
      }
    }
    if (replacement != null) {
      updated.add(replacement);
    }
    return updated;
  }

  EditManifest get currentManifest => _editManifest.copy();

  void _updateNativeTimelineIfNeeded() {
    _syncNativeTimeline();
  }

  void _syncNativeTimeline() {
    if (!_useNativePreview || _nativePreviewViewId == null) {
      return;
    }
    unawaited(
      _nativeEditorChannel.updateTimeline(
        manifest: currentManifest,
        surfaceId: _nativePreviewViewId,
      ),
    );
  }
}

class _PreparingOverlay extends StatelessWidget {
  const _PreparingOverlay();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      children: [
        ModalBarrier(
          color: Colors.black.withValues(alpha: 0.45),
          dismissible: false,
        ),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Text(
                  'Preparing...',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _EditorToolRail extends StatelessWidget {
  final _EditorTool selectedTool;
  final VoidCallback onSelectTrim;
  final VoidCallback onSelectText;

  const _EditorToolRail({
    required this.selectedTool,
    required this.onSelectTrim,
    required this.onSelectText,
  });

  @override
  Widget build(BuildContext context) {
    final Color selectedColor = Theme.of(context).colorScheme.primary;
    final Color unselectedColor =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8);

    Widget buildTool({
      required IconData icon,
      required String label,
      required bool selected,
      required VoidCallback onTap,
    }) {
      final color = selected ? selectedColor : unselectedColor;
      return GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor:
                  selected ? Colors.white.withValues(alpha: 0.12) : Colors.black26,
              child: Icon(icon, color: color),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: color),
            ),
          ],
        ),
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        buildTool(
          icon: Icons.content_cut,
          label: 'Trim',
          selected: selectedTool == _EditorTool.trim,
          onTap: onSelectTrim,
        ),
        const SizedBox(height: 16),
        buildTool(
          icon: Icons.title,
          label: 'Text',
          selected: selectedTool == _EditorTool.text,
          onTap: onSelectText,
        ),
      ],
    );
  }
}

class _AspectRatioOption {
  const _AspectRatioOption(this.id, this.label, this.ratio);

  final String id;
  final String label;
  final double? ratio;

  static const original = _AspectRatioOption('original', 'Original', null);
}

const List<_AspectRatioOption> _aspectRatioOptions = [
  _AspectRatioOption.original,
  _AspectRatioOption('square', '1:1', 1),
  _AspectRatioOption('fourFive', '4:5', 4 / 5),
  _AspectRatioOption('sixteenNine', '16:9', 16 / 9),
];

class _OverlayTextPreview extends StatefulWidget {
  const _OverlayTextPreview({
    required this.overlay,
    required this.videoListenable,
    this.onOverlayChanged,
    this.onOverlayTap,
    this.onOverlayDragStart,
    this.onOverlayDragUpdate,
    this.onOverlayDragEnd,
  });

  final OverlayTextOp overlay;
  final ValueListenable<VideoPlayerValue> videoListenable;
  final ValueChanged<OverlayTextOp>? onOverlayChanged;
  final ValueChanged<OverlayTextOp>? onOverlayTap;
  final VoidCallback? onOverlayDragStart;
  final ValueChanged<Offset>? onOverlayDragUpdate;
  final VoidCallback? onOverlayDragEnd;

  @override
  State<_OverlayTextPreview> createState() => _OverlayTextPreviewState();
}

class _OverlayTextPreviewState extends State<_OverlayTextPreview> {
  OverlayTextOp? _currentOverlay;
  double _startScale = 1.0;
  double _startRotationDeg = 0.0;
  Offset? _lastGlobalFocalPoint;

  @override
  void initState() {
    super.initState();
    _currentOverlay = widget.overlay;
  }

  @override
  void didUpdateWidget(covariant _OverlayTextPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    _currentOverlay = widget.overlay;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: widget.videoListenable,
      builder: (context, value, _) {
        if (!_isVisibleAt(value.position.inMilliseconds)) {
          return const SizedBox.shrink();
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;
            if (size.isEmpty) {
              return const SizedBox.shrink();
            }
            final overlay = widget.overlay;
            final overlayWidget = _buildOverlayWidget(overlay, size);
            if (widget.onOverlayChanged == null) {
              return IgnorePointer(child: overlayWidget);
            }
            return overlayWidget;
          },
        );
      },
    );
  }

  bool _isVisibleAt(int positionMs) {
    final start = widget.overlay.startMs ?? 0;
    final end = widget.overlay.endMs;
    if (end != null && end >= start) {
      return positionMs >= start && positionMs <= end;
    }
    return positionMs >= start;
  }

  Widget _buildOverlayWidget(OverlayTextOp overlay, Size size) {
    final normalizedX = overlay.x.clamp(0.0, 1.0);
    final normalizedY = overlay.y.clamp(0.0, 1.0);

    final clampedScale = _normalizedScale(overlay.scale);
    final radians = overlay.rotationDeg * math.pi / 180;

    final Widget textChild = _buildStyledText(overlay);

    final Widget gestureWrapped = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        widget.onOverlayTap?.call(overlay);
      },
      onScaleStart: (details) => _handleScaleStart(details, overlay, size),
      onScaleUpdate: (details) => _handleScaleUpdate(details, overlay, size),
      onScaleEnd: _handleScaleEnd,
      child: textChild,
    );

    final Widget transformed = Transform.rotate(
      angle: radians,
      child: Transform.scale(
        scale: clampedScale,
        child: gestureWrapped,
      ),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        Align(
          alignment: Alignment(normalizedX * 2 - 1, normalizedY * 2 - 1),
          child: transformed,
        ),
      ],
    );
  }

  Widget _buildStyledText(OverlayTextOp overlay) {
    final textColor = _parseColorHex(overlay.color) ?? Colors.white;
    final backgroundColor = overlay.backgroundColorHex != null
        ? _parseColorHex(overlay.backgroundColorHex!)
        : null;

    final textChild = Text(
      overlay.text,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: textColor,
            fontFamily: overlay.fontFamily,
          ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: backgroundColor != null
          ? BoxDecoration(
              color: backgroundColor.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(8),
            )
          : null,
      child: textChild,
    );
  }

  void _handleScaleStart(
    ScaleStartDetails details,
    OverlayTextOp overlay,
    Size size,
  ) {
    final current = _currentOverlay ?? overlay;

    _startScale = current.scale;
    _startRotationDeg = current.rotationDeg.toDouble();

    // Remember global finger position to compute deltas in screen space
    _lastGlobalFocalPoint = details.focalPoint;

    widget.onOverlayDragStart?.call();
  }

  void _handleScaleUpdate(
    ScaleUpdateDetails details,
    OverlayTextOp overlay,
    Size size,
  ) {
    final current = _currentOverlay ?? overlay;

    // --- Screen-space translation (always up/down/left/right in screen coordinates) ---
    final Offset currentGlobalFocal = details.focalPoint;
    final Offset lastGlobalFocal = _lastGlobalFocalPoint ?? currentGlobalFocal;
    final Offset globalDelta = currentGlobalFocal - lastGlobalFocal;
    _lastGlobalFocalPoint = currentGlobalFocal;

    final double dx = globalDelta.dx / size.width;
    final double dy = globalDelta.dy / size.height;

    double newX = (current.x + dx).clamp(0.0, 1.0);
    double newY = (current.y + dy).clamp(0.0, 1.0);

    // --- Scale and rotation (relative to gesture start, with 2+ fingers) ---
    double newScale = current.scale;
    double newRotationDeg = current.rotationDeg.toDouble();

    if (details.pointerCount >= 2) {
      newScale = _normalizedScale(_startScale * details.scale);
      newRotationDeg =
          _startRotationDeg + details.rotation * 180 / math.pi;
    }

    final updated = current.copyWith(
      x: newX,
      y: newY,
      scale: newScale,
      rotationDeg: newRotationDeg,
    );

    // Keep local state in sync for ultra responsive gestures
    _currentOverlay = updated;

    // Notify parent (manifest + native timeline)
    widget.onOverlayChanged?.call(updated);
    widget.onOverlayDragUpdate?.call(Offset(newX, newY));
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    _lastGlobalFocalPoint = null;

    widget.onOverlayDragEnd?.call();
  }

  double _normalizedScale(double raw) {
    if (!raw.isFinite || raw <= 0) {
      return 1.0;
    }
    return raw.clamp(0.5, 3.0).toDouble();
  }
}

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
