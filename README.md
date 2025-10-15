# coalition_app_v2

## Amplify Auth Wiring

- `lib/services/auth_service.dart`, `lib/features/auth/providers/auth_state.dart`, and `lib/features/auth/ui/auth_gate_page.dart` now configure Amplify once, normalize usernames, surface friendlier errors, and wire Hosted UI Google sign-in.
- Startup continues through `lib/pages/bootstrap_page.dart`, which waits for `AuthService.configureIfNeeded()` / `isSignedIn()` before routing.
- Mobile deep links are enabled via `android/app/src/main/AndroidManifest.xml` and `ios/Runner/Info.plist` for the `myapp://auth/` callback.
- Removed the legacy `google_sign_in` plugin dependency; run `flutter pub get`.

### Verify

- Android deep link: `adb shell am start -a android.intent.action.VIEW -d "myapp://auth/"`.
- iOS deep link: open `myapp://auth/` in Safari on simulator.
- Launch app twice: Amplify config logs once; second launch should bypass Auth when still signed in.
- Username validation: `Abc`, `ab`, and `ab!c` rejected; `valid_name_123` accepted.
- Email sign-up/sign-in: succeeds (confirmation message shown if pool requires it) and routes to the main feed.
- Google sign-in: Hosted UI returns via `myapp://auth/` and completes authentication.
- After sign-in, force quit and relaunch; user stays authenticated.

## Video proxy feature flags

- Segmented preview proxying is enabled by default. `CreateEntryPage` forwards the `VideoProxyRequest` directly to `EditMediaPage`, which starts the proxy job, streams early segments through `ProxyPlaylistController`, and enables progressive playback while the full proxy finalizes.
- To force the legacy proxy flow, pass `--dart-define=ENABLE_SEGMENTED_PREVIEW=false`. In that mode, `CreateEntryPage` waits for a full `VideoProxyResult`, `EditMediaPage` initializes the traditional `VideoEditorController`, and fallbacks rely on `_prepareVideoProxy` dialogs to request smaller proxies when needed.
