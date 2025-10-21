import 'dart:async';

import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:flutter/foundation.dart';

import '../amplifyconfiguration.dart';
import '../env.dart';
import '../features/auth/models/user_summary.dart';
import 'session_manager.dart';

class AuthFlowException implements Exception {
  AuthFlowException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

class AuthUiException implements Exception {
  AuthUiException(this.code, {this.message, this.cause});

  final String code;
  final String? message;
  final Object? cause;

  @override
  String toString() => message ?? code;
}

class SignUpFlowResult {
  SignUpFlowResult({
    required this.isComplete,
    required this.nextStep,
    required this.username,
    this.deliveryDestination,
  });

  final bool isComplete;
  final String nextStep; // 'none' | 'confirmCode'
  final String? deliveryDestination;
  final String username;
}

class AuthService {
  AuthService({SessionManager? sessionManager})
      : _sessionManager = sessionManager ?? SessionManager();

  final SessionManager _sessionManager;

  bool _pluginsAdded = false;
  Future<void>? _configureOperation;

  static final RegExp _usernameRegExp = RegExp(r'^[a-z0-9_]{3,20}$');

  Future<void> configureIfNeeded() async {
    if (kAuthBypassEnabled) {
      return;
    }

    if (Amplify.isConfigured) {
      return;
    }

    if (_configureOperation != null) {
      await _configureOperation;
      return;
    }

    final completer = Completer<void>();
    _configureOperation = completer.future;

    try {
      await _addPluginIfNeeded();
      if (!Amplify.isConfigured) {
        await Amplify.configure(amplifyconfig);
      }
      completer.complete();
    } on AmplifyAlreadyConfiguredException {
      debugPrint('[AuthService] Amplify already configured; continuing');
      completer.complete();
    } catch (error, stackTrace) {
      debugPrint('[AuthService] configure failed: $error\n$stackTrace');
      completer.completeError(error, stackTrace);
      rethrow;
    } finally {
      _configureOperation = null;
    }
  }

  Future<void> _addPluginIfNeeded() async {
    if (_pluginsAdded) {
      return;
    }
    try {
      Amplify.addPlugin(AmplifyAuthCognito());
      _pluginsAdded = true;
    } on AmplifyAlreadyConfiguredException {
      debugPrint('[AuthService] Auth plugin already added; continuing');
      _pluginsAdded = true;
    } on Exception catch (error, stackTrace) {
      debugPrint('[AuthService] addPlugin failed: $error\n$stackTrace');
      rethrow;
    }
  }

  String normalizeUsername(String username) {
    final normalized = username.trim().toLowerCase();
    if (!_usernameRegExp.hasMatch(normalized)) {
      throw AuthFlowException(
        'Username must be 3-20 characters using lowercase letters, numbers, or underscores.',
      );
    }
    return normalized;
  }

  Future<bool> isSignedIn() async {
    if (kAuthBypassEnabled) {
      final marker = await _sessionManager.readSessionMarker();
      return marker != null && marker.isNotEmpty;
    }
    await configureIfNeeded();
    try {
      final session = await Amplify.Auth.fetchAuthSession();
      return session.isSignedIn;
    } on SignedOutException {
      return false;
    } on AuthException catch (error, stackTrace) {
      debugPrint('[AuthService] fetchAuthSession failed: $error\n$stackTrace');
      throw _mapAuthException(error);
    }
  }

  Future<UserSummary?> currentUser() async {
    if (kAuthBypassEnabled) {
      final marker = await _sessionManager.readSessionMarker();
      if (marker == null || marker.isEmpty) {
        return null;
      }
      return UserSummary(userId: marker, username: marker, displayName: 'Developer');
    }

    await configureIfNeeded();
    try {
      final user = await Amplify.Auth.getCurrentUser();
      final attributes = await Amplify.Auth.fetchUserAttributes();
      String? username;
      String? displayName;
      for (final attribute in attributes) {
        switch (attribute.userAttributeKey.key) {
          case 'preferred_username':
          case 'nickname':
            username ??= attribute.value;
            break;
          case 'name':
          case 'given_name':
            displayName ??= attribute.value;
            break;
        }
      }
      username ??= user.username;
      return UserSummary(
        userId: user.userId,
        username: username,
        displayName: displayName,
      );
    } on AuthException catch (error, stackTrace) {
      debugPrint('[AuthService] currentUser failed: $error\n$stackTrace');
      throw _mapAuthException(error);
    }
  }

