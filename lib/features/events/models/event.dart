import 'package:equatable/equatable.dart';

class Event extends Equatable {
  const Event({
    required this.eventId,
    required this.title,
    required this.startAt,
    this.endAt,
    this.imageUrl,
    this.description,
    this.locationTown,
    this.locationName,
    this.address,
    this.hostUserId,
    this.hostUsername,
    this.hostDisplayName,
    this.attendeeCount = 0,
    this.isAttending = false,
    this.isFree = true,
    this.costAmount,
    this.socials,
    this.tags = const <String>[],
  });

  final String eventId;
  final String title;
  final String? imageUrl;
  final String? description;
  final DateTime startAt;
  final DateTime? endAt;
  final String? locationTown;
  final String? locationName;
  final String? address;
  final String? hostUserId;
  final String? hostUsername;
  final String? hostDisplayName;
  final int attendeeCount;
  final bool isAttending;
  final bool isFree;
  final double? costAmount;
  final Map<String, String?>? socials;
  final List<String> tags;

  String get displayHost {
    final username = hostUsername?.trim();
    if (username != null && username.isNotEmpty) {
      return username;
    }
    final display = hostDisplayName?.trim();
    if (display != null && display.isNotEmpty) {
      return display;
    }
    return hostUserId?.trim().isNotEmpty == true
        ? hostUserId!.trim()
        : 'Unknown';
  }

  String get displayTown {
    final town = locationTown?.trim();
    if (town != null && town.isNotEmpty) {
      return town;
    }
    final name = locationName?.trim();
    if (name != null && name.isNotEmpty) {
      return name;
    }
    return 'TBD';
  }

