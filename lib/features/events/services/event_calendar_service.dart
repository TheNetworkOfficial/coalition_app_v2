import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/event.dart';

Future<void> addEventToCalendar(BuildContext context, Event event) async {
  final start = event.startAt.toUtc();
  final end = (event.endAt ?? event.startAt.add(const Duration(hours: 1))).toUtc();

  final dates =
      '${_formatCalendarDateTime(start)}/${_formatCalendarDateTime(end)}';

  final uri = Uri.https(
    'calendar.google.com',
    '/calendar/render',
    <String, String>{
      'action': 'TEMPLATE',
      'text': event.title,
      if ((event.description ?? '').trim().isNotEmpty)
        'details': event.description!.trim(),
      if ((event.address ?? '').trim().isNotEmpty)
        'location': event.address!.trim()
      else if ((event.locationName ?? event.locationTown)?.trim().isNotEmpty ??
          false)
        'location': (event.locationName ?? event.locationTown)!.trim(),
      'dates': dates,
    },
  );

  try {
    final launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Could not open calendar')),
        );
    }
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('Failed to open calendar: $error')),
      );
  }
}

String _formatCalendarDateTime(DateTime dateTime) {
  String twoDigits(int n) => n.toString().padLeft(2, '0');
  final year = dateTime.year.toString().padLeft(4, '0');
  final month = twoDigits(dateTime.month);
  final day = twoDigits(dateTime.day);
  final hour = twoDigits(dateTime.hour);
  final minute = twoDigits(dateTime.minute);
  final second = twoDigits(dateTime.second);
  return '$year$month${day}T$hour$minute${second}Z';
}
