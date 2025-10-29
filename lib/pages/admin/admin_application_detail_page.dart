import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/models/admin_application.dart';
import '../../features/admin/providers/admin_providers.dart';

class AdminApplicationDetailPage extends ConsumerStatefulWidget {
  const AdminApplicationDetailPage({
    super.key,
    required this.applicationId,
  });

  final String applicationId;

  @override
  ConsumerState<AdminApplicationDetailPage> createState() =>
      _AdminApplicationDetailPageState();
}

class _AdminApplicationDetailPageState
    extends ConsumerState<AdminApplicationDetailPage> {
  bool _isSubmitting = false;

  @override
  Widget build(BuildContext context) {
    final applicationAsync =
        ref.watch(applicationDetailProvider(widget.applicationId));

    return applicationAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => _AdminApplicationDetailError(
        error: error,
        onRetry: () async {
          ref.invalidate(applicationDetailProvider(widget.applicationId));
        },
      ),
      data: (application) => _AdminApplicationDetailView(
        application: application,
        isSubmitting: _isSubmitting,
        onApprove: () => _handleModeration(
          context: context,
          application: application,
          approve: true,
        ),
        onReject: () => _handleModeration(
          context: context,
          application: application,
          approve: false,
        ),
      ),
    );
  }

  Future<void> _handleModeration({
    required BuildContext context,
    required AdminApplication application,
    required bool approve,
  }) async {
    if (_isSubmitting) {
      return;
    }
    setState(() => _isSubmitting = true);
    final repository = ref.read(adminRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (approve) {
        await repository.approve(application.id);
      } else {
        await repository.reject(application.id);
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              approve
                  ? 'Application approved successfully.'
                  : 'Application rejected.',
            ),
          ),
        );
      ref.invalidate(pendingApplicationsProvider);
      ref.invalidate(applicationDetailProvider(application.id));
      if (mounted) {
        context.pop();
      }
    } catch (error) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Moderation failed: $error')),
        );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }
}

class _AdminApplicationDetailView extends StatelessWidget {
  const _AdminApplicationDetailView({
    required this.application,
    required this.isSubmitting,
    required this.onApprove,
    required this.onReject,
  });

  final AdminApplication application;
  final bool isSubmitting;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(application.fullName),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Submitted ${application.submittedLabel}',
                style: textTheme.labelMedium,
              ),
              const SizedBox(height: 12),
              Text(
                application.summary ?? 'Review every field before taking action.',
                style: textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final entry in application.details.entries)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _ApplicationField(
                            label: entry.key,
                            value: entry.value,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: isSubmitting ? null : onApprove,
                      icon: const Icon(Icons.check),
                      label: const Text('Approve'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: isSubmitting ? null : onReject,
                      icon: const Icon(Icons.close),
                      label: const Text('Reject'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ApplicationField extends StatelessWidget {
  const _ApplicationField({
    required this.label,
    required this.value,
  });

  final String label;
  final Object? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final resolved = switch (value) {
      null => '—',
      final String text when text.trim().isEmpty => '—',
      final String text => text,
      final Iterable iterable => iterable.map((item) => '$item').join('\n'),
      _ => value.toString(),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: textTheme.labelLarge
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        SelectableText(
          resolved,
          style: textTheme.bodyLarge,
        ),
      ],
    );
  }
}

class _AdminApplicationDetailError extends StatelessWidget {
  const _AdminApplicationDetailError({
    required this.error,
    required this.onRetry,
  });

  final Object error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin dashboard'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Failed to load application: $error',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