  factory Event.fromJson(Map<String, dynamic> json) {
    List<String> resolveTags(dynamic value) {
      if (value is List) {
        return value
            .whereType<String>()
            .map((tag) => tag.trim())
            .where((tag) => tag.isNotEmpty)
            .toList(growable: false);
      }
      return const <String>[];
    }

    DateTime _parseDate(dynamic raw) {
      if (raw is int) {
        return DateTime.fromMillisecondsSinceEpoch(raw, isUtc: true).toLocal();
      }
      if (raw is String) {
        final trimmed = raw.trim();
        if (trimmed.isEmpty) {
          return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true).toLocal();
        }
        final parsed = DateTime.tryParse(trimmed);
        if (parsed != null) {
          return parsed.toLocal();
        }
      }
      return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true).toLocal();
    }

    DateTime? _parseDateOptional(dynamic raw) {
      if (raw == null) {
        return null;
      }
      if (raw is int) {
        return DateTime.fromMillisecondsSinceEpoch(raw, isUtc: true).toLocal();
      }
      if (raw is String) {
        final trimmed = raw.trim();
        if (trimmed.isEmpty) {
          return null;
        }
        final parsed = DateTime.tryParse(trimmed);
        if (parsed != null) {
          return parsed.toLocal();
        }
      }
      return null;
    }

    String readString(dynamic value) => value == null ? '' : value.toString();

    String? readNullable(dynamic value) {
      final text = readString(value).trim();
      return text.isEmpty ? null : text;
    }

    int readInt(dynamic value) {
      if (value is num) {
        return value.toInt();
      }
      if (value is String) {
        final parsed = int.tryParse(value);
        if (parsed != null) {
          return parsed;
        }
      }
      return 0;
    }

    double? readDouble(dynamic value) {
      if (value is num) {
        return value.toDouble();
      }
      if (value is String) {
        final parsed = double.tryParse(value.trim());
        if (parsed != null) {
          return parsed;
        }
      }
      return null;
    }

    final rawId =
        (json['eventId'] ?? json['id'] ?? json['event_id'] ?? '').toString();

    final title = readString(json['title'] ?? json['name']).trim().isEmpty
        ? 'Untitled event'
        : readString(json['title'] ?? json['name']).trim();

    final imageUrl = readNullable(
      json['imageUrl'] ??
          json['image'] ??
          json['coverUrl'] ??
          json['pictureUrl'] ??
          json['picture'],
    );

    final address = readNullable(
      json['address'] ??
          json['locationAddress'] ??
          json['fullAddress'] ??
          json['location_address'],
    );

    final costAmount = readDouble(
      json['costAmount'] ?? json['price'] ?? json['cost'],
    );

    bool resolveIsFree() {
      final rawIsFree = json['isFree'];
      if (rawIsFree is bool) {
        return rawIsFree;
      }
      if (rawIsFree is num) {
        return rawIsFree == 1;
      }
      if (rawIsFree is String) {
        final lowered = rawIsFree.toLowerCase().trim();
        if (lowered == 'true' || lowered == '1' || lowered == 'yes') {
          return true;
        }
        if (lowered == 'false' || lowered == '0' || lowered == 'no') {
          return false;
        }
      }
      return costAmount == null;
    }

    return Event(
      eventId: rawId.trim(),
      title: title,
      imageUrl: imageUrl,
      description: readString(json['description']).trim().isEmpty
          ? null
          : readString(json['description']).trim(),
      startAt: _parseDate(
        json['startAt'] ??
            json['startAtIso'] ??
            json['start_at'] ??
            json['start_at_iso'],
      ),
      endAt: _parseDateOptional(
        json['endAt'] ??
            json['endAtIso'] ??
            json['end_at'] ??
            json['end_at_iso'],
      ),
      locationTown:
          readString(json['locationTown'] ?? json['town']).trim().isEmpty
              ? null
              : readString(json['locationTown'] ?? json['town']).trim(),
      locationName:
          readString(json['locationName'] ?? json['location']).trim().isEmpty
              ? null
              : readString(json['locationName'] ?? json['location']).trim(),
      address: address,
      hostUserId:
          readString(json['hostUserId'] ?? json['hostId']).trim().isEmpty
              ? null
              : readString(json['hostUserId'] ?? json['hostId']).trim(),
      hostUsername:
          readString(json['hostUsername'] ?? json['host']).trim().isEmpty
              ? null
              : readString(json['hostUsername'] ?? json['host']).trim(),
      hostDisplayName:
          readString(json['hostDisplayName'] ?? json['hostName'])
                  .trim()
                  .isEmpty
              ? null
              : readString(json['hostDisplayName'] ?? json['hostName']).trim(),
      attendeeCount: readInt(json['attendeeCount'] ?? json['attendance']),
      isAttending: json['isAttending'] == true || json['attending'] == true,
      isFree: resolveIsFree(),
      costAmount: costAmount,
      socials: _readSocials(json['socials']),
      tags: resolveTags(json['tags']),
    );
  }

  Event copyWith({
    String? title,
    String? imageUrl,
    String? description,
    DateTime? startAt,
    DateTime? endAt,
    String? locationTown,
    String? locationName,
    String? address,
    String? hostUserId,
    String? hostUsername,
    String? hostDisplayName,
    int? attendeeCount,
    bool? isAttending,
    bool? isFree,
    double? costAmount,
    Map<String, String?>? socials,
    List<String>? tags,
  }) {
    return Event(
      eventId: eventId,
      title: title ?? this.title,
      imageUrl: imageUrl ?? this.imageUrl,
      description: description ?? this.description,
      startAt: startAt ?? this.startAt,
      endAt: endAt ?? this.endAt,
      locationTown: locationTown ?? this.locationTown,
      locationName: locationName ?? this.locationName,
      address: address ?? this.address,
      hostUserId: hostUserId ?? this.hostUserId,
      hostUsername: hostUsername ?? this.hostUsername,
      hostDisplayName: hostDisplayName ?? this.hostDisplayName,
      attendeeCount: attendeeCount ?? this.attendeeCount,
      isAttending: isAttending ?? this.isAttending,
      isFree: isFree ?? this.isFree,
      costAmount: costAmount ?? this.costAmount,
      socials: socials ?? this.socials,
      tags: tags ?? this.tags,
    );
  }

  Map<String, dynamic> toJson() {
    final sanitizedSocials = socials == null
        ? null
        : Map<String, String?>.fromEntries(
            socials!.entries.where(
              (entry) => (entry.value ?? '').trim().isNotEmpty,
            ),
          );
    return <String, dynamic>{
      'eventId': eventId,
      'title': title,
      if (imageUrl != null && imageUrl!.trim().isNotEmpty)
        'imageUrl': imageUrl!.trim(),
      if (description != null) 'description': description,
      'startAt': startAt.toUtc().toIso8601String(),
      if (endAt != null) 'endAt': endAt!.toUtc().toIso8601String(),
      if (locationTown != null) 'locationTown': locationTown,
      if (locationName != null) 'locationName': locationName,
      if (address != null && address!.trim().isNotEmpty)
        'address': address!.trim(),
      if (hostUserId != null) 'hostUserId': hostUserId,
      if (hostUsername != null) 'hostUsername': hostUsername,
      if (hostDisplayName != null) 'hostDisplayName': hostDisplayName,
      'attendeeCount': attendeeCount,
      'isAttending': isAttending,
      'isFree': isFree,
      if (!isFree && costAmount != null) 'costAmount': costAmount,
      if (tags.isNotEmpty) 'tags': List<String>.from(tags),
      if (sanitizedSocials != null && sanitizedSocials.isNotEmpty)
        'socials': sanitizedSocials,
    };
  }

  @override
  List<Object?> get props => <Object?>[
        eventId,
        title,
        imageUrl,
        description,
        startAt,
        endAt,
        locationTown,
        locationName,
        address,
        hostUserId,
        hostUsername,
        hostDisplayName,
        attendeeCount,
        isAttending,
        isFree,
        costAmount,
        socials,
        tags,
      ];

  static Map<String, String?>? _readSocials(dynamic raw) {
    if (raw is! Map) {
      return null;
    }
    final normalized = <String, String?>{};
    raw.forEach((key, value) {
      if (key is! String) {
        return;
      }
      final trimmedKey = key.trim();
      if (trimmedKey.isEmpty) {
        return;
      }
      final trimmedValue = value == null ? null : value.toString().trim();
      if (trimmedValue == null || trimmedValue.isEmpty) {
        return;
      }
      normalized[trimmedKey] = trimmedValue;
    });
    if (normalized.isEmpty) {
      return null;
    }
    return Map<String, String?>.unmodifiable(normalized);
  }
}
