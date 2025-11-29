import 'package:flutter/foundation.dart';

@immutable
class EventDraft {
  const EventDraft({
    required this.title,
    required this.imageUrl,
    required this.startAt,
    required this.description,
    this.locationTown,
    this.address,
    this.isFree = true,
    this.costAmount,
    this.socials = const <String, String?>{},
  });

  final String title;
  final String imageUrl;
  final DateTime startAt;
  final String description;
  final String? locationTown;
  final String? address;
  final bool isFree;
  final double? costAmount;
  final Map<String, String?> socials;

  Map<String, String?> get _sanitizedSocials {
    final entries = socials.entries
        .where((entry) => (entry.value ?? '').trim().isNotEmpty)
        .map((entry) => MapEntry(entry.key.trim(), entry.value!.trim()))
        .toList(growable: false);
    if (entries.isEmpty) {
      return const <String, String?>{};
    }
    return Map<String, String?>.fromEntries(entries);
  }

  Map<String, dynamic> toJson() {
    final sanitizedSocials = _sanitizedSocials;
    return <String, dynamic>{
      'title': title.trim(),
      'imageUrl': imageUrl.trim(),
      'startAt': startAt.toUtc().toIso8601String(),
      'description': description.trim(),
      if (locationTown != null && locationTown!.trim().isNotEmpty)
        'locationTown': locationTown!.trim(),
      if (address != null && address!.trim().isNotEmpty)
        'address': address!.trim(),
      'isFree': isFree,
      if (!isFree && costAmount != null) 'costAmount': costAmount,
      if (sanitizedSocials.isNotEmpty) 'socials': sanitizedSocials,
    };
  }
}
