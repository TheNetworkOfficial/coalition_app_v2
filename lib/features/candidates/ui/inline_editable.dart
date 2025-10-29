// Existing picker/uploader inventory:
// - wechat_assets_picker with LightweightAssetPicker for media selection.
// - UploadService + UploadManager handle post media uploads; reused for avatar pipeline.
// - No dedicated image compression helper located; current flows use source files directly.
import 'package:flutter/material.dart';

class InlineEditable extends StatefulWidget {
  const InlineEditable({
    super.key,
    required this.view,
    required this.edit,
    this.startInEdit = false,
  });

  final Widget view;
  final Widget edit;
  final bool startInEdit;

  static _InlineEditableScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_InlineEditableScope>();
  }

  static void completeEditing(BuildContext context) {
    final scope = maybeOf(context);
    scope?.state._finishEditing();
  }

  @override
  State<InlineEditable> createState() => _InlineEditableState();
}

class _InlineEditableState extends State<InlineEditable> {
  late final FocusNode _focusNode;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _isEditing = widget.startInEdit;
    _focusNode = FocusNode();
    _focusNode.addListener(_handleFocusChange);
    if (_isEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _requestFocus();
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant InlineEditable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isEditing && widget.startInEdit && !oldWidget.startInEdit) {
      setState(() {
        _isEditing = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (!_focusNode.hasFocus && _isEditing) {
      _finishEditing();
    }
  }

  void _requestFocus() {
    if (_focusNode.hasFocus) {
      return;
    }
    FocusScope.of(context).requestFocus(_focusNode);
  }

  void _startEditing() {
    if (_isEditing) {
      return;
    }
    setState(() => _isEditing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _requestFocus();
      }
    });
  }

  void _finishEditing() {
    if (!_isEditing) {
      return;
    }
    setState(() => _isEditing = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_isEditing) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _startEditing,
        child: widget.view,
      );
    }

    return FocusScope(
      node: FocusScopeNode(),
      child: Focus(
        focusNode: _focusNode,
        child: _InlineEditableScope(
          state: this,
          child: widget.edit,
        ),
      ),
    );
  }
}

class _InlineEditableScope extends InheritedWidget {
  const _InlineEditableScope({
    required this.state,
    required super.child,
  }) : super();

  final _InlineEditableState state;

  @override
  bool updateShouldNotify(covariant _InlineEditableScope oldWidget) {
    return oldWidget.state != state;
  }
}
