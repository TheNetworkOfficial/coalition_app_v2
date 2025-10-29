import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

import '../env.dart';
import '../features/auth/providers/auth_state.dart';
import '../features/candidates/models/candidate.dart';
import '../features/candidates/models/candidate_update.dart';
import '../features/candidates/providers/candidates_providers.dart';
import '../features/candidates/ui/candidate_editable_views.dart';
import '../features/candidates/ui/candidate_views.dart';
import '../pickers/lightweight_asset_picker.dart';
import '../providers/app_providers.dart';

class EditCandidatePage extends ConsumerStatefulWidget {
  const EditCandidatePage({super.key, this.candidateId});

  final String? candidateId;

  @override
  ConsumerState<EditCandidatePage> createState() => _EditCandidatePageState();
}

class _EditCandidatePageState extends ConsumerState<EditCandidatePage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _levelCtrl = TextEditingController();
  final _districtCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _avatarCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _facebookCtrl = TextEditingController();
  final _instagramCtrl = TextEditingController();
  final _tiktokCtrl = TextEditingController();
  final _websiteCtrl = TextEditingController();

  Candidate? _loadedCandidate;
  List<String> _tags = <String>[];

  bool _isSaving = false;
  bool _didPopulate = false;

  Map<String, TextEditingController> get _socialControllers => <String, TextEditingController>{
        'phone': _phoneCtrl,
        'email': _emailCtrl,
        'facebook': _facebookCtrl,
        'instagram': _instagramCtrl,
        'tiktok': _tiktokCtrl,
        'website': _websiteCtrl,
      };

  @override
  void dispose() {
    _nameCtrl.dispose();
    _levelCtrl.dispose();
    _districtCtrl.dispose();
    _bioCtrl.dispose();
    _avatarCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _facebookCtrl.dispose();
    _instagramCtrl.dispose();
    _tiktokCtrl.dispose();
    _websiteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final candidateId =
        (widget.candidateId ?? authState.user?.userId ?? '').trim();

    if (candidateId.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Edit Candidate Page'),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('No candidate found to edit.'),
          ),
        ),
      );
    }

    final candidateAsync = ref.watch(candidateDetailProvider(candidateId));
    candidateAsync.whenData(_maybePopulate);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Candidate Page'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : () => _submit(candidateId),
            child: _isSaving
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: candidateAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Failed to load candidate: $error'),
          ),
        ),
        data: (_) {
          final followerCount = _loadedCandidate?.followersCount ?? 0;
          final extraChips = <Widget>[
            if (followerCount > 0)
              Chip(label: Text('$followerCount followers')),
          ];
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                CandidateHeaderEditable(
                  nameController: _nameCtrl,
                  levelController: _levelCtrl,
                  districtController: _districtCtrl,
                  avatarUrlController: _avatarCtrl,
                  nameValidator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Display name is required';
                    }
                    return null;
                  },
                  extraChips: extraChips,
                  onPickAvatar: _pickAndUploadAvatar,
                  onAvatarUploadError: _showAvatarError,
                ),
                const SizedBox(height: 16),
                CandidateBioEditable(bioController: _bioCtrl),
                const SizedBox(height: 16),
                CandidateTagsEditable(
                  initialTags: _tags,
                  onChanged: (tags) => setState(() => _tags = tags),
                ),
                const SizedBox(height: 24),
                const CandidateSectionTitle(text: 'Connect'),
                const SizedBox(height: 8),
                CandidateSocialsEditable(
                  controllers: _socialControllers,
                  onChanged: () => setState(() {}),
                ),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: _isSaving ? null : () => _submit(candidateId),
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save changes'),
                ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  void _maybePopulate(Candidate? candidate) {
    if (_didPopulate || candidate == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _didPopulate) {
        return;
      }
      _nameCtrl.text = candidate.name;
      _levelCtrl.text = candidate.level ?? '';
      _districtCtrl.text = candidate.district ?? '';
      _bioCtrl.text = candidate.description ?? '';
      _avatarCtrl.text =
          candidate.avatarUrl ?? candidate.headshotUrl ?? _avatarCtrl.text;

      final socials = _normalizedSocials(candidate.socials);
      _phoneCtrl.text = socials['phone'] ?? '';
      _emailCtrl.text = socials['email'] ?? '';
      _facebookCtrl.text = socials['facebook'] ?? '';
      _instagramCtrl.text = socials['instagram'] ?? '';
      _tiktokCtrl.text = socials['tiktok'] ?? '';
      _websiteCtrl.text = socials['website'] ?? '';

      final tags = candidate.tags.take(5).toList(growable: false);
      setState(() {
        _tags = List<String>.from(tags);
        _loadedCandidate = candidate;
        _didPopulate = true;
      });
    });
  }

  Future<void> _submit(String candidateId) async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _isSaving = true);

    final socials = <String, String?>{
      'phone': _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
      'email': _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
      'facebook':
          _facebookCtrl.text.trim().isEmpty ? null : _facebookCtrl.text.trim(),
      'instagram': _instagramCtrl.text.trim().isEmpty
          ? null
          : _instagramCtrl.text.trim(),
      'tiktok':
          _tiktokCtrl.text.trim().isEmpty ? null : _tiktokCtrl.text.trim(),
      'website':
          _websiteCtrl.text.trim().isEmpty ? null : _websiteCtrl.text.trim(),
    }..removeWhere((_, value) => value == null);

    final update = CandidateUpdate(
      displayName: _nameCtrl.text.trim(),
      levelOfOffice:
          _levelCtrl.text.trim().isEmpty ? null : _levelCtrl.text.trim(),
      district:
          _districtCtrl.text.trim().isEmpty ? null : _districtCtrl.text.trim(),
      bio: _bioCtrl.text.trim().isEmpty ? null : _bioCtrl.text.trim(),
      priorityTags: List<String>.from(_tags.take(5)),
      avatarUrl:
          _avatarCtrl.text.trim().isEmpty ? null : _avatarCtrl.text.trim(),
      socials: socials.isEmpty ? null : socials,
    );

    final updateCandidate = ref.read(candidateUpdateControllerProvider);

    try {
      await updateCandidate(candidateId, update);
      if (!mounted) {
        return;
      }
      ref.invalidate(candidateDetailProvider(candidateId));
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Candidate profile updated')),
        );
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Failed to update candidate: $error')),
        );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _showAvatarError(Object error) {
    debugPrint('[EditCandidatePage] Avatar update failed: $error');
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Failed to update avatar. Please try again.'),
        ),
      );
  }

  Future<CandidateAvatarSelection?> _pickAndUploadAvatar(
    ValueChanged<ImageProvider?> onPreview,
  ) async {
    final file = await _selectAvatarFile();
    if (file == null) {
      return null;
    }
    final preview = FileImage(file);
    onPreview(preview);
    final remoteUrl = await _uploadAvatarFile(file);
    if (remoteUrl == null || remoteUrl.isEmpty) {
      return null;
    }
    _avatarCtrl.text = remoteUrl;
    return CandidateAvatarSelection(
      previewImage: preview,
      remoteUrl: remoteUrl,
    );
  }

  Future<File?> _selectAvatarFile() async {
    if (!await _ensureMediaPermissions()) {
      return null;
    }

    final permissionOption = const PermissionRequestOption(
      androidPermission: AndroidPermission(
        type: RequestType.common,
        mediaLocation: false,
      ),
    );

    final permissionState = await AssetPicker.permissionCheck(
      requestOption: permissionOption,
    );

    final provider = LightweightAssetPickerProvider(
      maxAssets: 1,
      pathThumbnailSize: const ThumbnailSize.square(120),
      initializeDelayDuration: const Duration(milliseconds: 250),
    );

    final delegate = LightweightAssetPickerBuilderDelegate(
      provider: provider,
      initialPermission: permissionState,
      gridCount: 4,
      gridThumbnailSize: const ThumbnailSize.square(200),
    );

    List<AssetEntity>? assets;
    try {
      assets = await AssetPicker.pickAssetsWithDelegate<AssetEntity,
          AssetPathEntity, LightweightAssetPickerProvider>(
        context,
        delegate: delegate,
        permissionRequestOption: permissionOption,
      );
    } on StateError catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Enable photo permissions to continue.'),
          ),
        );
      }
      return null;
    }

    if (!mounted || assets == null || assets.isEmpty) {
      return null;
    }

    final asset = assets.first;
    if (asset.type != AssetType.image) {
      throw Exception('Please select an image file.');
    }
    final file = await asset.file;
    if (file == null) {
      throw Exception('Unable to read the selected file.');
    }
    return file;
  }

  Future<bool> _ensureMediaPermissions() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return true;
    }

    final permissions = <Permission>{};
    if (Platform.isAndroid) {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      final sdkInt = androidInfo.version.sdkInt;
      if (sdkInt >= 33) {
        permissions.addAll({Permission.photos, Permission.videos});
      } else {
        permissions.add(Permission.storage);
      }
    } else {
      permissions.add(Permission.photos);
    }

    if (permissions.isEmpty) {
      return true;
    }

    final requested = permissions.toList();
    final results = await requested.request();
    final granted = results.values.every(
      (status) =>
          status == PermissionStatus.granted ||
          status == PermissionStatus.limited,
    );

    if (!granted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enable photo permissions to continue.'),
        ),
      );
    }
    return granted;
  }

  Future<String?> _uploadAvatarFile(File file) async {
    final apiClient = ref.read(apiClientProvider);
    final fileSize = await file.length();
    if (fileSize <= 0) {
      throw Exception('Selected file is empty.');
    }

    final fileName = p.basename(file.path);
    final contentType = _inferContentType(file.path);

    final createResponse = await apiClient.postJson(
      '/api/uploads/create',
      body: <String, dynamic>{
        'type': 'image',
        'fileName': fileName,
        'fileSize': fileSize,
        'contentType': contentType,
      },
    );

    if (createResponse.statusCode < 200 ||
        createResponse.statusCode >= 300) {
      final errorBody = createResponse.body;
      throw Exception(
        'createUpload failed with status ${createResponse.statusCode}'
        '${errorBody.isEmpty ? '' : ': $errorBody'}',
      );
    }

    final rawBody = createResponse.body;
    Map<String, dynamic> rawJson;
    try {
      final decoded = jsonDecode(rawBody);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('Unexpected response when creating upload.');
      }
      rawJson = Map<String, dynamic>.from(decoded);
    } catch (error) {
      throw Exception('Failed to parse create upload response: $error');
    }

    final uid = _findStringInRaw(rawJson, const ['uid']) ??
        _findStringInRaw(rawJson, const ['id']);
    if (uid == null || uid.isEmpty) {
      throw Exception('Upload response missing uid or id.');
    }

    final uploadUrlString = _findStringInRaw(
      rawJson,
      const ['uploadurl', 'upload_url', 'uploadUrl', 'uploadURL'],
    );
    if (uploadUrlString == null) {
      throw Exception('Upload response missing uploadURL.');
    }
    final uploadUrl = Uri.tryParse(uploadUrlString);
    if (uploadUrl == null || uploadUrl.host.isEmpty) {
      throw Exception('Upload response contained invalid uploadURL.');
    }

    final deliveryUrl = _findStringInRaw(
      rawJson,
      const ['deliveryurl', 'delivery_url', 'deliveryURL'],
    );

    final headers = _extractStringMapFromRaw(
      rawJson,
      const ['headers', 'uploadheaders', 'uploadHeaders'],
    )..removeWhere((key, _) => key.toLowerCase() == 'content-type');

    final fields = _extractStringMapFromRaw(
      rawJson,
      const ['fields', 'formfields', 'formFields', 'form_data', 'formData'],
    );

    final request = http.MultipartRequest('POST', uploadUrl);
    if (headers.isNotEmpty) {
      request.headers.addAll(headers);
    }
    if (fields.isNotEmpty) {
      request.fields.addAll(fields);
    }
    request.files.add(
      await http.MultipartFile.fromPath('file', file.path),
    );

    debugPrint('[AvatarUpload] POST ${request.url}');
    final response = await request.send();
    final responseBody = await response.stream.bytesToString();
    debugPrint(
      '[AvatarUpload] status=${response.statusCode}'
      '${responseBody.isEmpty ? '' : ' body: $responseBody'}',
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Upload failed with status ${response.statusCode}'
        '${responseBody.isEmpty ? '' : ': $responseBody'}',
      );
    }

    final resolvedUrl = deliveryUrl ??
        _findStringInRaw(rawJson, const ['publicurl', 'public_url']) ??
        _buildDeliveryUrlFromParts(
          uploadId: uid,
          variant: _extractVariant(rawJson),
        );
    if (resolvedUrl == null || resolvedUrl.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text(
                'Avatar uploaded but no public URL could be resolved. Please check Cloudflare Images configuration.',
              ),
            ),
          );
      }
      return null;
    }

    return resolvedUrl;
  }

  Map<String, String> _extractStringMapFromRaw(
    Map<String, dynamic> rawJson,
    List<String> candidateKeys,
  ) {
    final normalizedKeys =
        candidateKeys.map((key) => key.toLowerCase()).toSet();
    final result = <String, String>{};

    void visit(dynamic node) {
      if (node is Map) {
        for (final entry in node.entries) {
          final key = entry.key;
          if (key is String) {
            final normalizedKey = key.toLowerCase();
            if (normalizedKeys.contains(normalizedKey)) {
              final parsed = _toStringMap(entry.value);
              for (final mapEntry in parsed.entries) {
                result.putIfAbsent(mapEntry.key, () => mapEntry.value);
              }
            }
            visit(entry.value);
          }
        }
      } else if (node is Iterable) {
        for (final element in node) {
          visit(element);
        }
      }
    }

    visit(rawJson);
    return result;
  }

  Map<String, String> _toStringMap(dynamic value) {
    if (value is Map) {
      final map = <String, String>{};
      value.forEach((key, dynamic val) {
        if (key is String) {
          final stringValue = _asNonEmptyString(val);
          if (stringValue != null) {
            map.putIfAbsent(key, () => stringValue);
          }
        }
      });
      return map;
    }
    return const <String, String>{};
  }

  String? _extractVariant(Map<String, dynamic> rawJson) {
    final variant = _findStringInRaw(
      rawJson,
      const ['variant', 'imagevariant', 'defaultvariant'],
    );
    if (variant != null) {
      return variant;
    }
    final variantsValue = rawJson['variants'];
    if (variantsValue != null) {
      final nested = _deepStringLookup(
        variantsValue,
        const {'public', 'default', 'variant'},
      );
      if (nested != null && nested.isNotEmpty) {
        return nested;
      }
    }
    return null;
  }

  String? _buildDeliveryUrlFromParts({
    required String? uploadId,
    required String? variant,
  }) {
    final normalizedId = _asNonEmptyString(uploadId);
    if (normalizedId == null) {
      return null;
    }
    final accountHash = kCloudflareImagesAccountHash.trim();
    if (accountHash.isEmpty) {
      return null;
    }
    final variantOverride = _asNonEmptyString(variant);
    final defaultVariant = kCloudflareImagesVariant.trim().isEmpty
        ? 'public'
        : kCloudflareImagesVariant.trim();
    final resolvedVariant = variantOverride?.isNotEmpty == true
        ? variantOverride!
        : defaultVariant;
    return 'https://imagedelivery.net/$accountHash/$normalizedId/$resolvedVariant';
  }

  String? _findStringInRaw(
    Map<String, dynamic> rawJson,
    List<String> candidateKeys,
  ) {
    final normalizedKeys = candidateKeys
        .map((key) => key.toLowerCase())
        .toSet();
    return _deepStringLookup(rawJson, normalizedKeys);
  }

  String? _deepStringLookup(
    dynamic value,
    Set<String> candidateKeys,
  ) {
    if (value is Map) {
      for (final entry in value.entries) {
        final key = entry.key;
        if (key is String && candidateKeys.contains(key.toLowerCase())) {
          final extracted = _asNonEmptyString(entry.value);
          if (extracted != null) {
            return extracted;
          }
        }
      }
      for (final entry in value.entries) {
        final nested = _deepStringLookup(entry.value, candidateKeys);
        if (nested != null) {
          return nested;
        }
      }
    } else if (value is Iterable) {
      for (final element in value) {
        final nested = _deepStringLookup(element, candidateKeys);
        if (nested != null) {
          return nested;
        }
      }
    }
    return null;
  }

  String? _asNonEmptyString(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    final stringValue = value.toString().trim();
    return stringValue.isEmpty ? null : stringValue;
  }


  String _inferContentType(String path) {
    final extension = p.extension(path).toLowerCase();
    switch (extension) {
      case '.png':
        return 'image/png';
      case '.gif':
        return 'image/gif';
      case '.webp':
        return 'image/webp';
      case '.heic':
      case '.heif':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
  }

  Map<String, String> _normalizedSocials(Map<String, String?>? socials) {
    if (socials == null || socials.isEmpty) {
      return const {};
    }
    final map = <String, String>{};
    socials.forEach((key, value) {
      final trimmedKey = key.trim();
      final trimmedValue = value?.trim();
      if (trimmedKey.isNotEmpty && trimmedValue != null && trimmedValue.isNotEmpty) {
        map[trimmedKey] = trimmedValue;
      }
    });
    return map;
  }
}
