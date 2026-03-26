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

## Required before store submission

### 1) Secrets and runtime backend

- [ ] Create production `.env` values for:
  - `API_BASE_URL`
  - `FMP_API_KEY`
  - `MARKETAUX_API_KEY`
  - `NEWSAPI_KEY`
  - `ALPHAVANTAGE_API_KEY`
- [ ] Deploy the Node proxy (`server/`) to a production host with TLS.
- [ ] Set `API_BASE_URL` in app builds to the production proxy URL.
- [ ] Validate CORS policy in `server/index.js` for production origin restrictions.

### 2) Android release signing

- [ ] Generate a production upload keystore.
- [ ] Copy `android/key.properties.example` to `android/key.properties` and fill values.
- [ ] Ensure `storeFile` path points to a keystore file that is not committed.
- [ ] Build and verify:
  - `flutter build appbundle --release`
  - `flutter build apk --release` (optional)

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

## Suggested pre-submit command set

From project root:

```bash
flutter pub get
flutter analyze
flutter test
flutter build appbundle --release
flutter build ios --release
```

From `server/`:

```bash
npm install
node --check index.js
```
