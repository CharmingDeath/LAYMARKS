# App Store + Play Store Readiness Guide

This guide lists everything needed to publish LAYMARKS to Apple App Store and Google Play.

## Current Gaps Found In This Repo

- Android package id is still placeholder:
  - `com.example.appmine`
- iOS bundle identifier is still placeholder:
  - `com.example.appmine`
- Android release uses debug signing config.
- App display names still reference `appmine`/`Appmine`.
- No formal privacy policy URL configured for store listing.

These must be fixed before production submission.

## Status After `release/v0.1.1-prep`

- Android package id updated to:
  - `com.charmingdeath.laymarks`
- iOS bundle id updated to:
  - `com.charmingdeath.laymarks`
- App display names updated to `LAYMARKS`.
- Android release signing template added:
  - `android/key.properties.example`

---

## A) Product Identity

## 1) Final identifiers

Decide and lock:

- Android applicationId (example): `com.charmingdeath.laymarks`
- iOS bundle id (example): `com.charmingdeath.laymarks`

Never change these after production launch.

## 2) Branding

- [ ] App name set to `LAYMARKS` on iOS and Android.
- [ ] Launcher icons exported for all required sizes.
- [ ] Optional adaptive icon polish for Android 13+.

## 3) Versioning

- [ ] Bump `pubspec.yaml` version for every release.
- [ ] Confirm build numbers increment monotonically.

---

## B) Android Release (Play Store)

## 1) Signing

- [ ] Generate release keystore.
- [ ] Store credentials securely (never in git).
- [ ] Configure signing for `release` build type.

## 2) Build

- [ ] Run `flutter build appbundle --release`.
- [ ] Verify `.aab` generated successfully.

## 3) Play Console Setup

- [ ] Create app in Play Console.
- [ ] Complete Data safety form.
- [ ] Complete App content declarations.
- [ ] Add Privacy Policy URL.
- [ ] Upload icons, feature graphic, screenshots.
- [ ] Upload AAB to internal testing first.

## 4) Android Due Diligence

- [ ] No sensitive permissions unless required.
- [ ] Min SDK and target SDK meet policy requirements.
- [ ] App opens from cold start under poor network.
- [ ] Crash-free basic flow on at least 2 Android devices.

---

## C) iOS Release (App Store)

## 1) Signing & Capabilities

- [ ] Apple Developer membership active.
- [ ] Unique bundle identifier configured.
- [ ] Signing certificates/profiles valid.
- [ ] Required capabilities configured only when needed.

## 2) Build

- [ ] `flutter build ios --release` works.
- [ ] Archive generated in Xcode.
- [ ] Build uploaded to App Store Connect.

## 3) App Store Connect Setup

- [ ] Create app record and metadata.
- [ ] Add Privacy Policy URL.
- [ ] Complete App Privacy questionnaire.
- [ ] Add screenshots for required device classes.
- [ ] Add support URL and marketing URL (optional but recommended).
- [ ] Submit first to TestFlight.

## 4) iOS Due Diligence

- [ ] App launch and navigation tested on physical iPhone.
- [ ] External links work and do not trap user.
- [ ] No placeholder strings or assets.
- [ ] No crash on offline mode / API timeout.

---

## D) Legal + Compliance

- [ ] Privacy Policy published on public URL.
- [ ] Terms of Service (recommended).
- [ ] Third-party API attribution/license obligations reviewed.
- [ ] Confirm no copyrighted logos/content without rights.

Starter pages created in repo:

- `docs/legal/privacy-policy.md`
- `docs/legal/support.md`

---

## E) Operational Readiness

- [ ] Production API proxy deployed (not localhost).
- [ ] `API_BASE_URL` points to production endpoint in release build.
- [ ] Monitoring/alerting set for backend uptime and error rate.
- [ ] Key rotation procedure documented.

---

## F) Final Submission Checklist

- [ ] All checks in this document complete.
- [ ] Internal beta sign-off done.
- [ ] Store notes/changelog finalized.
- [ ] Release tag created and GitHub release published.

---

## Suggested Next Implementation Tasks

1. Replace placeholder package identifiers.
2. Configure Android release signing and remove debug signing in release.
3. Update app display names and brand assets.
4. Deploy proxy backend and set production `API_BASE_URL`.
5. Prepare store metadata packs (descriptions, keywords, screenshots).

## Command Walkthrough

For an exact Android internal testing sequence, use:

- `docs/store/play-internal-test-walkthrough.md`
