import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:uuid/uuid.dart';

class FilePersistenceService {
  FilePersistenceService();

  static const _uploadsSubDirectory = 'uploads';
  static const _maxPersistedEntries = 50;
  static const _maxPersistedAge = Duration(days: 14);
  static final Uuid _uuid = const Uuid();

  Future<Directory> _uploadsDirectory() async {
    final supportDir = await getApplicationSupportDirectory();
    final uploadsDir = Directory(p.join(supportDir.path, _uploadsSubDirectory));
    if (!await uploadsDir.exists()) {
      await uploadsDir.create(recursive: true);
    }
    return uploadsDir;
  }

  Future<File> persistOriginalForUpload(
    String srcPath, {
    String? preferredName,
    String? assetId,
  }) async {
    if (srcPath.trim().isEmpty) {
      throw ArgumentError.value(srcPath, 'srcPath', 'must not be empty');
    }

    var resolvedPath = srcPath;
    var sourceFile = File(resolvedPath);
    if (!await sourceFile.exists()) {
      final assetFile = await _resolveAssetFile(
        assetId: assetId,
        fallbackPath: resolvedPath,
      );
      if (assetFile != null && await assetFile.exists()) {
        resolvedPath = assetFile.path;
        sourceFile = assetFile;
      }
    }

    if (!await sourceFile.exists()) {
      throw FileSystemException('Source file missing', resolvedPath);
    }

    final uploadsDir = await _uploadsDirectory();
    final normalizedUploadsPath = uploadsDir.path;
    final isAlreadyManaged = p.isWithin(normalizedUploadsPath, resolvedPath);
    if (isAlreadyManaged) {
      debugPrint('[FilePersistence] source already persisted: $resolvedPath');
      return sourceFile;
    }

    final extension = p.extension(preferredName ?? resolvedPath);
    final sanitizedExtension = extension.isEmpty ? '' : extension;
    final generatedName = preferredName?.trim().isNotEmpty == true
        ? preferredName!.trim()
        : 'upload_${DateTime.now().millisecondsSinceEpoch}_${_uuid.v4()}';
    final normalizedName = p.setExtension(generatedName, sanitizedExtension);
    final targetPath = p.join(normalizedUploadsPath, normalizedName);
    final persistedFile = await sourceFile.copy(targetPath);
    debugPrint(
      '[FilePersistence][metric] persist_original_bytes=${await persistedFile.length()} target=$targetPath',
    );
    await _maybeTrimCache(exclusions: {persistedFile.path});
    return persistedFile;
  }

  Future<File?> _resolveAssetFile({
    String? assetId,
    String? fallbackPath,
  }) async {
    final inferredId = assetId ?? _inferAssetIdFromPath(fallbackPath);
    if (inferredId == null) {
      return null;
    }
    try {
      final entity = await AssetEntity.fromId(inferredId);
      if (entity == null) {
        return null;
      }
      final origin = await entity.originFile;
      if (origin != null && await origin.exists()) {
        return origin;
      }
      final fallback = await entity.file;
      if (fallback != null && await fallback.exists()) {
        return fallback;
      }
    } catch (error) {
      debugPrint('[FilePersistence] Failed to resolve asset: $error');
    }
    return null;
  }

  String? _inferAssetIdFromPath(String? path) {
    if (path == null) {
      return null;
    }
    final normalized = path.trim();
    if (normalized.isEmpty) {
      return null;
    }
    if (normalized.startsWith('ph://')) {
      return normalized.substring(5);
    }
    if (normalized.startsWith('asset://')) {
      return normalized.substring(8);
    }
    return null;
  }

  Future<void> cleanupObsoleteUploads({
    int maxEntries = _maxPersistedEntries,
    Duration maxAge = _maxPersistedAge,
    Set<String> exclusions = const {},
  }) async {
    await _maybeTrimCache(
      maxEntries: maxEntries,
      maxAge: maxAge,
      exclusions: exclusions,
    );
  }

  Future<void> _maybeTrimCache({
    int maxEntries = _maxPersistedEntries,
    Duration maxAge = _maxPersistedAge,
    Set<String> exclusions = const {},
  }) async {
    try {
      final uploadsDir = await _uploadsDirectory();
      final entries = uploadsDir
          .listSync()
          .whereType<File>()
          .where((file) => !exclusions.contains(file.path))
          .toList()
        ..sort(
          (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
        );

      final now = DateTime.now();
      final stale = <File>[];
      for (var index = 0; index < entries.length; index += 1) {
        final file = entries[index];
        final modified = await file.lastModified();
        final isTooOld = now.difference(modified) > maxAge;
        final exceedsCap = index >= maxEntries;
        if (isTooOld || exceedsCap) {
          stale.add(file);
        }
      }

      if (stale.isEmpty) {
        return;
      }

      for (final file in stale) {
        try {
          debugPrint('[FilePersistence] pruning ${file.path}');
          await file.delete();
        } catch (error) {
          debugPrint('[FilePersistence] failed to delete ${file.path}: $error');
        }
      }
    } catch (error) {
      debugPrint('[FilePersistence] cache cleanup skipped: $error');
    }
  }
}
