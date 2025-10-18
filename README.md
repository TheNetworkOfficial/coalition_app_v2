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

## Proxy workflow

- When a video is picked, the editor plays the original file immediately (muted looping) so the user gets instant feedback while a background proxy transcode starts.
- A single low-resolution proxy is generated in the background via `VideoProxyService.createJob`; once ready the editor swaps to that proxy and all trimming/scrubbing happens against the lightweight file.
- Timeline state is preserved so trim sliders continue to map to source timecodes, and any fallback proxy encodes (e.g. 360p) still upgrade the session once they complete.
