import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:video_editor_2/video_editor.dart';

import '../models/post_draft.dart';
import '../models/video_proxy.dart';
import '../services/video_proxy_service.dart';
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

class _EditMediaPageState extends State<EditMediaPage> {
  static const _videoTrimHeight = 72.0;

  VideoEditorController? _videoController;
  VideoEditorController? _originalVideoController;
  VideoProxyJob? _activeJob;
  VideoProxyResult? _activeProxy;
  bool _usingFallbackProxy = false;
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

  double? _imageWidth;
  double? _imageHeight;
  bool _imageLoading = false;
  bool _imageLoadFailed = false;

  String _selectedAspectId = _AspectRatioOption.original.id;
  int _rotationTurns = 0;

  @override
  void initState() {
    super.initState();
    if (widget.media.type == 'video') {
      final proxyResult = widget.media.proxyResult;
      final proxyJob = widget.media.proxyJob;
      final request = widget.media.proxyRequest;

      unawaited(_initOriginalPreview());

      if (proxyResult != null) {
        _activeProxy = proxyResult;
        _usingFallbackProxy =
            proxyResult.metadata.resolution == VideoProxyResolution.p360;
        unawaited(_initVideoController());
      } else if (proxyJob != null) {
        _attachProxyJob(proxyJob);
      } else if (request != null) {
        final job = VideoProxyService().createJob(
          request: request,
          enableLogging: true,
        );
        _attachProxyJob(job);
      } else {
        setState(() {
          _videoInitError =
              const VideoProxyException('Video proxy missing. Please retry.');
        });
      }
    } else {
      _loadImageMetadata();
    }
  }

