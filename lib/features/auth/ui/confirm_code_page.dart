import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../models/profile.dart';
import '../../../providers/app_providers.dart';
import '../../../services/api_client.dart';
import '../../../services/auth_service.dart';
import '../providers/auth_state.dart';

class ConfirmCodePage extends ConsumerStatefulWidget {
  const ConfirmCodePage({super.key});

  @override
  ConsumerState<ConfirmCodePage> createState() => _ConfirmCodePageState();
}

class _ConfirmCodePageState extends ConsumerState<ConfirmCodePage> {
  final TextEditingController _codeController = TextEditingController();
  String? _inputError;
  bool _navigatedAway = false;
  bool _initialProfileSubmitted = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final awaiting = authState.awaitingConfirmation;

    if (awaiting == null && !_navigatedAway) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _navigatedAway = true;
        if (authState.isSignedIn) {
          context.go('/feed');
        } else {
          context.go('/auth');
        }
      });
    }

    final destination =
        awaiting?.deliveryDestination ?? awaiting?.email ?? 'your email';
    final isLoading = authState.isLoading;
    final serverError = awaiting != null ? authState.errorMessage : null;
    final errorText = _inputError ?? serverError;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Confirm your account'),
      ),
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'We sent a code to $destination. Enter it to finish signing up.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _codeController,
                    decoration: InputDecoration(
                      labelText: '6-digit code',
                      errorText: errorText,
                    ),
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    onChanged: (_) {
                      if (_inputError != null) {
                        setState(() {
                          _inputError = null;
                        });
                      }
                      ref.read(authStateProvider.notifier).clearError();
                    },
                    onSubmitted: (_) => _confirmCode(),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: isLoading ? null : _confirmCode,
                    child: const Text('Confirm'),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: isLoading ? null : _handleResend,
                    child: const Text('Resend code'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Username: ${awaiting?.username ?? ''}',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ),
          if (isLoading)
            Container(
              color: Theme.of(context)
                  .colorScheme
                  .scrim
                  .withValues(alpha: 0.45),
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmCode() async {
    FocusScope.of(context).unfocus();
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() {
        _inputError = 'Enter the 6-digit code.';
      });
      return;
    }
    final awaiting = ref.read(authStateProvider).awaitingConfirmation;
    if (awaiting == null) {
      return;
    }
    ref.read(authStateProvider.notifier).clearError();
    try {
      await ref
          .read(authStateProvider.notifier)
          .confirmSignUp(username: awaiting.username, code: code);
      if (!_initialProfileSubmitted) {
        _initialProfileSubmitted = true;
        await _submitInitialProfileUsername(awaiting.username);
      }
    } on AuthUiException catch (error) {
      ref.read(authStateProvider.notifier).clearError();
      setState(() {
        _inputError =
            error.message ?? 'We could not confirm that code. Try again.';
      });
    } on AuthFlowException catch (error) {
      ref.read(authStateProvider.notifier).clearError();
      setState(() {
        _inputError = error.message;
      });
    } catch (error) {
      ref.read(authStateProvider.notifier).clearError();
      final messenger = ScaffoldMessenger.of(context);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Could not confirm code: $error')),
        );
    }
  }

  Future<void> _submitInitialProfileUsername(String username) async {
    final trimmed = username.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      final client = ref.read(apiClientProvider);
      await client.upsertMyProfile(ProfileUpdate(username: trimmed));
    } on ApiException catch (error) {
      final message = error.message.isNotEmpty
          ? error.message
          : 'status ${error.statusCode ?? 'unknown'}';
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Could not finish profile setup: $message'),
          ),
        );
    } catch (error) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Could not finish profile setup: $error'),
          ),
        );
    }
  }

  Future<void> _handleResend() async {
    final awaiting = ref.read(authStateProvider).awaitingConfirmation;
    if (awaiting == null) {
      return;
    }
    ref.read(authStateProvider.notifier).clearError();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(authStateProvider.notifier).resendConfirmationCode();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Code sent')),
        );
    } catch (error) {
      ref.read(authStateProvider.notifier).clearError();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Could not resend code: $error')),
        );
    }
  }
}