  Future<void> signInWithGoogle() async {
    if (kAuthBypassEnabled) {
      await _sessionManager.persistSessionMarker('u1');
      return;
    }

    await configureIfNeeded();
    try {
      await Amplify.Auth.signInWithWebUI(provider: AuthProvider.google);
    } on AuthException catch (error, stackTrace) {
      debugPrint('[AuthService] Google sign-in failed: $error\n$stackTrace');
      throw _mapAuthException(error);
    } catch (error, stackTrace) {
      debugPrint('[AuthService] Google sign-in unexpected error: $error\n$stackTrace');
      throw AuthFlowException(
        'Google sign-in failed. Please try again in a moment.',
        cause: error,
      );
    }
    await _persistSessionMarkerFromUser();
  }

  Future<SignUpFlowResult> signUpEmail({
    required String username,
    required String email,
    required String password,
  }) async {
    final normalizedUsername = normalizeUsername(username);

    if (kAuthBypassEnabled) {
      await _sessionManager.persistSessionMarker(normalizedUsername);
      return SignUpFlowResult(
        isComplete: true,
        nextStep: 'none',
        username: normalizedUsername,
      );
    }

    await configureIfNeeded();
    try {
      final options = SignUpOptions(
        userAttributes: {
          AuthUserAttributeKey.email: email,
          AuthUserAttributeKey.preferredUsername: normalizedUsername,
        },
      );
      final result = await Amplify.Auth.signUp(
        username: normalizedUsername,
        password: password,
        options: options,
      );
      if (result.isSignUpComplete) {
        return SignUpFlowResult(
          isComplete: true,
          nextStep: 'none',
          username: normalizedUsername,
        );
      }
      if (result.nextStep.signUpStep == AuthSignUpStep.confirmSignUp) {
        final destination = result.nextStep.codeDeliveryDetails?.destination;
        return SignUpFlowResult(
          isComplete: false,
          nextStep: 'confirmCode',
          username: normalizedUsername,
          deliveryDestination: destination,
        );
      }
      final fallbackDestination = result.nextStep.codeDeliveryDetails?.destination;
      return SignUpFlowResult(
        isComplete: result.isSignUpComplete,
        nextStep: 'none',
        username: normalizedUsername,
        deliveryDestination: fallbackDestination,
      );
    } on UsernameExistsException catch (error, stackTrace) {
      debugPrint('[AuthService] signUpEmail failed: $error\n$stackTrace');
      throw AuthUiException(
        'username-exists',
        message:
            'An account with that username already exists. Try signing in or pick another handle.',
        cause: error,
      );
    } on InvalidPasswordException catch (error, stackTrace) {
      debugPrint('[AuthService] signUpEmail failed: $error\n$stackTrace');
      throw AuthUiException(
        'invalid-password',
        message:
            'Password does not meet policy requirements. Create a stronger password and try again.',
        cause: error,
      );
    } on InvalidParameterException catch (error, stackTrace) {
      debugPrint('[AuthService] signUpEmail failed: $error\n$stackTrace');
      throw AuthUiException(
        'invalid-parameter',
        message:
            'We could not process that sign-up request. Double-check your details and try again.',
        cause: error,
      );
    } on CodeDeliveryFailureException catch (error, stackTrace) {
      debugPrint('[AuthService] signUpEmail failed: $error\n$stackTrace');
      throw AuthUiException(
        'code-delivery-failed',
        message:
            'We could not send a verification code right now. Wait a moment and try again.',
        cause: error,
      );
    } on AuthException catch (error, stackTrace) {
      debugPrint('[AuthService] signUpEmail failed: $error\n$stackTrace');
      throw _mapAuthException(error);
    }
  }

  Future<void> signInEmail({
    required String usernameOrEmail,
    required String password,
  }) async {
    if (kAuthBypassEnabled) {
      await _sessionManager.persistSessionMarker(usernameOrEmail);
      return;
    }

    await configureIfNeeded();
    final identifier = usernameOrEmail.contains('@')
        ? usernameOrEmail.trim()
        : normalizeUsername(usernameOrEmail);
    try {
      final result = await Amplify.Auth.signIn(
        username: identifier,
        password: password,
      );
      if (!result.isSignedIn) {
        throw AuthFlowException('Sign-in not completed. Please follow the next steps.');
      }
    } on AuthException catch (error, stackTrace) {
      debugPrint('[AuthService] signInEmail failed: $error\n$stackTrace');
      throw _mapAuthException(error);
    }
    await _persistSessionMarkerFromUser();
  }

