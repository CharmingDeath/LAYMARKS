# Changelog

All notable changes to this project are documented in this file.

The format is based on Keep a Changelog and this project follows semantic versioning.

## [Unreleased]

### Added

- Release management scaffolding:
  - issue templates
  - pull request template
  - v0.1.1 release prep checklist
  - app store and play store readiness guide

## [0.1.0] - 2026-03-24

### Added

- Full routed Flutter app shell:
  - splash
  - dashboard
  - news
  - companies
  - saved/watchlist feed
- API-backed data flow integration via `ApiService`.
- Shared component library for reusable UI primitives.
- Node.js proxy endpoint expansion for market/news/search/listings/financial data.
- Setup and onboarding documentation improvements.
- `.env.example` to safely onboard contributors without exposing secrets.

### Changed

- Refactored app structure to separate navigation, models, and reusable widgets.
- Improved resilience with provider fallback logic in backend proxy routes.

### Fixed

- Duplicate artifact cleanup in project tree.
- Test stability around splash transition timing.

[Unreleased]: https://github.com/CharmingDeath/LAYMARKS/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/CharmingDeath/LAYMARKS/releases/tag/v0.1.0
