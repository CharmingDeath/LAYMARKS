# LAYMARKS Monetization Model (App Store + Play Store)

This document defines the production payment model for LAYMARKS and the required implementation/compliance items to launch paid subscriptions.

## Recommended model

Use a **freemium subscription model** with two auto-renewing plans:

- `laymarks_premium_monthly`
- `laymarks_premium_yearly` (position as best value)

Rationale:

- Fits ongoing data/API costs and server spend.
- Aligns with market-intelligence usage (recurring value, not one-off).
- Standard user expectation on iOS/Android stores.

## Feature packaging

### Free tier (acquisition)

- Dashboard core quote cards
- Limited market news (first batch only)
- Limited company listings preview
- Limited company news feed preview
- Upgrade prompts and paywall access

### Premium tier (conversion/retention)

- Unlimited market news feed
- Unlimited company listings and detail dialogs
- Sector peers + deeper company financial snapshots
- Earnings calendar and economic calendar intelligence
- Unlimited company news feed

## Pricing guidance

Start with two plans:

- Monthly: low-friction entry plan.
- Yearly: discounted effective monthly rate (target ~25-40% off annualized monthly).

Use local currency pricing in App Store Connect and Play Console and run price experiments over time.

## Required technical components

## 1) Client purchase flow

Implemented in app:

- In-app billing integration via `in_app_purchase`
- Product query + paywall UI
- Purchase and restore flows
- Local entitlement cache via `shared_preferences`
- Premium feature gating in key screens

## 2) Store products and setup

Required in both stores:

- Create matching product IDs:
  - `laymarks_premium_monthly`
  - `laymarks_premium_yearly`
- Localized descriptions, pricing, and screenshots
- Subscription groups (iOS) and base plans/offers (Play)

## 3) Entitlement security (required for production)

Current app includes local entitlement persistence for UX continuity.
For production-grade fraud resistance, add server-side receipt verification:

- App Store Server API verification
- Google Play Developer API purchase validation
- Backend entitlement record with expiry and renewal status
- Periodic entitlement refresh in app

Without receipt validation, users may bypass premium checks on compromised devices.

## 4) Policy and legal requirements

Required before submission:

- Clear auto-renew terms in paywall and store metadata
- Privacy policy including purchase data handling
- Terms of service (billing/refund/cancel language)
- Restore purchases flow (already implemented in app)

## 5) Analytics events to add

Track conversion funnel:

- `paywall_viewed`
- `plan_selected`
- `purchase_started`
- `purchase_success`
- `purchase_failed`
- `restore_started`
- `restore_success`
- `premium_feature_blocked`

## 6) Conversion optimization plan

- Place upgrade CTA on high-intent surfaces (already added to primary screens).
- A/B test paywall copy and yearly discount framing.
- Trigger upsell after repeated premium-feature interactions.

## Launch checklist

- [ ] Product IDs created in App Store Connect and Play Console
- [ ] Subscription metadata, prices, and review notes completed
- [ ] Server-side receipt validation implemented
- [ ] End-to-end test purchases on iOS sandbox + Play internal testing
- [ ] Restore flow tested on both platforms
- [ ] Free-to-paid gating verified on all premium surfaces
- [ ] Privacy policy + terms URLs ready for store listings
