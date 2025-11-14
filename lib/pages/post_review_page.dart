import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../env.dart';
import '../models/post_draft.dart';
import '../providers/upload_manager.dart';
import '../services/video_proxy_service.dart';

class PostReviewPage extends ConsumerStatefulWidget {
  const PostReviewPage({super.key, required this.draft});

  final PostDraft draft;

  @override
  ConsumerState<PostReviewPage> createState() => _PostReviewPageState();
}

class _PostReviewPageState extends ConsumerState<PostReviewPage> {
  static const int _coverThumbnailMaxDimension = 720;

  late final TextEditingController _descriptionController;
  bool _isPosting = false;
  VideoPlayerController? _videoController;
  Future<void>? _videoInitFuture;
  Duration? _trimStart;
  Duration? _trimEnd;
  Duration? _videoDuration;
  int? _coverFrameMs;
  Uint8List? _coverThumbnail;
  bool _isCoverLoading = false;
  Object? _videoInitError;

  @override
  void initState() {
    super.initState();
    _descriptionController =
        TextEditingController(text: widget.draft.description);

    if (widget.draft.type == 'video') {
      final initialCover =
          widget.draft.coverFrameMs ?? widget.draft.videoTrim?.startMs ?? 0;
      _coverFrameMs = initialCover;
      if (!kIsWeb) {
        _initializeVideoPreview();
      }
    } else {
      _coverFrameMs = widget.draft.coverFrameMs;
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _videoController?.removeListener(_handleVideoLoop);
    _videoController?.dispose();
    _cleanupProxyCache();
    super.dispose();
  }

  Future<void> _handlePost() async {
    if (_isPosting) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _isPosting = true;
    });

    final uploadManager = ref.read(uploadManagerProvider);
    final router = GoRouter.of(context);
    final navigator = Navigator.of(context);

