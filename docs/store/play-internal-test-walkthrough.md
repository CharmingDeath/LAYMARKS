# Play Internal Test Walkthrough (Command-by-Command)

Follow this exactly to get your first Android internal test live.

## 0) Prerequisites

- Google Play Console app already created.
- Package id is locked to `com.charmingdeath.laymarks`.
- Java (JDK 17+) installed.
- Android SDK installed and configured.

## 1) Configure Android SDK env vars (macOS zsh)

Replace with your SDK path if needed:

```bash
echo 'export ANDROID_HOME=$HOME/Library/Android/sdk' >> ~/.zshrc
echo 'export ANDROID_SDK_ROOT=$ANDROID_HOME' >> ~/.zshrc
echo 'export PATH=$PATH:$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin' >> ~/.zshrc
source ~/.zshrc
```

Verify:

```bash
echo $ANDROID_HOME
flutter doctor -v
```

## 2) Create upload keystore

From repo root:

```bash
cd /Users/apple/Desktop/LAYMARKS
keytool -genkeypair -v -keystore android/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

When prompted, set and save:

- keystore password
- key password
- alias `upload`

## 3) Configure signing file

```bash
cp android/key.properties.example android/key.properties
```

Edit `android/key.properties` with your actual values:

```properties
storePassword=YOUR_STORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=upload
storeFile=upload-keystore.jks
```

## 4) Run release preflight

```bash
./scripts/release_preflight.sh
```

## 5) Build release AAB

```bash
flutter build appbundle --release
```

Output should be:

- `build/app/outputs/bundle/release/app-release.aab`

## 6) Upload to Play Console Internal testing

In Play Console:

1. App -> Testing -> Internal testing
2. Create release
3. Upload `app-release.aab`
4. Add release notes (e.g. "Initial internal testing build")
5. Review and roll out

## 7) Add testers

In internal testing track:

- Add tester emails or a Google Group
- Share opt-in link with testers

## 8) Verify install

- Tester opens opt-in URL
- Accepts invite
- Installs app from Play Store listing
- Confirms app opens and basic flows work

## Common Errors

### "No Android SDK found"

- Set `ANDROID_HOME`/`ANDROID_SDK_ROOT`
- Re-run `flutter doctor -v`

### "Missing android/key.properties"

- Copy from example and fill values:
  - `cp android/key.properties.example android/key.properties`

### "Keystore was tampered with, or password incorrect"

- Password mismatch in `key.properties`
- Recreate keystore if needed