  Future<void> confirmSignUp({
    required String username,
    required String code,
  }) async {
    if (kAuthBypassEnabled) {
      await _sessionManager.persistSessionMarker(username);
      return;
    }

    await configureIfNeeded();
    final normalizedUsername = normalizeUsername(username);
    try {
      await Amplify.Auth.confirmSignUp(
        username: normalizedUsername,
        confirmationCode: code.trim(),
      );
    } on AuthException catch (error, stackTrace) {
      debugPrint('[AuthService] confirmSignUp failed: $error\n$stackTrace');
      throw _mapAuthException(error);
    }
  }

  Future<void> resendSignUpCode({required String username}) async {
    if (kAuthBypassEnabled) {
      return;
    }

    await configureIfNeeded();
    final normalizedUsername = normalizeUsername(username);
    try {
      await Amplify.Auth.resendSignUpCode(username: normalizedUsername);
    } on AuthException catch (error, stackTrace) {
      debugPrint('[AuthService] resendSignUpCode failed: $error\n$stackTrace');
      throw _mapAuthException(error);
    }
  }

  Future<void> signOut() async {
    if (kAuthBypassEnabled) {
      await _sessionManager.clearSessionMarker();
      return;
    }

    await configureIfNeeded();
    try {
      await Amplify.Auth.signOut(
        options: const SignOutOptions(globalSignOut: true),
      );
    } on AuthException catch (error, stackTrace) {
      debugPrint('[AuthService] signOut failed: $error\n$stackTrace');
      throw _mapAuthException(error);
    }
    await _sessionManager.clearSessionMarker();
  }

  Future<String?> fetchAuthToken({bool forceRefresh = false}) async {
    if (kAuthBypassEnabled) {
      return null;
    }
    await configureIfNeeded();
    try {
      if (forceRefresh) {
        return await _tryFetchIdToken(forceRefresh: true);
      }
      final token = await _tryFetchIdToken(forceRefresh: false);
      if (token != null) {
        return token;
      }
      return await _tryFetchIdToken(forceRefresh: true);
    } on AuthException catch (error, stackTrace) {
      debugPrint('[AuthService] fetchAuthToken failed: $error\n$stackTrace');
    }
    return null;
  }

  Future<String?> _tryFetchIdToken({required bool forceRefresh}) async {
    final session = await Amplify.Auth.fetchAuthSession(
      options: FetchAuthSessionOptions(forceRefresh: forceRefresh),
    );
    if (session is CognitoAuthSession) {
      final tokens = session.userPoolTokensResult.valueOrNull;
      if (tokens != null) {
        return tokens.idToken.raw;
      }
    }
    return null;
  }

  Future<void> _persistSessionMarkerFromUser() async {
    final summary = await currentUser();
    final marker = summary?.userId ?? summary?.username;
    if (marker != null && marker.isNotEmpty) {
      await _sessionManager.persistSessionMarker(marker);
    }
  }

  AuthFlowException _mapAuthException(AuthException error) {
    if (error is UsernameExistsException) {
      return AuthFlowException(
        'An account with that username already exists. Try signing in or pick another handle.',
        cause: error,
      );
    }
    if (error is AuthNotAuthorizedException || error is InvalidPasswordException) {
      return AuthFlowException(
        'Incorrect username or password. Please try again.',
        cause: error,
      );
    }
    if (error is UserNotFoundException) {
      return AuthFlowException(
        'We couldn\'t find an account with those details. Check the spelling or sign up.',
        cause: error,
      );
    }
    if (error is CodeMismatchException || error is ExpiredCodeException) {
      return AuthFlowException(
        'The verification code is incorrect or expired. Request a new code and try again.',
        cause: error,
      );
    }
    if (error.message.toLowerCase().contains('not configured')) {
      return AuthFlowException(
        'Auth not configured. Rebuild after running amplify pull.',
        cause: error,
      );
    }
    if (error is NetworkException ||
        error.recoverySuggestion?.toLowerCase().contains('network') == true) {
      return AuthFlowException(
        'We hit a network issue. Check your connection and try again.',
        cause: error,
      );
    }
    return AuthFlowException(error.message, cause: error);
  }
}
