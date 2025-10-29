// Existing picker/uploader inventory:
// - wechat_assets_picker with LightweightAssetPicker for media selection.
// - UploadService + UploadManager handle post media uploads; reused for avatar pipeline.
// - No dedicated image compression helper located; current flows use source files directly.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../widgets/user_avatar.dart';
import 'candidate_views.dart';
import 'inline_editable.dart';

class CandidateAvatarSelection {
  const CandidateAvatarSelection({
    this.previewImage,
    this.remoteUrl,
  });

  final ImageProvider? previewImage;
  final String? remoteUrl;
}

class CandidateHeaderEditable extends StatefulWidget {
  const CandidateHeaderEditable({
    super.key,
    required this.nameController,
    required this.levelController,
    required this.districtController,
    required this.avatarUrlController,
    required this.onPickAvatar,
    this.extraChips = const <Widget>[],
    this.onAvatarUploadError,
    this.nameValidator,
  });

  final TextEditingController nameController;
  final TextEditingController levelController;
  final TextEditingController districtController;
  final TextEditingController avatarUrlController;
  final Future<CandidateAvatarSelection?> Function(
    ValueChanged<ImageProvider?> onPreview,
  ) onPickAvatar;
  final List<Widget> extraChips;
  final ValueChanged<Object>? onAvatarUploadError;
  final FormFieldValidator<String>? nameValidator;

  @override
  State<CandidateHeaderEditable> createState() =>
      _CandidateHeaderEditableState();
}

class _CandidateHeaderEditableState extends State<CandidateHeaderEditable> {
  bool _uploading = false;
  ImageProvider? _localPreview;

