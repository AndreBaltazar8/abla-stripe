# Changelog

## Unreleased

- Added typed Payment Intents, Charges, Invoices, Refunds, Disputes, Balance
  Transactions and Payouts, tested against Stripe's published examples for the
  pinned API version.

## 0.1.0 - 2026-08-12

- Added a version-pinned Stripe API v1 client for `2026-07-29.dahlia`.
- Added bounded HTTPS requests, safe retries, idempotency and structured errors.
- Added opt-in previous-request telemetry and strict request/header validation.
- Added deterministic nested form encoding and a guarded raw request API.
- Added typed Customer, Checkout, Billing Portal, Subscription, Product, Price,
  Event and list projections.
- Added bounded cursor collection.
- Added constant-time webhook verification with replay protection and secret
  rotation.
- Added deterministic and real-socket protocol fixtures.
- Migrated Kilo's server-side Stripe transport and webhook authentication to
  the package.
