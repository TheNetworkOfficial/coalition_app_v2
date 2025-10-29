// Existing picker/uploader inventory:
// - wechat_assets_picker with LightweightAssetPicker for media selection.
// - UploadService + UploadManager handle post media uploads; reused for avatar pipeline.
// - No dedicated image compression helper located; current flows use source files directly.
import 'package:flutter/material.dart';

import '../../../widgets/user_avatar.dart';

const Map<String, IconData> kCandidateSocialIcons = <String, IconData>{
  'phone': Icons.phone_outlined,
  'email': Icons.email_outlined,
  'facebook': Icons.facebook,
  'instagram': Icons.camera_alt_outlined,
  'tiktok': Icons.music_note,
  'website': Icons.link,
};

String candidateSocialLabel(String key) {
  switch (key.toLowerCase()) {
    case 'phone':
      return 'Phone';
    case 'email':
      return 'Email';
    case 'facebook':
      return 'Facebook';
    case 'instagram':
      return 'Instagram';
    case 'tiktok':
      return 'TikTok';
    case 'website':
      return 'Website';
    default:
      if (key.isEmpty) {
        return '';
      }
      return key[0].toUpperCase() + key.substring(1);
  }
}

Map<String, String> normalizedCandidateSocials(Map<String, String?>? socials) {
  if (socials == null || socials.isEmpty) {
    return const {};
  }
  final result = <String, String>{};
  socials.forEach((key, value) {
    final trimmedKey = key.trim();
    final trimmedValue = value?.trim();
    if (trimmedKey.isNotEmpty &&
        trimmedValue != null &&
        trimmedValue.isNotEmpty) {
      result[trimmedKey] = trimmedValue;
    }
  });
  return result;
}

class CandidateHeaderView extends StatelessWidget {
  const CandidateHeaderView({
    super.key,
    required this.avatarUrl,
    required this.displayName,
    required this.levelOfOffice,
    required this.district,
    this.extraChips = const <Widget>[],
  });

  final String? avatarUrl;
  final String displayName;
  final String? levelOfOffice;
  final String? district;
  final List<Widget> extraChips;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chips = <Widget>[
      if ((levelOfOffice ?? '').trim().isNotEmpty)
        Chip(label: Text(levelOfOffice!.trim())),
      if ((district ?? '').trim().isNotEmpty)
        Chip(label: Text(district!.trim())),
      ...extraChips,
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        UserAvatar(
          url: avatarUrl,
          size: 72,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayName.isNotEmpty
                    ? displayName
                    : 'Unnamed candidate',
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              if (chips.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: chips,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class CandidateBioView extends StatelessWidget {
  const CandidateBioView({
    super.key,
    required this.bio,
  });

  final String? bio;

  @override
  Widget build(BuildContext context) {
    final text = bio?.trim();
    if (text == null || text.isEmpty) {
      return const SizedBox.shrink();
    }

    return Text(
      text,
      style: Theme.of(context).textTheme.bodyLarge,
    );
  }
}

class CandidateTagsView extends StatelessWidget {
  const CandidateTagsView({
    super.key,
    required this.priorityTags,
  });

  final List<String> priorityTags;

  @override
  Widget build(BuildContext context) {
    final tags = priorityTags
        .where((tag) => tag.trim().isNotEmpty)
        .map((tag) => tag.trim())
        .toList(growable: false);
    if (tags.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final tag in tags) Chip(label: Text(tag)),
      ],
    );
  }
}

class CandidateSocialsView extends StatelessWidget {
  const CandidateSocialsView({
    super.key,
    required this.socials,
    this.title,
  });

  final Map<String, String?> socials;
  final Widget? title;

  @override
  Widget build(BuildContext context) {
    final normalized = normalizedCandidateSocials(socials);
    if (normalized.isEmpty) {
      return const SizedBox.shrink();
    }

    final tiles = normalized.entries
        .map(
          (entry) => ListTile(
            leading: Icon(kCandidateSocialIcons[entry.key] ?? Icons.link_outlined),
            title: Text(candidateSocialLabel(entry.key)),
            subtitle: Text(entry.value),
            dense: true,
          ),
        )
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) title!,
        if (title != null) const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          child: Column(children: tiles),
        ),
      ],
    );
  }
}

class CandidateSectionTitle extends StatelessWidget {
  const CandidateSectionTitle({
    super.key,
    required this.text,
  });

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium,
    );
  }
}