  void _attachProxyJob(VideoProxyJob job) {
    _activeJob = job;
    setState(() {
      _videoInitError = null;
      _optimizingProgress = 0;
    });

    _jobProgressSub?.cancel();
    _jobProgressSub = job.progress.listen((event) {
      if (!mounted) return;
      setState(() {
        _optimizingProgress = event.fraction;
      });
    });

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
      unawaited(_initVideoController());
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

  @override
  void dispose() {
    final controller = _videoController;
    if (controller != null) {
      controller.removeListener(_handleVideoControllerUpdate);
      unawaited(controller.dispose());
    }
    final original = _originalVideoController;
    if (original != null && original != controller) {
      original.removeListener(_handleVideoControllerUpdate);
      unawaited(original.dispose());
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
    _jobProgressSub?.cancel();
    _trimSeekDebounce?.cancel();
    super.dispose();
  }

  Future<void> _initOriginalPreview() async {
    final path = widget.media.originalFilePath;
    if (path.isEmpty) {
      return;
    }

    final hintDuration = widget.media.originalDurationMs;
    final maxDuration = hintDuration != null && hintDuration > 0
        ? Duration(milliseconds: hintDuration)
        : const Duration(days: 1);

    final controller = VideoEditorController.file(
      XFile(path),
      maxDuration: maxDuration,
      minDuration: Duration.zero,
    );

    final previous = _originalVideoController;
    if (previous != null) {
      previous.removeListener(_handleVideoControllerUpdate);
      unawaited(previous.dispose());
    }
    _originalVideoController = controller;

    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }

      controller.addListener(_handleVideoControllerUpdate);
      await controller.video.setLooping(true);
      await controller.video.play();

      final range = RangeValues(
        controller.startTrim.inMilliseconds.toDouble(),
        controller.endTrim.inMilliseconds.toDouble(),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _videoController = controller;
        _videoInitialized = true;
        _videoInitError = null;
        _videoDuration = controller.videoDuration;
        _videoTrimRangeMs = range;
        _globalTrimMs ??= range;
      });
    } catch (error, stackTrace) {
      debugPrint(
        '[EditMediaPage] Failed to initialize original preview: $error\n$stackTrace',
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _videoInitError ??= error;
        _videoInitialized = false;
      });
    }
  }

  Future<void> _initVideoController() async {
    final proxy = _activeProxy;
    if (proxy == null) {
      setState(() {
        _videoInitError = const VideoProxyException('Missing video proxy');
      });
      return;
    }

    final durationMs = proxy.metadata.durationMs > 0
        ? proxy.metadata.durationMs
        : (widget.media.originalDurationMs ?? 0);
    final maxDuration = durationMs > 0
        ? Duration(milliseconds: durationMs)
        : const Duration(days: 1);

    final controller = VideoEditorController.file(
      XFile(proxy.filePath),
      maxDuration: maxDuration,
      minDuration: Duration.zero,
    );

    final previous = _videoController;
    if (previous != null) {
      previous.removeListener(_handleVideoControllerUpdate);
      unawaited(previous.dispose());
    }
    final original = _originalVideoController;
    if (original != null && original != previous) {
      original.removeListener(_handleVideoControllerUpdate);
      unawaited(original.dispose());
      _originalVideoController = null;
    } else if (previous != null && previous == original) {
      _originalVideoController = null;
    }

    setState(() {
      _videoController = controller;
      _videoInitialized = false;
      _videoInitError = null;
    });

    try {
      await controller.initialize();
      if (!mounted) return;
      controller.addListener(_handleVideoControllerUpdate);
      setState(() {
        _videoInitialized = true;
        _videoDuration = controller.videoDuration;
        _videoTrimRangeMs = RangeValues(
          controller.startTrim.inMilliseconds.toDouble(),
          controller.endTrim.inMilliseconds.toDouble(),
        );
        _globalTrimMs = _videoTrimRangeMs;
      });
    } catch (error) {
      if (!mounted) return;
      final fallbackSucceeded = await _attemptFallback(error);
      if (fallbackSucceeded) {
        return;
      }
      setState(() {
        _videoInitError ??= error;
      });
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

    await _initVideoController();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Edit ${_isVideo ? 'Video' : 'Image'}'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _isVideo ? _buildVideoEditor() : _buildImageEditor(),
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
        ),
      ),
    );
  }

  bool get _canContinue {
    if (_isVideo) {
      return _videoInitialized &&
          _videoInitError == null &&
          !_isPreparingFallback &&
          _activeProxy != null;
    }
    if (_imageLoadFailed) {
      return false;
    }
    return true;
  }

  Widget _buildVideoEditor() {
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Stack(
            children: [
              Center(
                child: AspectRatio(
                  aspectRatio: aspectRatio,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      color: Colors.black,
                      child: CropGridViewer.preview(controller: controller),
                    ),
                  ),
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
        const SizedBox(height: 16),
        _buildTrimControls(controller),
      ],
    );
  }

  Widget _buildTrimControls(VideoEditorController controller) {
    final duration = _videoDuration;
    final range = _videoTrimRangeMs;
    if (duration == null || range == null) {
      return const SizedBox(
        height: _videoTrimHeight,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final totalMs = duration.inMilliseconds.toDouble();
    final trimRange = RangeValues(
      range.start.clamp(0, totalMs),
      range.end.clamp(0, totalMs),
    );
    final sliderDivisions = duration.inSeconds > 0 ? duration.inSeconds : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Trim: ${_formatDuration(trimRange.start)} - ${_formatDuration(trimRange.end)}',
        ),
        const SizedBox(height: 8),
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
              values: trimRange,
              labels: RangeLabels(
                _formatDuration(trimRange.start),
                _formatDuration(trimRange.end),
              ),
              onChangeStart: (_) => _onTrimChangeStart(),
              onChanged: (values) => _onTrimChanged(values, duration),
              onChangeEnd: (values) => _onTrimChangeEnd(values, duration),
            ),
          ),
        ),
      ],
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
              }),
              icon: const Icon(Icons.rotate_left),
            ),
            IconButton(
              tooltip: 'Rotate right',
              onPressed: () => setState(() {
                _rotationTurns = (_rotationTurns - 1) % 4;
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

  Future<void> _onContinuePressed() async {
    if (_isVideo && _activeProxy == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Video proxy missing. Please retry.')),
      );
      return;
    }

    _retainProxyForNextStep = true;

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
    );

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PostReviewPage(draft: draft),
      ),
    );

    if (mounted) {
      setState(() {
        _retainProxyForNextStep = false;
      });
    } else {
      _retainProxyForNextStep = false;
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

  void _onTrimChangeStart() {
    final controller = _videoController;
    if (controller == null) return;
    controller.isTrimming = true;
    final video = controller.video;
    if (video.value.isInitialized && video.value.isPlaying) {
      video.pause();
    }
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
    }
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
