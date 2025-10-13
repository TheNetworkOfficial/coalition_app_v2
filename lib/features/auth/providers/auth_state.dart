import 'package:flutter_riverpod/legacy.dart';

import '../../../providers/app_providers.dart';
import '../../../services/auth_service.dart';
import '../models/user_summary.dart';

class AwaitingConfirmationState {
  const AwaitingConfirmationState({
    required this.username,
    required this.email,
    required this.password,
    this.deliveryDestination,
    this.codeSentAt,
  });

  final String username;
  final String email;
  final String password;
  final String? deliveryDestination;
  final DateTime? codeSentAt;

  AwaitingConfirmationState copyWith({
    String? deliveryDestination,
    DateTime? codeSentAt,
  }) {
    return AwaitingConfirmationState(
      username: username,
      email: email,
      password: password,
      deliveryDestination: deliveryDestination ?? this.deliveryDestination,
      codeSentAt: codeSentAt ?? this.codeSentAt,
    );
  }
}

class AuthState {
  const AuthState({
    required this.isLoading,
    required this.initialized,
    required this.isSignedIn,
    this.user,
    this.errorMessage,
    this.errorCode,
    this.awaitingConfirmation,
  });

  const AuthState.loading()
      : isLoading = true,
        initialized = false,
        isSignedIn = false,
        user = null,
        errorMessage = null,
        errorCode = null,
        awaitingConfirmation = null;

  final bool isLoading;
  final bool initialized;
  final bool isSignedIn;
  final UserSummary? user;
  final String? errorMessage;
  final String? errorCode;
  final AwaitingConfirmationState? awaitingConfirmation;

  AuthState copyWith({
    bool? isLoading,
    bool? initialized,
    bool? isSignedIn,
    UserSummary? user,
    String? errorMessage,
    bool resetErrorMessage = false,
    String? errorCode,
    bool resetErrorCode = false,
    AwaitingConfirmationState? awaitingConfirmation,
    bool resetAwaitingConfirmation = false,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      initialized: initialized ?? this.initialized,
      isSignedIn: isSignedIn ?? this.isSignedIn,
      user: user ?? this.user,
      errorMessage:
          resetErrorMessage ? null : (errorMessage ?? this.errorMessage),
      errorCode: resetErrorCode ? null : (errorCode ?? this.errorCode),
      awaitingConfirmation: resetAwaitingConfirmation
          ? null
          : (awaitingConfirmation ?? this.awaitingConfirmation),
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
      await _authService.configureIfNeeded();
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
    state = state.copyWith(
      isLoading: true,
      resetErrorMessage: true,
      resetErrorCode: true,
      resetAwaitingConfirmation: true,
    );
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
      final errorCode = error is AuthUiException ? error.code : null;
      state = state.copyWith(
        isLoading: false,
        initialized: true,
        isSignedIn: false,
        errorMessage: error.toString(),
        errorCode: errorCode,
        resetErrorCode: errorCode == null,
        resetAwaitingConfirmation: true,
      );
      rethrow;
    }
  }

  Future<void> signUpWithEmail({
    required String username,
    required String email,
    required String password,
  }) async {
    state = state.copyWith(
      isLoading: true,
      resetErrorMessage: true,
      resetErrorCode: true,
      resetAwaitingConfirmation: true,
    );
    try {
      final normalized = _authService.normalizeUsername(username);
      final result = await _authService.signUpEmail(
        username: normalized,
        email: email,
        password: password,
      );
      if (result.isComplete || result.nextStep == 'none') {
        await signInWithEmail(
          usernameOrEmail: normalized,
          password: password,
        );
        return;
      }
      if (result.nextStep == 'confirmCode') {
        state = AuthState(
          isLoading: false,
          initialized: true,
          isSignedIn: false,
          user: null,
          errorMessage: null,
          awaitingConfirmation: AwaitingConfirmationState(
            username: result.username,
            email: email,
            password: password,
            deliveryDestination: result.deliveryDestination,
            codeSentAt: DateTime.now(),
          ),
        );
        return;
      }
      // Fallback: treat other next steps as incomplete but without follow-up.
      state = state.copyWith(
        isLoading: false,
        initialized: true,
        isSignedIn: false,
        errorMessage:
            'Sign-up requires additional steps. Please check your email for instructions.',
        resetErrorCode: true,
      );
    } catch (error) {
      final errorCode = error is AuthUiException ? error.code : null;
      state = state.copyWith(
        isLoading: false,
        initialized: true,
        isSignedIn: false,
        errorMessage: error.toString(),
        errorCode: errorCode,
        resetErrorCode: errorCode == null,
        resetAwaitingConfirmation: true,
      );
      rethrow;
    }
  }

  Future<void> signInWithGoogle() async {
    state = state.copyWith(
      isLoading: true,
      resetErrorMessage: true,
      resetErrorCode: true,
      resetAwaitingConfirmation: true,
    );
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
      final errorCode = error is AuthUiException ? error.code : null;
      state = state.copyWith(
        isLoading: false,
        initialized: true,
        isSignedIn: false,
        errorMessage: error.toString(),
        errorCode: errorCode,
        resetErrorCode: errorCode == null,
        resetAwaitingConfirmation: true,
      );
      rethrow;
    }
  }

  Future<void> signOut() async {
    state = state.copyWith(
      isLoading: true,
      resetErrorMessage: true,
      resetErrorCode: true,
      resetAwaitingConfirmation: true,
    );
    try {
      await _authService.signOut();
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: error.toString(),
        resetErrorCode: true,
        resetAwaitingConfirmation: true,
      );
      return;
    }
    state = AuthState(
      isLoading: false,
      initialized: true,
      isSignedIn: false,
    );
  }

  Future<void> confirmSignUp({
    required String username,
    required String code,
  }) async {
    final awaiting = state.awaitingConfirmation;
    state = state.copyWith(
      isLoading: true,
      resetErrorMessage: true,
      resetErrorCode: true,
    );
    try {
      await _authService.confirmSignUp(username: username, code: code);
      final password = awaiting?.password;
      if (password != null) {
        await _authService.signInEmail(
          usernameOrEmail: username,
          password: password,
        );
        final user = await _authService.currentUser();
        state = AuthState(
          isLoading: false,
          initialized: true,
          isSignedIn: true,
          user: user,
        );
      } else {
        state = state.copyWith(
          isLoading: false,
          initialized: true,
          isSignedIn: false,
          resetErrorMessage: true,
          resetErrorCode: true,
          resetAwaitingConfirmation: true,
        );
      }
    } catch (error) {
      final errorCode = error is AuthUiException ? error.code : null;
      state = state.copyWith(
        isLoading: false,
        initialized: true,
        isSignedIn: false,
        errorMessage: error.toString(),
        errorCode: errorCode,
        resetErrorCode: errorCode == null,
      );
      rethrow;
    }
  }

  Future<void> resendConfirmationCode() async {
    final awaiting = state.awaitingConfirmation;
    if (awaiting == null) {
      return;
    }
    state = state.copyWith(
      isLoading: true,
      resetErrorMessage: true,
      resetErrorCode: true,
    );
    try {
      await _authService.resendSignUpCode(username: awaiting.username);
      state = state.copyWith(
        isLoading: false,
        awaitingConfirmation: awaiting.copyWith(codeSentAt: DateTime.now()),
        resetErrorMessage: true,
        resetErrorCode: true,
      );
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: error.toString(),
        resetErrorCode: true,
      );
      rethrow;
    }
  }

  void clearError() {
    state = state.copyWith(
      resetErrorMessage: true,
      resetErrorCode: true,
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
