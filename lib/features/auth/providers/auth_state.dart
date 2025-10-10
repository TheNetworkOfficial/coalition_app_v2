import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user_summary.dart';
import '../../../providers/app_providers.dart';
import '../../../services/auth_service.dart';

class AuthState {
  const AuthState({
    required this.isLoading,
    required this.initialized,
    required this.isSignedIn,
    this.user,
    this.errorMessage,
  });

  const AuthState.loading()
      : isLoading = true,
        initialized = false,
        isSignedIn = false,
        user = null,
        errorMessage = null;

  final bool isLoading;
  final bool initialized;
  final bool isSignedIn;
  final UserSummary? user;
  final String? errorMessage;

  AuthState copyWith({
    bool? isLoading,
    bool? initialized,
    bool? isSignedIn,
    UserSummary? user,
    String? errorMessage,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      initialized: initialized ?? this.initialized,
      isSignedIn: isSignedIn ?? this.isSignedIn,
      user: user ?? this.user,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class AuthController extends StateNotifier<AuthState> {
  AuthController({required AuthService authService})
      : _authService = authService,
        super(const AuthState.loading());

  final AuthService _authService;

  bool _bootstrapped = false;

  Future<void> bootstrap() async {
    if (_bootstrapped) {
      return;
    }
    _bootstrapped = true;
    state = state.copyWith(isLoading: true, initialized: false);
    try {
      final signedIn = await _authService.isSignedIn();
      UserSummary? user;
      if (signedIn) {
        user = await _authService.currentUser();
      }
      state = AuthState(
        isLoading: false,
        initialized: true,
        isSignedIn: signedIn,
        user: user,
      );
    } catch (error) {
      state = AuthState(
        isLoading: false,
        initialized: true,
        isSignedIn: false,
        errorMessage: error.toString(),
      );
    }
  }

  Future<void> refreshUser() async {
    try {
      final user = await _authService.currentUser();
      state = state.copyWith(user: user, isSignedIn: user != null);
    } catch (error) {
      state = state.copyWith(user: null, isSignedIn: false);
    }
  }

  Future<void> signInWithEmail({
    required String usernameOrEmail,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await _authService.signInEmail(
        usernameOrEmail: usernameOrEmail,
        password: password,
      );
      final user = await _authService.currentUser();
      state = AuthState(
        isLoading: false,
        initialized: true,
        isSignedIn: true,
        user: user,
      );
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        initialized: true,
        isSignedIn: false,
        errorMessage: error.toString(),
      );
      rethrow;
    }
  }

  Future<void> signUpWithEmail({
    required String username,
    required String displayName,
    required String email,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await _authService.signUpEmail(
        username: username,
        displayName: displayName,
        email: email,
        password: password,
      );
      await signInWithEmail(usernameOrEmail: username, password: password);
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        initialized: true,
        isSignedIn: false,
        errorMessage: error.toString(),
      );
      rethrow;
    }
  }

  Future<void> signInWithGoogle() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await _authService.signInWithGoogle();
      final user = await _authService.currentUser();
      state = AuthState(
        isLoading: false,
        initialized: true,
        isSignedIn: true,
        user: user,
      );
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        initialized: true,
        isSignedIn: false,
        errorMessage: error.toString(),
      );
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _authService.signOut();
    state = AuthState(
      isLoading: false,
      initialized: true,
      isSignedIn: false,
    );
  }
}

final authStateProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  final authService = ref.watch(authServiceProvider);
  final controller = AuthController(authService: authService);
  controller.bootstrap();
  return controller;
});
