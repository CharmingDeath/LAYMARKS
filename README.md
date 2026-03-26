# LAYMARKS

LAYMARKS is a Flutter market intelligence app with a Node.js data proxy, delivering real-time quotes, company discovery, and curated financial news in a modern cross-platform dashboard.

## Features

- Real-time market quote cards for tracked symbols
- Business and company-specific news feeds
- Company search with profile and quote details
- Company financial snapshots and sector peer discovery
- Economic and earnings calendar highlights on dashboard
- Cross-platform Flutter client (macOS, iOS, Android, Linux, Windows, Web)
- Node.js proxy layer for provider fallback and response normalization

## Tech Stack

- Flutter (Dart)
- Node.js + Express
- Financial and news providers via API keys (`FMP`, `Marketaux`, `NewsAPI`, `Alpha Vantage`)

## Prerequisites

- Flutter SDK installed and available on PATH
- Node.js 18+ and npm
- API keys for market/news providers

## Project Structure

- `lib/` Flutter app code
- `server/` Node.js proxy backend
- `test/` Flutter widget tests

## Environment Setup

1. Copy example env file for local development:

   ```bash
   cp .env.example .env
   ```

2. Fill values in `.env`:

   - `API_BASE_URL` (for proxy-backed mode, e.g. `http://127.0.0.1:8787`)
   - `PROXY_CLIENT_TOKEN` (optional in dev, required if proxy auth is enabled)
   - `FMP_API_KEY`
   - `MARKETAUX_API_KEY`
   - `NEWSAPI_KEY`
   - `ALPHAVANTAGE_API_KEY`

## Run the Proxy Server

From project root:

```bash
cd server
npm install
npm start
```

Server runs on:

- `http://0.0.0.0:8787` by default
- Override with env: `HOST` and `PORT`
- Security/runtime knobs:
  - `PROXY_CLIENT_TOKEN` (required bearer token for all non-health endpoints when set)
  - `CORS_ORIGINS` (comma-separated allowlist, e.g. `https://app.example.com,https://admin.example.com`)
  - `UPSTREAM_TIMEOUT_MS` (default `15000`)
  - `RATE_LIMIT_WINDOW_MS` (default `60000`)
  - `RATE_LIMIT_MAX` (default `120`)
  - `RATE_LIMIT_EXPENSIVE_MAX` (default `40`)
  - `TRUST_PROXY` (`1` when behind reverse proxy/load balancer)

## Run the Flutter App

From project root:

```bash
flutter pub get
flutter run
```

### Build-time configuration (recommended for release)

Prefer build-time defines instead of relying on a bundled `.env` file:

```bash
flutter run \
  --dart-define=API_BASE_URL=https://your-proxy.example.com \
  --dart-define=PROXY_CLIENT_TOKEN=your_proxy_token
```

For release builds, inject values in CI/CD with `--dart-define` or `--dart-define-from-file`.

## Test and Validate

```bash
flutter analyze
flutter test
```

## Release Setup (Android + iOS)

### Android signing

1. Copy the template and fill production values:

   ```bash
   cp android/key.properties.example android/key.properties
   ```

2. Ensure `storeFile` points to your local upload keystore path.

3. Build release artifacts:

   ```bash
   flutter build appbundle --release
   flutter build apk --release
   ```

   Note: release builds require `android/key.properties`; build will fail fast if missing.

### iOS bundle identifier and signing

- iOS bundle identifier is set to `com.laymarks.app`
- Configure your Apple Developer Team and release signing in Xcode (`Runner` target)
- Build and archive:

  ```bash
  flutter build ios --release
  ```

See full launch checklist: `docs/release-readiness.md`.
Monetization and pricing blueprint: `docs/monetization-model.md`.

## Security Notes

- Never commit real `.env` secrets
- Keep `.env.example` placeholders only
- Rotate any key immediately if it is exposed

## License

MIT
