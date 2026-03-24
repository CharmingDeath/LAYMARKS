# LAYMARKS

LAYMARKS is a Flutter market intelligence app with a Node.js data proxy, delivering real-time quotes, company discovery, and curated financial news in a modern cross-platform dashboard.

## Features

- Real-time market quote cards for tracked symbols
- Business and company-specific news feeds
- Company search with profile and quote details
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

1. Copy example env file:

   ```bash
   cp .env.example .env
   ```

2. Fill values in `.env`:

   - `API_BASE_URL` (for proxy-backed mode, e.g. `http://127.0.0.1:8787`)
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

## Run the Flutter App

From project root:

```bash
flutter pub get
flutter run
```

## Test and Validate

```bash
flutter analyze
flutter test
```

## Security Notes

- Never commit real `.env` secrets
- Keep `.env.example` placeholders only
- Rotate any key immediately if it is exposed

## License

MIT
