import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
  final TextEditingController _signUpDisplayNameController =
      TextEditingController();
  final TextEditingController _signUpEmailController = TextEditingController();
  final TextEditingController _signUpPasswordController =
      TextEditingController();

  bool _obscureSignInPassword = true;
  bool _obscureSignUpPassword = true;

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
  }

  @override
  void dispose() {
    _authSubscription?.close();
    _tabController.dispose();
    _signInUsernameController.dispose();
    _signInPasswordController.dispose();
    _signUpUsernameController.dispose();
    _signUpDisplayNameController.dispose();
    _signUpEmailController.dispose();
    _signUpPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final isLoading = authState.isLoading;

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
              controller: _signUpDisplayNameController,
              decoration: const InputDecoration(
                labelText: 'Display name',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Display name is required';
                }
                return null;
              },
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _signUpUsernameController,
              decoration: const InputDecoration(
                labelText: 'Username',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Username is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _signUpEmailController,
              decoration: const InputDecoration(labelText: 'Email'),
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
            displayName: _signUpDisplayNameController.text.trim(),
            email: _signUpEmailController.text.trim(),
            password: _signUpPasswordController.text,
          );
    } catch (error) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Sign-up failed: $error')),
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
