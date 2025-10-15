import 'package:coalition_app_v2/models/video_proxy.dart';
import 'package:coalition_app_v2/services/video_proxy_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ProxyManifestData keeps highest quality segment per index', () {
    final manifest = ProxyManifestData();
    final preview = ProxySegment(
      index: 0,
      path: '/tmp/low.mp4',
      durationMs: 1000,
      width: 360,
      height: 640,
      hasAudio: true,
      quality: ProxyQuality.preview,
    );
    final mezzanine = ProxySegment(
      index: 0,
      path: '/tmp/high.mp4',
      durationMs: 1000,
      width: 720,
      height: 1280,
      hasAudio: true,
      quality: ProxyQuality.mezzanine,
    );
    final duplicatePreview = ProxySegment(
      index: 0,
      path: '/tmp/low2.mp4',
      durationMs: 1000,
      width: 360,
      height: 640,
      hasAudio: true,
      quality: ProxyQuality.preview,
    );

    expect(manifest.addSegment(preview), isTrue);
    expect(manifest.segments.single.path, '/tmp/low.mp4');
    expect(manifest.bestAvailableQuality(), ProxyQuality.preview);

    expect(manifest.addSegment(mezzanine), isTrue);
    expect(manifest.segments.single.path, '/tmp/high.mp4');
    expect(manifest.bestAvailableQuality(), ProxyQuality.mezzanine);
    expect(manifest.availableQualityTiers(),
        contains(ProxySessionQualityTier.full));

    expect(manifest.addSegment(duplicatePreview), isFalse);
    expect(manifest.segments.single.path, '/tmp/high.mp4');
  });
}
