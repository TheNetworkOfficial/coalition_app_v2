import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../providers/app_providers.dart';
import '../../../services/auth_service.dart';
import '../providers/auth_state.dart';

class AuthGatePage extends ConsumerStatefulWidget {
  const AuthGatePage({super.key});

  @override
  ConsumerState<AuthGatePage> createState() => _AuthGatePageState();
}

class _AuthGatePageState extends ConsumerState<AuthGatePage>
    with SingleTickerProviderStateMixin {
  final _signInFormKey = GlobalKey<FormState>();
  final _signUpFormKey = GlobalKey<FormState>();

  late final TabController _tabController;
  ProviderSubscription<AuthState>? _authSubscription;

  final TextEditingController _signInUsernameController =
      TextEditingController();
  final TextEditingController _signInPasswordController =
      TextEditingController();

  final TextEditingController _signUpUsernameController =
      TextEditingController();
  final TextEditingController _signUpEmailController = TextEditingController();
  final TextEditingController _signUpPasswordController =
      TextEditingController();

  bool _obscureSignInPassword = true;
  bool _obscureSignUpPassword = true;
  bool _isPresentingConfirmation = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _authSubscription = ref.listenManual<AuthState>(
      authStateProvider,
      (previous, next) {
        if (next.initialized && next.isSignedIn) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              context.go('/feed');
            }
          });
        }
        if (next.awaitingConfirmation != null &&
            previous?.awaitingConfirmation == null) {
          _presentConfirmation(next.awaitingConfirmation!);
        }
        if (next.awaitingConfirmation == null &&
            previous?.awaitingConfirmation != null) {
          _isPresentingConfirmation = false;
        }
      },
      fireImmediately: false,
    );
    final initialState = ref.read(authStateProvider);
    if (initialState.initialized && initialState.isSignedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.go('/feed');
        }
      });
    }
    if (initialState.awaitingConfirmation != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && initialState.awaitingConfirmation != null) {
          _presentConfirmation(initialState.awaitingConfirmation!);
        }
      });
    }
  }

  @override
  void dispose() {
    _authSubscription?.close();
    _tabController.dispose();
    _signInUsernameController.dispose();
    _signInPasswordController.dispose();
    _signUpUsernameController.dispose();
    _signUpEmailController.dispose();
    _signUpPasswordController.dispose();
    super.dispose();
  }

  void _presentConfirmation(AwaitingConfirmationState awaiting) {
    if (_isPresentingConfirmation) {
      return;
    }
    _isPresentingConfirmation = true;
    final messenger = ScaffoldMessenger.of(context);
    final destination = awaiting.deliveryDestination ?? awaiting.email;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'We sent a code to $destination. Enter it to finish signing up.',
          ),
        ),
      );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _isPresentingConfirmation = false;
        return;
      }
      try {
        await context.push('/auth/confirm-code');
      } finally {
        _isPresentingConfirmation = false;
      }
    });
  }

  Widget? _buildStatusBanner(AuthState authState) {
    final awaiting = authState.awaitingConfirmation;
    if (authState.errorCode == 'username-exists') {
      final message = authState.errorMessage ??
          'An account with that username already exists. Try signing in or pick another handle.';
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        color: Colors.orange.shade50,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message,
                style: TextStyle(
                  color: Colors.orange.shade900,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    ref.read(authStateProvider.notifier).clearError();
                    final username = _signUpUsernameController.text.trim();
                    if (username.isNotEmpty) {
                      _signInUsernameController.text = username;
                    }
                    _tabController.animateTo(0);
                  },
                  child: const Text('Go to Sign In'),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (authState.errorMessage != null && awaiting == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          authState.errorMessage!,
          style: const TextStyle(color: Colors.redAccent),
          textAlign: TextAlign.center,
        ),
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final isLoading = authState.isLoading;
    final statusBanner = _buildStatusBanner(authState);

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                const SizedBox(height: 24),
                const Text(
                  'Welcome',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                if (statusBanner != null) ...[
                  statusBanner,
                  const SizedBox(height: 16),
                ],
                TabBar(
                  controller: _tabController,
                  tabs: const [
                    Tab(text: 'Sign In'),
                    Tab(text: 'Create account'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildSignInForm(context, isLoading),
                      _buildSignUpForm(context, isLoading),
                    ],
                  ),
                ),
              ],
            ),
            if (isLoading)
              Container(
                color: Colors.black45,
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignInForm(BuildContext context, bool isLoading) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _signInFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _signInUsernameController,
              decoration: const InputDecoration(
                labelText: 'Username or email',
              ),
              onChanged: (_) =>
                  ref.read(authStateProvider.notifier).clearError(),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter your username or email';
                }
                return null;
              },
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _signInPasswordController,
              decoration: InputDecoration(
                labelText: 'Password',
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureSignInPassword
                        ? Icons.visibility_off
                        : Icons.visibility,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscureSignInPassword = !_obscureSignInPassword;
                    });
                  },
                ),
              ),
              obscureText: _obscureSignInPassword,
              onChanged: (_) =>
                  ref.read(authStateProvider.notifier).clearError(),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your password';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: isLoading ? null : _handleEmailSignIn,
              child: const Text('Sign In'),
            ),
            const SizedBox(height: 16),
            _buildGoogleButton(isLoading),
          ],
        ),
      ),
    );
  }

  Widget _buildSignUpForm(BuildContext context, bool isLoading) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _signUpFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _signUpUsernameController,
              decoration: const InputDecoration(
                labelText: 'Username',
              ),
              onChanged: (_) =>
                  ref.read(authStateProvider.notifier).clearError(),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Username is required';
                }
                try {
                  ref.read(authServiceProvider).normalizeUsername(value);
                } catch (error) {
                  return error.toString();
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _signUpEmailController,
              decoration: const InputDecoration(labelText: 'Email'),
              onChanged: (_) =>
                  ref.read(authStateProvider.notifier).clearError(),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Email is required';
                }
                if (!value.contains('@')) {
                  return 'Enter a valid email';
                }
                return null;
              },
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _signUpPasswordController,
              decoration: InputDecoration(
                labelText: 'Password',
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureSignUpPassword
                        ? Icons.visibility_off
                        : Icons.visibility,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscureSignUpPassword = !_obscureSignUpPassword;
                    });
                  },
                ),
              ),
              obscureText: _obscureSignUpPassword,
              onChanged: (_) =>
                  ref.read(authStateProvider.notifier).clearError(),
              validator: (value) {
                if (value == null || value.length < 8) {
                  return 'Password must be at least 8 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: isLoading ? null : _handleEmailSignUp,
              child: const Text('Create account'),
            ),
            const SizedBox(height: 16),
            _buildGoogleButton(isLoading),
          ],
        ),
      ),
    );
  }

  Widget _buildGoogleButton(bool isLoading) {
    return OutlinedButton.icon(
      onPressed: isLoading ? null : _handleGoogleSignIn,
      icon: const Icon(Icons.login),
      label: const Text('Continue with Google'),
    );
  }

  Future<void> _handleEmailSignIn() async {
    final form = _signInFormKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(authStateProvider.notifier).signInWithEmail(
            usernameOrEmail: _signInUsernameController.text.trim(),
            password: _signInPasswordController.text,
          );
    } catch (error) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Sign-in failed: $error')),
        );
    }
  }

  Future<void> _handleEmailSignUp() async {
    final form = _signUpFormKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(authStateProvider.notifier).signUpWithEmail(
            username: _signUpUsernameController.text.trim(),
            email: _signUpEmailController.text.trim(),
            password: _signUpPasswordController.text,
          );
    } catch (error) {
      if (error is AuthUiException && error.code == 'username-exists') {
        return;
      }
      final message = error is AuthUiException
          ? (error.message ?? 'Sign-up failed. Please try again.')
          : 'Sign-up failed: $error';
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(message)),
        );
    }
  }

  Future<void> _handleGoogleSignIn() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(authStateProvider.notifier).signInWithGoogle();
    } catch (error) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Google sign-in failed: $error')),
        );
    }
  }
}