  Future<void> _handleAvatarTap() async {
    if (_uploading) {
      return;
    }
    setState(() => _uploading = true);
    final previousPreview = _localPreview;
    try {
      final result = await widget.onPickAvatar((preview) {
        if (!mounted) {
          return;
        }
        setState(() => _localPreview = preview);
      });
      if (!mounted) {
        return;
      }
      if (result == null) {
        setState(() {
          _uploading = false;
          _localPreview = previousPreview;
        });
        return;
      }
      setState(() {
        _localPreview = result.previewImage ?? previousPreview;
      });
      if (result.remoteUrl != null && result.remoteUrl!.isNotEmpty) {
        widget.avatarUrlController.text = result.remoteUrl!;
        setState(() {
          _localPreview = null;
        });
      }
    } catch (error) {
      widget.onAvatarUploadError?.call(error);
      setState(() {
        _localPreview = previousPreview;
      });
    } finally {
      if (mounted) {
        setState(() => _uploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            GestureDetector(
              onTap: _handleAvatarTap,
              child: SizedBox(
                width: 72,
                height: 72,
                child: ClipOval(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      UserAvatar(
                        url: widget.avatarUrlController.text,
                        size: 72,
                      ),
                      if (_localPreview != null)
                        Positioned.fill(
                          child: IgnorePointer(
                            ignoring: true,
                            child: Image(
                              image: _localPreview!,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (_uploading)
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black38,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: SizedBox.square(
                      dimension: 28,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InlineEditable(
                view: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: widget.nameController,
                  builder: (context, value, _) {
                    final text = value.text.trim();
                    return Text(
                      text.isEmpty ? 'Unnamed candidate' : text,
                      style: theme.textTheme.headlineSmall,
                    );
                  },
                ),
                edit: TextFormField(
                  controller: widget.nameController,
                  autofocus: true,
                  style: theme.textTheme.headlineSmall,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  validator: widget.nameValidator,
                  textInputAction: TextInputAction.done,
                  onEditingComplete: () {
                    InlineEditable.completeEditing(context);
                  },
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _EditableChip(
                    controller: widget.levelController,
                    placeholder: 'Tap to add level',
                  ),
                  _EditableChip(
                    controller: widget.districtController,
                    placeholder: 'Tap to add district',
                  ),
                  ...widget.extraChips,
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EditableChip extends StatelessWidget {
  const _EditableChip({
    required this.controller,
    required this.placeholder,
  });

  final TextEditingController controller;
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InlineEditable(
      view: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          final text = value.text.trim();
          if (text.isEmpty) {
            return Chip(
              label: Text(
                placeholder,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.hintColor,
                ),
              ),
            );
          }
          return Chip(label: Text(text));
        },
      ),
      edit: SizedBox(
        width: 180,
        child: TextFormField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
          ),
          textInputAction: TextInputAction.done,
          onEditingComplete: () {
            InlineEditable.completeEditing(context);
          },
        ),
      ),
    );
  }
}

class CandidateBioEditable extends StatelessWidget {
  const CandidateBioEditable({
    super.key,
    required this.bioController,
  });

  final TextEditingController bioController;

  @override
  Widget build(BuildContext context) {
    return InlineEditable(
      view: ValueListenableBuilder<TextEditingValue>(
        valueListenable: bioController,
        builder: (context, value, _) =>
            CandidateBioView(bio: value.text.trim()),
      ),
      edit: TextFormField(
        controller: bioController,
        autofocus: true,
        maxLines: null,
        minLines: 3,
        keyboardType: TextInputType.multiline,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
        ),
        onEditingComplete: () {
          InlineEditable.completeEditing(context);
        },
      ),
    );
  }
}

class CandidateTagsEditable extends StatefulWidget {
  const CandidateTagsEditable({
    super.key,
    required this.initialTags,
    required this.onChanged,
    this.maxTags = 5,
  });

  final List<String> initialTags;
  final ValueChanged<List<String>> onChanged;
  final int maxTags;

  @override
  State<CandidateTagsEditable> createState() => _CandidateTagsEditableState();
}

class _CandidateTagsEditableState extends State<CandidateTagsEditable> {
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  late List<String> _tags;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _tags = _sanitize(widget.initialTags);
  }

  @override
  void didUpdateWidget(covariant CandidateTagsEditable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.initialTags, widget.initialTags)) {
      _tags = _sanitize(widget.initialTags);
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  List<String> _sanitize(List<String> tags) {
    return tags
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toSet()
        .take(widget.maxTags)
        .toList(growable: true);
  }

  void _notifyChange() {
    widget.onChanged(List<String>.unmodifiable(_tags));
  }

  void _removeTag(String tag) {
    setState(() {
      _tags.remove(tag);
    });
    _notifyChange();
  }

  void _showAdder() {
    if (_tags.length >= widget.maxTags) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('You can add up to ${widget.maxTags} tags.'),
          ),
        );
      return;
    }
    setState(() {
      _adding = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        FocusScope.of(context).requestFocus(_inputFocusNode);
      }
    });
  }

  void _addTag() {
    final value = _inputController.text.trim();
    if (value.isEmpty) {
      return;
    }
    if (_tags.contains(value)) {
      _inputController.clear();
      setState(() {
        _adding = false;
      });
      return;
    }
    if (_tags.length >= widget.maxTags) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('You can add up to ${widget.maxTags} tags.'),
          ),
        );
      return;
    }
    setState(() {
      _tags.add(value);
      _inputController.clear();
      _adding = false;
    });
    _notifyChange();
  }

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      for (final tag in _tags)
        InputChip(
          label: Text(tag),
          onDeleted: () => _removeTag(tag),
        ),
      if (!_adding)
        ActionChip(
          label: const Text('Add tag'),
          avatar: const Icon(Icons.add),
          onPressed: _showAdder,
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: chips,
        ),
        if (_adding) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _inputController,
                  focusNode: _inputFocusNode,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Add priority tag',
                    helperText:
                        '${_tags.length}/${widget.maxTags} tags used',
                  ),
                  onSubmitted: (_) => _addTag(),
                ),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: _addTag,
                child: const Text('Add'),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Cancel',
                onPressed: () {
                  setState(() {
                    _adding = false;
                    _inputController.clear();
                  });
                },
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class CandidateSocialsEditable extends StatelessWidget {
  const CandidateSocialsEditable({
    super.key,
    required this.controllers,
    this.onChanged,
    this.socialOrder = const <String>[
      'phone',
      'email',
      'facebook',
      'instagram',
      'tiktok',
      'website',
    ],
  });

  final Map<String, TextEditingController> controllers;
  final VoidCallback? onChanged;
  final List<String> socialOrder;

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[];
    for (final key in socialOrder) {
      final controller = controllers[key];
      if (controller == null) {
        continue;
      }
      tiles.add(
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            final text = value.text.trim();
            final label = candidateSocialLabel(key);
            final subtitle = text.isEmpty ? 'Tap to add $label' : text;
            final subtitleStyle = text.isEmpty
                ? Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Theme.of(context).hintColor)
                : Theme.of(context).textTheme.bodyMedium;
            return InlineEditable(
              view: ListTile(
                leading: Icon(
                  kCandidateSocialIcons[key] ?? Icons.link_outlined,
                ),
                title: Text(label),
                subtitle: Text(
                  subtitle,
                  style: subtitleStyle,
                ),
                dense: true,
              ),
              edit: ListTile(
                leading: Icon(
                  kCandidateSocialIcons[key] ?? Icons.link_outlined,
                ),
                title: TextFormField(
                  controller: controller,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: label,
                  ),
                  textInputAction: TextInputAction.done,
                  onEditingComplete: () {
                    InlineEditable.completeEditing(context);
                    onChanged?.call();
                  },
                ),
              ),
            );
          },
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Column(children: tiles),
    );
  }
}
