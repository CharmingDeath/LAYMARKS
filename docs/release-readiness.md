# LAYMARKS Release Readiness (App Store + Play Store)

This checklist tracks what is required to ship a production build of LAYMARKS.

## Completed in-repo hardening

- [x] Android package namespace/application id set to `com.laymarks.app`
- [x] Android release signing config supports production keystore via `android/key.properties`
- [x] iOS bundle identifiers updated to `com.laymarks.app` (app) and `com.laymarks.app.RunnerTests` (tests)
- [x] App display name standardized to `LAYMARKS` across Android/iOS/web
- [x] Widget test no longer hard-fails when `.env` is absent
- [x] Server cache bounded to prevent unbounded memory growth
- [x] Proxy-backed financials/peers/economic/earnings APIs wired to Flutter app
- [x] Proxy hardening: auth token support, CORS allowlist, rate limiting, upstream timeouts
- [x] Flutter requests hardened with shared timeout + proxy auth header support
- [x] `.env` asset removed from app bundle to avoid shipping secrets in release binaries

## Required before store submission

### 1) Secrets and runtime backend

- [ ] Configure production server env values for:
  - `FMP_API_KEY`
  - `MARKETAUX_API_KEY`
  - `NEWSAPI_KEY`
  - `ALPHAVANTAGE_API_KEY`
  - `PROXY_CLIENT_TOKEN`
  - `CORS_ORIGINS`
  - `TRUST_PROXY` (set to `1` behind reverse proxy/LB)
  - `UPSTREAM_TIMEOUT_MS`
  - `RATE_LIMIT_PER_MINUTE`
  - `RATE_LIMIT_EXPENSIVE_PER_MINUTE`
- [ ] Deploy the Node proxy (`server/`) to a production host with TLS.
- [ ] Set app build-time values (via `--dart-define` or `--dart-define-from-file`):
  - `API_BASE_URL`
  - `PROXY_CLIENT_TOKEN`
  - (optional) direct-provider keys if not using proxy-only mode
- [ ] Validate production CORS allowlist behavior for web clients.

### 1.5) Monetization setup (required for revenue)

- [ ] Create paid subscriptions in App Store Connect and Google Play Console:
  - `laymarks_premium_monthly`
  - `laymarks_premium_yearly`
- [ ] Add localizations, pricing tiers, and trial/intro offer strategy.
- [ ] Add app metadata and screenshots that clearly describe premium benefits.
- [ ] Verify purchase, restore, cancellation, and renewal flows on both stores.
- [ ] Ensure legal links are available in-app and store listing:
  - Privacy Policy
  - Terms of Use / Subscription Terms
- [ ] Complete server-side receipt validation endpoint for anti-fraud (recommended before scale).
- [ ] Review and apply `docs/monetization-model.md`.

### 2) Android release signing

- [ ] Generate a production upload keystore.
- [ ] Copy `android/key.properties.example` to `android/key.properties` and fill values.
- [ ] Ensure `storeFile` path points to a keystore file that is not committed.
- [ ] Build and verify:
  - `flutter build appbundle --release`
  - `flutter build apk --release` (optional)
  - (Expected) build fails early if `android/key.properties` is missing.

### 3) iOS signing + capabilities

- [ ] Configure Apple Developer Team in Xcode for `Runner` target.
- [ ] Ensure `com.laymarks.app` App ID exists in Apple Developer portal.
- [ ] Configure signing certificates/profiles for Release.
- [ ] Build and verify:
  - `flutter build ios --release`
  - Archive + Validate in Xcode Organizer.

### 4) Privacy and compliance

- [ ] Write and host a public privacy policy URL (required by both stores).
- [ ] Complete App Store privacy nutrition labels (data collection usage).
- [ ] Complete Play Store Data Safety form.
- [ ] Confirm third-party API provider terms allow commercial mobile redistribution.

### 5) Product metadata and assets

- [ ] Final app icon set (Android adaptive + iOS app icons).
- [ ] Splash/launch branding review.
- [ ] Store screenshots for required form factors.
- [ ] App descriptions, keywords, support URL, marketing URL.

### 6) Quality gates

- [ ] Run `flutter analyze` with zero actionable issues.
- [ ] Run `flutter test`.
- [ ] Manual smoke test on real iOS and Android devices.
- [ ] Confirm startup behavior when `.env` missing/invalid.
- [ ] Verify all key screens load using production `API_BASE_URL`.
- [ ] Verify proxy auth enforcement by calling API without/with `Authorization: Bearer <token>`.
- [ ] Verify proxy rate limits trigger correctly under load tests.

## Suggested pre-submit command set

From project root:

```bash
flutter pub get
flutter analyze
flutter test
flutter build appbundle --release \
  --dart-define=API_BASE_URL=https://api.example.com \
  --dart-define=PROXY_CLIENT_TOKEN=replace_me
flutter build ios --release \
  --dart-define=API_BASE_URL=https://api.example.com \
  --dart-define=PROXY_CLIENT_TOKEN=replace_me
```

From `server/`:

```bash
npm install
node --check index.js
```
