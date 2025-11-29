import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/events/models/event.dart';
import '../../features/events/models/event_draft.dart';
import '../../features/events/providers/events_providers.dart';
import '../../providers/app_providers.dart';
import '../../services/api_client.dart';
import '../../shared/media/image_uploader.dart';

class EventEditPage extends ConsumerStatefulWidget {
  const EventEditPage({super.key, this.eventId, this.event});

  final String? eventId;
  final Event? event;

  @override
  ConsumerState<EventEditPage> createState() => _EventEditPageState();
}

class _EventEditPageState extends ConsumerState<EventEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _websiteCtrl = TextEditingController();
  final _otherLinkCtrl = TextEditingController();
  final _costCtrl = TextEditingController();

  DateTime? _startAt;
  bool _isFree = true;
  String? _imageUrl;
  ImageProvider? _imagePreview;
  bool _loadingEvent = false;
  bool _uploadingImage = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _hydrateFromEvent(widget.event);
    _maybeLoadEventFromApi();
  }

  @override
  void didUpdateWidget(covariant EventEditPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.event != oldWidget.event) {
      _hydrateFromEvent(widget.event);
    }
    if (widget.eventId != oldWidget.eventId && widget.event == null) {
      _maybeLoadEventFromApi();
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _cityCtrl.dispose();
    _addressCtrl.dispose();
    _descriptionCtrl.dispose();
    _emailCtrl.dispose();
    _websiteCtrl.dispose();
    _otherLinkCtrl.dispose();
    _costCtrl.dispose();
    super.dispose();
  }

  void _hydrateFromEvent(Event? event) {
    if (event == null) {
      return;
    }
    _titleCtrl.text = event.title;
    _cityCtrl.text = event.locationTown ?? '';
    _addressCtrl.text = event.address ?? event.locationName ?? '';
    _descriptionCtrl.text = event.description ?? '';
    _emailCtrl.text = event.socials?['email'] ?? '';
    _websiteCtrl.text = event.socials?['website'] ?? '';
    _otherLinkCtrl.text =
        event.socials?['link'] ?? event.socials?['other'] ?? '';
    setState(() {
      _startAt = event.startAt;
      _isFree = event.isFree;
      if (!event.isFree && event.costAmount != null) {
        _costCtrl.text = event.costAmount!.toStringAsFixed(2);
      } else {
        _costCtrl.clear();
      }
      _imageUrl = event.imageUrl;
      _imagePreview = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = _resolvedEventId != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit event' : 'New event'),
        actions: [
          TextButton(
            onPressed: _isSaving || _loadingEvent ? null : _submit,
            child: _isSaving
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : _loadingEvent
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_loadingEvent) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _ImagePickerField(
                    imageUrl: _imageUrl,
                    preview: _imagePreview,
                    isUploading: _uploadingImage,
                    onTap: _pickImage,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Name of event',
                    ),
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Name is required';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _descriptionCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                    ),
                    maxLines: 4,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Description is required';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  _DateTimeField(
                    value: _startAt,
                    onPick: _pickDateTime,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _cityCtrl,
                    decoration: const InputDecoration(
                      labelText: 'City',
                      helperText: 'Shown on the event card',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _addressCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Full address',
                      helperText: 'Tapping address opens maps',
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: const Text('Free event'),
                    value: _isFree,
                    onChanged: (value) {
                      setState(() {
                        _isFree = value;
                        if (value) {
                          _costCtrl.clear();
                        }
                      });
                    },
                  ),
                  if (!_isFree) ...[
                    TextFormField(
                      controller: _costCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Ticket price (USD)',
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      validator: (value) {
                        if (_isFree) {
                          return null;
                        }
                        if (value == null || value.trim().isEmpty) {
                          return 'Enter a price';
                        }
                        final parsed = double.tryParse(value.trim());
                        if (parsed == null || parsed <= 0) {
                          return 'Enter a valid amount';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    'Contact',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _emailCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                    ),
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Email is required';
                      }
                      if (!value.contains('@')) {
                        return 'Enter a valid email';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _websiteCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Website (optional)',
                    ),
                    keyboardType: TextInputType.url,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _otherLinkCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Other link (optional)',
                    ),
                    keyboardType: TextInputType.url,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage() async {
    if (_uploadingImage) {
      return;
    }
    setState(() => _uploadingImage = true);
    try {
      final result = await pickAndUploadProfileImage(
        context: context,
        ref: ref,
      );
      if (result == null) {
        return;
      }
      setState(() {
        _imageUrl = result.remoteUrl;
        _imagePreview = result.preview;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(error.message)),
        );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Failed to pick image: $error')),
        );
    } finally {
      if (mounted) {
        setState(() => _uploadingImage = false);
      }
    }
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final initial = _startAt ?? now.add(const Duration(hours: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now,
      lastDate: DateTime(now.year + 5),
    );
    if (date == null) {
      return;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) {
      return;
    }
    final combined = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    setState(() => _startAt = combined);
  }

  Future<void> _maybeLoadEventFromApi() async {
    if (widget.event != null) {
      return;
    }
    final id = widget.eventId;
    if (id == null || id.trim().isEmpty || _loadingEvent) {
      return;
    }
    setState(() => _loadingEvent = true);
    try {
      final event = await ref.read(eventDetailProvider(id).future);
      if (!mounted || event == null) return;
      _hydrateFromEvent(event);
    } on ApiException catch (error) {
      if (!mounted) return;
      _showMessage('Failed to load event: ${error.message}');
    } catch (error) {
      if (!mounted) return;
      _showMessage('Failed to load event: $error');
    } finally {
      if (mounted) {
        setState(() => _loadingEvent = false);
      }
    }
  }

  Future<void> _submit() async {
    if (_isSaving) {
      return;
    }
    if (_loadingEvent) {
      _showMessage('Please wait for the event to finish loading');
      return;
    }
    setState(() => _isSaving = true);
    try {
      final form = _formKey.currentState;
      if (form == null) {
        return;
      }
      if (!form.validate()) {
        return;
      }
      if (_startAt == null) {
        _showMessage('Please choose a date and time');
        return;
      }
      if (!_startAt!.isAfter(DateTime.now())) {
        _showMessage('Event time must be in the future');
        return;
      }
      if (_imageUrl == null || _imageUrl!.isEmpty) {
        _showMessage('Please add a cover image');
        return;
      }

      final cost = _isFree ? null : double.tryParse(_costCtrl.text.trim());
      if (!_isFree && cost == null) {
        _showMessage('Enter a valid price');
        return;
      }

      final socials = <String, String?>{
        'email': _emailCtrl.text.trim(),
        if (_websiteCtrl.text.trim().isNotEmpty)
          'website': _websiteCtrl.text.trim(),
        if (_otherLinkCtrl.text.trim().isNotEmpty)
          'link': _otherLinkCtrl.text.trim(),
      };

      final draft = EventDraft(
        title: _titleCtrl.text.trim(),
        imageUrl: _imageUrl!,
        startAt: _startAt!,
        description: _descriptionCtrl.text.trim(),
        locationTown:
            _cityCtrl.text.trim().isEmpty ? null : _cityCtrl.text.trim(),
        address:
            _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
        isFree: _isFree,
        costAmount: _isFree ? null : cost,
        socials: socials,
      );

      final api = ref.read(apiClientProvider);
      final eventId = _resolvedEventId;
      final wasEditing = eventId != null;
      if (eventId == null) {
        await api.createEvent(draft);
      } else {
        await api.updateEvent(eventId, draft);
        ref.invalidate(eventDetailProvider(eventId));
      }
      ref.invalidate(eventsPagerProvider);
      ref.invalidate(myEventsProvider(MyEventsStatus.active));
      ref.invalidate(myEventsProvider(MyEventsStatus.previous));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(wasEditing ? 'Event updated' : 'Event created!'),
          ),
        );
      context.pop();
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(error.message)),
        );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Failed to save event: $error')),
        );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  String? get _resolvedEventId {
    final fromEvent = widget.event?.eventId.trim();
    if (fromEvent != null && fromEvent.isNotEmpty) {
      return fromEvent;
    }
    final fromWidget = widget.eventId?.trim();
    if (fromWidget != null && fromWidget.isNotEmpty) {
      return fromWidget;
    }
    return null;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ImagePickerField extends StatelessWidget {
  const _ImagePickerField({
    required this.imageUrl,
    required this.preview,
    required this.onTap,
    required this.isUploading,
  });

  final String? imageUrl;
  final ImageProvider? preview;
  final VoidCallback onTap;
  final bool isUploading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final imageProvider = preview ??
        ((imageUrl != null && imageUrl!.trim().isNotEmpty)
            ? NetworkImage(imageUrl!)
            : null);
    return GestureDetector(
      onTap: isUploading ? null : onTap,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: imageProvider != null
                  ? Image(
                      image: imageProvider,
                      fit: BoxFit.cover,
                    )
                  : Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.image_outlined, size: 48),
                          SizedBox(height: 8),
                          Text('Add a cover image'),
                        ],
                      ),
                    ),
            ),
            if (isUploading)
              Container(
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: SizedBox.square(
                    dimension: 36,
                    child: CircularProgressIndicator(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DateTimeField extends StatelessWidget {
  const _DateTimeField({
    required this.value,
    required this.onPick,
  });

  final DateTime? value;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = value == null
        ? 'Select date & time'
        : _formatDateTime(context, value!);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Date & time'),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodyMedium,
      ),
      trailing: const Icon(Icons.calendar_month_outlined),
      onTap: onPick,
    );
  }

  String _formatDateTime(BuildContext context, DateTime dateTime) {
    final localizations = MaterialLocalizations.of(context);
    final date = localizations.formatShortDate(dateTime);
    final time = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(dateTime),
      alwaysUse24HourFormat: false,
    );
    return '$date · $time';
  }
}