    try {
      final updatedDraft = widget.draft.copyWith(
        description: _descriptionController.text,
        coverFrameMs: widget.draft.type == 'video'
            ? _effectiveCoverFrameMs
            : widget.draft.coverFrameMs,
      );

      final uploadFuture = uploadManager.startUpload(
        draft: updatedDraft,
        description: _descriptionController.text,
      );

      if (kBlockOnUpload) {
        final outcome = await uploadFuture;
        if (!mounted) {
          return;
        }
        if (!outcome.ok) {
          final friendlyMessage =
              outcome.message ?? 'Failed to finalize upload.';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyMessage)),
          );
          return;
        }
        _cleanupProxyCache();
        _navigateToFeed(navigator, router);
      } else {
        uploadFuture.then((outcome) {
          if (outcome.ok) {
            _cleanupProxyCache();
          } else {
            debugPrint(
              '[PostReviewPage] Upload failed after navigation: ${outcome.message}',
            );
          }
        }).catchError((error, stackTrace) {
          debugPrint('[PostReviewPage] Upload future failed: $error\n$stackTrace');
        });
        _navigateToFeed(navigator, router);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start upload: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isPosting = false;
        });
      }
    }
  }

  void _navigateToFeed(NavigatorState navigator, GoRouter router) {
    navigator.popUntil((route) => route.isFirst);
    router.go('/feed');
  }

  void _initializeVideoPreview() {
    if (kIsWeb) {
      return;
    }
    final trim = widget.draft.videoTrim;
    _trimStart =
        trim != null ? Duration(milliseconds: trim.startMs) : Duration.zero;
    _trimEnd = trim != null ? Duration(milliseconds: trim.endMs) : null;

    final controller = VideoPlayerController.file(
      File(widget.draft.videoPlaybackPath(preferOriginal: true)),
    );
    _videoController = controller;
    _videoInitFuture = controller.initialize().then((_) {
      _videoDuration = controller.value.duration;
      final start = _trimStart ?? Duration.zero;
      final safeStart = _clampDuration(start);
      controller.setLooping(true);
      controller.seekTo(safeStart);
      controller.play();
      controller.addListener(_handleVideoLoop);
      setState(() {
        final fallback = _coverFrameMs ?? safeStart.inMilliseconds;
        _coverFrameMs = _clampFrameMs(fallback);
      });
    }).catchError((error) {
      if (mounted) {
        setState(() {
          _videoInitError = error;
        });
      }
    });
  }

  void _handleVideoLoop() {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    final end = _trimEnd ?? _videoDuration;
    if (end == null) {
      return;
    }
    final position = controller.value.position;
    if (position >= end) {
      controller.seekTo(_trimStart ?? Duration.zero);
    }
  }

  void _cleanupProxyCache() {
    final proxyPath = widget.draft.proxyFilePath;
    if (proxyPath != null) {
      unawaited(VideoProxyService().deleteProxy(proxyPath));
    }
  }

  Future<void> _refreshCoverThumbnail(int? frameMs) async {
    if (kIsWeb || frameMs == null) {
      return;
    }
    final clamped = _clampFrameMs(frameMs);
    setState(() {
      _isCoverLoading = true;
    });
    final bytes = await _createThumbnail(clamped);
    if (!mounted) {
      return;
    }
    setState(() {
      _coverFrameMs = clamped;
      _coverThumbnail = bytes;
      _isCoverLoading = false;
    });
  }

  Future<Uint8List?> _createThumbnail(int frameMs) async {
    if (kIsWeb) {
      return null;
    }
    try {
      return await VideoThumbnail.thumbnailData(
        video: widget.draft.videoPlaybackPath(preferOriginal: true),
        timeMs: frameMs,
        quality: 80,
        imageFormat: ImageFormat.JPEG,
        maxHeight: _coverThumbnailMaxDimension,
        maxWidth: _coverThumbnailMaxDimension,
      );
    } catch (error) {
      debugPrint('Cover thumbnail generation failed: $error');
      return null;
    }
  }

  int? get _effectiveCoverFrameMs {
    if (widget.draft.type != 'video') {
      return widget.draft.coverFrameMs;
    }
    final baseFrame = _coverFrameMs ??
        widget.draft.coverFrameMs ??
        widget.draft.videoTrim?.startMs ??
        (_trimStart ?? Duration.zero).inMilliseconds;
    return _clampFrameMs(baseFrame);
  }

  int _clampFrameMs(int frameMs) {
    final min = (_trimStart ?? Duration.zero).inMilliseconds;
    final maxDuration = _trimEnd ?? _videoDuration;
    if (maxDuration == null) {
      return frameMs < min ? min : frameMs;
    }
    final max = maxDuration.inMilliseconds;
    if (max <= min) {
      return min;
    }
    final clamped = frameMs.clamp(min, max);
    return clamped.toInt();
  }

  Duration _clampDuration(Duration input) {
    final duration = _videoDuration;
    if (duration == null || duration <= Duration.zero) {
      return input;
    }
    final clamped = input.inMilliseconds.clamp(0, duration.inMilliseconds);
    return Duration(milliseconds: clamped);
  }

  String _formatMilliseconds(int ms) {
    final duration = Duration(milliseconds: ms);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    final hoursPart = hours > 0 ? '${hours.toString().padLeft(2, '0')}:' : '';
    final minutesPart = minutes.toString().padLeft(2, '0');
    final secondsPart = seconds.toString().padLeft(2, '0');
    return '$hoursPart$minutesPart:$secondsPart';
  }

  Future<void> _showCoverPicker() async {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized || kIsWeb) {
      return;
    }
    final startMs = (_trimStart ?? Duration.zero).inMilliseconds.toDouble();
    final endDuration = _trimEnd ?? _videoDuration ?? controller.value.duration;
    final endMs = endDuration.inMilliseconds.toDouble();
    double sliderValue =
        (_effectiveCoverFrameMs ?? startMs.toInt()).toDouble().clamp(
              startMs,
              endMs > startMs ? endMs : startMs + 1,
            );
    final Uint8List? initialBytes = _coverThumbnail;

    final result = await showModalBottomSheet<_CoverSelection>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        double currentValue = sliderValue;
        Uint8List? previewBytes = initialBytes;
        bool localLoading = previewBytes == null;
        bool initialPreviewRequested = previewBytes != null;
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> loadPreview(double value) async {
              setModalState(() {
                localLoading = true;
              });
              final bytes = await _createThumbnail(value.toInt());
              if (!mounted) {
                return;
              }
              setModalState(() {
                previewBytes = bytes;
                localLoading = false;
              });
            }

            if (!initialPreviewRequested && previewBytes == null) {
              initialPreviewRequested = true;
              Future<void>(() async {
                final bytes = await _createThumbnail(currentValue.toInt());
                if (!mounted) {
                  return;
                }
                setModalState(() {
                  previewBytes = bytes;
                  localLoading = false;
                });
              });
            }

            Future<void> updatePreview(double value) async {
              setModalState(() {
                currentValue = value;
              });
              await loadPreview(value);
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Select cover frame',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 200,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: previewBytes != null
                            ? FittedBox(
                                fit: BoxFit.contain,
                                child: Image.memory(
                                  previewBytes!,
                                ),
                              )
                            : localLoading
                                ? const Center(
                                    child: CircularProgressIndicator(),
                                  )
                                : const Center(
                                    child: Icon(
                                      Icons.image_not_supported_outlined,
                                      size: 40,
                                    ),
                                  ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Slider(
                      min: startMs,
                      max: endMs > startMs ? endMs : startMs + 1,
                      value: currentValue.clamp(
                        startMs,
                        endMs > startMs ? endMs : startMs + 1,
                      ),
                      onChanged: (value) {
                        setModalState(() {
                          currentValue = value;
                        });
                      },
                      onChangeEnd: updatePreview,
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_formatMilliseconds(currentValue.toInt())),
                        if (localLoading)
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.of(context).pop(
                                _CoverSelection(
                                  frameMs: currentValue.toInt(),
                                  bytes: previewBytes,
                                ),
                              );
                            },
                            child: const Text('Save cover'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (!mounted || result == null) {
      return;
    }

    setState(() {
      _coverFrameMs = result.frameMs;
      if (result.bytes != null) {
        _coverThumbnail = result.bytes;
      }
    });
    if (result.bytes == null) {
      unawaited(_refreshCoverThumbnail(result.frameMs));
    }
  }

  Widget _buildVideoPreview(BorderRadius borderRadius) {
    final controller = _videoController;
    if (_videoInitError != null) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: _PreviewPlaceholder(
          icon: Icons.error_outline,
          label: 'Unable to load video preview',
        ),
      );
    }
    if (controller == null) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: const SizedBox(
          height: 240,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    return ClipRRect(
      borderRadius: borderRadius,
      child: FutureBuilder<void>(
        future: _videoInitFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox(
              height: 240,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError) {
            return const _PreviewPlaceholder(
              icon: Icons.error_outline,
              label: 'Unable to load video preview',
            );
          }
          final aspectRatio = controller.value.aspectRatio == 0
              ? 9 / 16
              : controller.value.aspectRatio;
          final mediaQuery = MediaQuery.of(context);
          final maxHeight = mediaQuery.size.height * (2 / 3);
          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: AspectRatio(
              aspectRatio: aspectRatio,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    color: Colors.black,
                    child: VideoPlayer(controller),
                  ),
                  Positioned(
                    left: 12,
                    bottom: 12,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Row(
                        children: [
                          _buildPlayPauseButton(),
                          const SizedBox(width: 12),
                          Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: ValueListenableBuilder<VideoPlayerValue>(
                              valueListenable: controller,
                              builder: (_, value, __) => Text(
                                _formatMilliseconds(
                                  value.position.inMilliseconds,
                                ),
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: Colors.black54,
                      ),
                      onPressed: _isCoverLoading ? null : _showCoverPicker,
                      icon: const Icon(Icons.photo),
                      label: const Text('Edit cover'),
                    ),
                  ),
                  if (_isCoverLoading)
                    const Positioned.fill(
                      child: ColoredBox(
                        color: Color(0x55000000),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPlayPauseButton() {
    final controller = _videoController!;
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (_, value, __) {
        final isPlaying = value.isPlaying;
        return IconButton(
          onPressed: () {
            if (isPlaying) {
              controller.pause();
            } else {
              final start = _trimStart ?? Duration.zero;
              if (value.position < start ||
                  (_trimEnd != null && value.position >= _trimEnd!)) {
                controller.seekTo(start);
              }
              controller.play();
            }
          },
          icon: Icon(
            isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
          ),
          color: Colors.white,
          iconSize: 32,
        );
      },
    );
  }

  Widget _buildPreview() {
    final borderRadius = BorderRadius.circular(16);
    final trim = widget.draft.videoTrim;
    final crop = widget.draft.imageCrop;
    final coverFrame = widget.draft.type == 'video'
        ? _effectiveCoverFrameMs
        : widget.draft.coverFrameMs;

    Widget previewContent;
    if (widget.draft.type == 'video' && !kIsWeb) {
      previewContent = _buildVideoPreview(borderRadius);
    } else if (widget.draft.type == 'image' && !kIsWeb) {
      previewContent = ClipRRect(
        borderRadius: borderRadius,
        child: Image.file(
          File(widget.draft.originalFilePath),
          height: 240,
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return const _PreviewPlaceholder(
              icon: Icons.image_not_supported_outlined,
              label: 'Unable to load image preview',
            );
          },
        ),
      );
    } else {
      previewContent = ClipRRect(
        borderRadius: borderRadius,
        child: _PreviewPlaceholder(
          icon: widget.draft.type == 'video'
              ? Icons.videocam_outlined
              : Icons.image_outlined,
          label: 'Preview unavailable on this platform',
        ),
      );
    }

    final infoLines = <String>[];
    if (trim != null) {
      infoLines.add(
        'Trim: ${_formatMilliseconds(trim.startMs)} - ${_formatMilliseconds(trim.endMs)}',
      );
    }
    if (coverFrame != null) {
      infoLines.add('Cover @ ${_formatMilliseconds(coverFrame)}');
    }
    if (crop != null) {
      infoLines.add(
        'Crop x${crop.x.toStringAsFixed(2)}, y${crop.y.toStringAsFixed(2)}, '
        'w${crop.width.toStringAsFixed(2)}, h${crop.height.toStringAsFixed(2)}',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        previewContent,
        if (infoLines.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in infoLines)
                  Text(
                    line,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Review Post'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                children: [
                  _buildPreview(),
                  const SizedBox(height: 16),
                  Text(
                    widget.draft.type.toUpperCase(),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _descriptionController,
                    maxLines: 5,
                    minLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isPosting ? null : _handlePost,
              style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48)),
              child: _isPosting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Post'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoverSelection {
  const _CoverSelection({required this.frameMs, this.bytes});

  final int frameMs;
  final Uint8List? bytes;
}

class _PreviewPlaceholder extends StatelessWidget {
  const _PreviewPlaceholder({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 240,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 48,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
