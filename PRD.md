# Abla Stripe Product Requirements Document

Status: approved implementation contract
Target package: `abla-stripe`
Initial package version: `0.1.0`
Target Stripe API version: `2026-07-29.dahlia`
Primary consumer: Kilo

## 1. Product statement

Abla Stripe is a server-side Stripe API package written in Abla. It should feel
familiar to users of Stripe's official Node.js and PHP SDKs while fitting
Abla's explicit, synchronous service model and bounded runtime.

The package owns the reusable concerns that an application should not
reimplement: authentication headers, form encoding, response and error
decoding, request metadata, safe retries, idempotency, pagination and webhook
signature verification. Applications continue to own prices, entitlement
policy, database transactions and event idempotency.

The first release is not a line-for-line translation of generated Node or PHP
source. It is a clean Abla implementation of the stable behaviours those SDKs
expose. A raw request API provides access to Stripe endpoints not yet covered by
typed services.

## 2. Why this exists

Kilo currently contains a small bespoke Stripe HTTP implementation. That code
can create customers, Checkout Sessions and Customer Portal Sessions and can
verify subscription webhooks, but transport, parsing and signature behaviour
belong in a reusable package.

Other Abla services will need the same foundation. A shared package reduces the
risk of inconsistent webhook validation, unsafe retries, malformed nested form
parameters, missing request IDs and accidental secret exposure.

## 3. Reference behaviour

The design is informed by Stripe's official SDKs and API documentation:

- Node client configuration, per-request options, retries, response metadata,
  webhook helpers and bounded auto-pagination:
  <https://github.com/stripe/stripe-node>
- PHP client/service pattern, configurable retries, custom requests and
  `stripe-mock` testing:
  <https://github.com/stripe/stripe-php>
- Stripe API versioning and the current API version:
  <https://docs.stripe.com/api/versioning>
- Idempotent request semantics:
  <https://docs.stripe.com/api/idempotent_requests>
- Error types and HTTP status behaviour:
  <https://docs.stripe.com/api/errors>
- Webhook raw-body signing and replay protection:
  <https://docs.stripe.com/webhooks/signature>
- Request identifiers:
  <https://docs.stripe.com/api/request_ids>
- Rate limiting and `Stripe-Rate-Limited-Reason`:
  <https://docs.stripe.com/rate-limits>

When this PRD and a language-specific SDK differ, Stripe's protocol
documentation is authoritative. The package must not claim to be an official
Stripe SDK or use Stripe branding in a way that implies endorsement.

## 4. Users and use cases

### Primary users

- Abla server applications selling subscriptions or one-time products.
- Abla webhook endpoints that need to authenticate and parse Stripe events.
- Abla package authors who need a stable Stripe transport and raw-request
  escape hatch.

### Initial use cases

1. Create or retrieve a Stripe Customer for an application account.
2. Create a subscription-mode Checkout Session with an idempotency key.
3. Create a Customer Portal Session.
4. Retrieve and list products, prices, subscriptions and events for checks and
   reconciliation.
5. Cancel or update a subscription using an explicit idempotency key.
6. Verify a webhook against one or more active endpoint secrets using the exact
   raw body, then expose its event envelope and data object.
7. Diagnose failures using structured Stripe error fields and `Request-Id`.
8. Call a new or preview Stripe API v1 endpoint without waiting for a package
   release.

## 5. Principles

- Safe by default: TLS, bounded bodies, redacted credentials, strict webhook
  verification and explicit mutation idempotency.
- Versioned: every normal request sends the package's pinned Stripe API
  version unless the client explicitly selects another version.
- Honest types: stable fields receive typed resource classes; the complete JSON
  response remains available so additive API changes do not destroy data.
- Application-neutral: no Kilo product IDs, URLs, plans or database code.
- Testable without money or live credentials.
- Bounded: retries, response bodies, pagination and parsing always have limits.
- Observable without secrets: return request IDs and retry metadata, never API
  keys or full sensitive request bodies.

## 6. Package shape

The repository follows the existing Abla package family:

```text
abla-stripe/
  abla.toml
  LICENSE
  README.md
  PRD.md
  Makefile
  src/
    stripe.ab
    client.ab
    form.ab
    webhook.ab
    resources.ab
    services.ab
  tests/
    compile_test.ab
    form_test.ab
    response_test.ab
    retry_test.ab
    webhook_test.ab
    service_test.ab
  tools/
    test-stripe.sh
```

`src/stripe.ab` is the single public package entry and imports the other
modules. Consumers use:

```abla
import github("AndreBaltazar8/abla-stripe")
```

## 7. Public API requirements

Names below define the intended surface. Small syntax adjustments are allowed
when required by the current compiler, but the semantics and capabilities are
acceptance requirements.

### 7.1 Client configuration

```abla
val stripe = stripeClient(StripeConfig(
    secretKey,
    stripeDefaultApiVersion(),
    30000,
    1,
    8 * 1024 * 1024,
    true,
    StripeAppInfo("kilo", "0.1.0", "https://kilo.pt")
))
```

Configuration must include:

- secret key;
- API version, defaulting to `2026-07-29.dahlia` for package `0.1.x`;
- timeout in milliseconds;
- maximum network retries, default `1`, bounded to `0..5`;
- maximum response body bytes;
- telemetry setting, default `false` in Abla Stripe;
- optional application name/version/URL for `User-Agent` metadata; and
- API host/port, restricted to `api.stripe.com:443` in normal mode.

`stripeConfigFromEnvironment()` reads `STRIPE_SECRET_KEY` or
`STRIPE_SECRET_KEY_FILE`, with the direct value taking precedence. Optional
configuration uses `STRIPE_API_VERSION`, `STRIPE_TIMEOUT_MS`,
`STRIPE_MAX_NETWORK_RETRIES` and `STRIPE_ENABLE_TELEMETRY`.

Secret-file content has trailing CR/LF removed. Error values and printable
configuration must never contain the secret key.

### 7.2 Request options

Every service and raw request accepts `StripeRequestOptions`, containing:

- `idempotencyKey`;
- `stripeAccount` for Connect's `Stripe-Account` header;
- optional API version override;
- optional timeout override; and
- optional retry-count override.

Idempotency keys are limited to 255 bytes and rejected if they contain control
characters. Typed mutation helpers require a non-empty caller-supplied key.
The lower-level raw API permits an empty key for compatibility, but does not
automatically retry a `POST` without one.

### 7.3 Parameters and encoding

Stripe API v1 requests use `application/x-www-form-urlencoded`. The package
provides a `StripeParams` builder supporting:

- string, integer and boolean values;
- explicit empty strings;
- repeated array fields such as `expand[]`;
- nested keys such as `metadata[account_id]`;
- indexed structures such as `line_items[0][price]`; and
- deterministic insertion-order encoding for fixtures and idempotency audits.

Keys and values use RFC 3986 percent encoding with UTF-8 bytes. Spaces encode
as `%20`, never ambiguously as raw spaces. The encoder must handle Portuguese
text and reject CR/LF in field names.

The builder does not silently turn `null` into an empty string; omission and an
explicit empty value remain different operations.

### 7.4 Results and errors

No expected Stripe or network error terminates the process. Calls return a
`StripeResult` with:

- `succeeded`;
- parsed `Json` value when valid;
- exact response body, bounded by configuration;
- HTTP status;
- `Request-Id`;
- Stripe API version response header when present;
- idempotency key;
- number of retries performed;
- rate-limit reason when present; and
- a structured `StripeError`.

`StripeError` exposes, when returned by Stripe:

- `kind` (`api_error`, `card_error`, `idempotency_error`,
  `invalid_request_error`, `network_error`, `parse_error`,
  `configuration_error`, or `unknown_error`);
- `message`, `code`, `declineCode`, `param`, `docUrl`;
- `paymentIntentId`, `paymentMethodId`, `setupIntentId` when present;
- HTTP status and request ID; and
- whether the final failure is retryable.

Malformed JSON on a successful status is a `parse_error`, not a success.
Unknown error fields and unknown enum values remain accessible through the raw
JSON object.

### 7.5 HTTP and authentication

Normal API requests must:

- use certificate-verified TLS to `api.stripe.com:443`;
- use `Authorization: Bearer <secret>`;
- send the selected `Stripe-Version`;
- send an identifiable `User-Agent` and client information header;
- send `Content-Type: application/x-www-form-urlencoded` for API v1 `POST`;
- attach `Idempotency-Key` and `Stripe-Account` only when set; and
- capture `Request-Id`, `Stripe-Version`, `Stripe-Should-Retry`, `Retry-After`
  and `Stripe-Rate-Limited-Reason` response headers case-insensitively.

Redirects are not followed for API requests. A redirect is returned as an
error because following it could disclose the Authorization header.

### 7.6 Retries

The default is one safe retry, matching the current Node SDK default. Retry
decisions must consider:

- network failures before a usable response;
- `Stripe-Should-Retry: true` or `false` as the strongest signal;
- HTTP `409`, `429`, `500`, `502`, `503` and `504` as retry candidates;
- `Retry-After` when valid and bounded; and
- exponential backoff with jitter otherwise.

`GET` and `DELETE` may be retried. `POST` may be retried only when an
idempotency key is present. Authentication, permission, card and ordinary
validation errors are not retried.

Retries are capped by both the configured count and a bounded delay. Tests use
an injectable/no-wait retry policy so they are deterministic. The same
idempotency key and exact encoded body must be reused for every attempt.

### 7.7 Raw requests

```abla
val result = stripe.rawRequest(
    "POST", "/v1/example", params, options
)
```

The raw API supports API v1 `GET`, `POST` and `DELETE` paths beginning with
`/v1/`. It rejects absolute URLs, path traversal, fragments and embedded
control characters. It returns the same structured result and retry behaviour
as typed services.

This is the compatibility path for undocumented, preview and newly released
parameters. It must be documented as less type-safe, not less secure.

API v2 JSON request semantics, multipart file uploads and streaming downloads
are outside `0.1.0`.

### 7.8 Typed services

The client exposes service-shaped methods analogous to the official
`StripeClient` pattern. Abla may implement these as methods on `StripeClient`
with consistent resource prefixes if nested service objects are awkward.

Required `0.1.0` operations:

- Customers: create, retrieve, update, list.
- Checkout Sessions: create, retrieve, list.
- Billing Portal Sessions: create.
- Subscriptions: retrieve, update, cancel, list.
- Products: retrieve, list.
- Prices: retrieve, list.
- Events: retrieve, list.

Required typed resource projections:

- `StripeCustomer`: id, email, name, livemode, metadata.
- `StripeCheckoutSession`: id, URL, mode, status, customer ID,
  subscription ID, client reference ID, livemode, metadata.
- `StripeBillingPortalSession`: id, URL, customer ID, livemode.
- `StripeSubscription`: id, customer ID, status, cancel-at-period-end,
  current-period start/end derived from subscription items, product and price
  IDs, livemode, metadata.
- `StripeProduct`: id, name, active, livemode, metadata.
- `StripePrice`: id, product ID, active, currency, unit amount, recurring
  interval/count, tax behaviour, livemode, metadata.
- `StripeEvent`: id, type, created, livemode, API version, data object.
- `StripeList`: object/data array, has-more and URL.

Every typed result also retains the complete parsed JSON response. Expandable
references expose their ID whether Stripe returned a string or expanded
object.

List methods expose explicit pages. A bounded helper may collect pages up to a
caller-provided item limit; it must require a positive limit and stop on empty
pages, missing cursors, repeated cursors or the limit. It must not offer an
unbounded collect-all operation.

### 7.9 Webhooks

```abla
val verified = stripeWebhookConstructEvent(
    rawBody,
    stripeSignatureHeader,
    [currentSecret, previousSecret],
    nowUnixSeconds,
    300
)
```

Webhook verification must:

- accept the exact, unparsed raw request body;
- parse all `t=` timestamps and `v1=` signatures without assuming order;
- compute HMAC-SHA256 over `<timestamp>.<rawBody>`;
- compare signatures in constant time;
- support multiple endpoint secrets during rotation;
- require at least one valid signature;
- reject timestamps older or farther in the future than the positive
  tolerance, default 300 seconds;
- reject tolerance `<= 0` rather than disabling replay protection;
- distinguish malformed header, invalid signature, stale timestamp, invalid
  JSON and invalid event envelope errors; and
- return a typed `StripeEvent` plus the raw parsed JSON only after both
  signature and JSON validation succeed.

`stripeWebhookGenerateTestHeader(...)` creates deterministic signed headers for
fixtures. Test helpers must be clearly named and never weaken production
verification.

Webhook verification does not persist event IDs or run business logic.
Consumers must durably deduplicate `event.id`, return `2xx` promptly and process
complex work asynchronously.

## 8. Security requirements

- API keys and webhook secrets never appear in errors, debug formatting,
  request metadata or test snapshots.
- No global mutable API key is required; independent clients may safely use
  different accounts or modes.
- The package does not accept publishable keys for server authentication.
- Live and test mode consistency is exposed to, and enforced by, the consumer;
  typed helpers preserve every resource's `livemode` value.
- Webhook parsing happens after signature validation except for the minimal raw
  header parsing needed to authenticate.
- JSON and HTTP bodies use explicit size/depth/item/string limits.
- Error messages are suitable for server logs but never presented directly to
  end users as payment advice.
- Cleartext HTTP is unavailable in public production configuration. A
  deliberately named loopback-only test transport may be compiled for
  integration fixtures and must reject non-loopback hosts.
- Logs and observability hooks are metadata-only by default. Request/response
  bodies require explicit application-side handling.

## 9. Compatibility and version policy

- Package `0.1.x` pins Stripe API `2026-07-29.dahlia`.
- The selected version is always sent explicitly; account-default drift must
  not silently alter response shapes.
- A new Stripe major API release requires an `abla-stripe` major/minor review,
  fixture refresh and migration note before changing the default.
- Backward-compatible monthly Stripe versions may be tested as explicit
  overrides without changing the package default.
- Unknown additive JSON fields are preserved. Unknown enum strings do not
  cause parsing failure unless they make a safety decision ambiguous.
- The package version and pinned Stripe version appear in README and client
  metadata.

## 10. Testing requirements

### Deterministic unit tests

- Percent encoding: ASCII, delimiters, spaces, empty values and UTF-8.
- Nested/repeated parameter ordering.
- Configuration validation and secret-file newline trimming.
- Successful and malformed JSON decoding.
- Every documented Stripe error type and useful optional field.
- Case-insensitive response header extraction.
- Retry matrix for methods, statuses, network failures,
  `Stripe-Should-Retry`, missing idempotency and retry limits.
- No secret leakage through every error path.
- Webhooks: valid signature, multiple signatures, multiple secrets, rotation,
  malformed fields, wrong secret, body mutation, stale/future timestamp,
  zero tolerance and invalid event JSON.
- Typed parsing for every required resource, including string and expanded
  references and subscription-item billing periods.
- Pagination termination and maximum-item bounds.

### Protocol integration tests

A scripted loopback server or pinned `stripe-mock` process must assert:

- method, path, headers and exact encoded request body;
- API version and User-Agent metadata;
- request ID propagation;
- typed service paths and parameters;
- error object decoding;
- retry attempts preserve body and idempotency key; and
- redirects are not followed.

Tests must not require a developer's Stripe secret and must not create real
Stripe objects.

### Optional Stripe sandbox smoke tests

An opt-in test guarded by an explicit environment flag may use restricted
sandbox credentials. It must use unique metadata, idempotency keys and cleanup,
and must never run as part of ordinary `make test`.

### Consumer test

Kilo's customer, Checkout, portal and webhook transport code is migrated to
`abla-stripe`. Its existing billing tests must pass with billing disabled and
the package must compile in Kilo's production build. Kilo retains database
idempotency, entitlement policy, mode checks and redirect allow-listing.

## 11. Documentation requirements

README must include:

- installation/import;
- a minimal client example;
- customer, Checkout and portal examples;
- request options and idempotency guidance;
- webhook integration showing the raw body requirement;
- structured error handling and request IDs;
- environment/secret-file configuration;
- pinned API version and upgrade policy;
- testing commands;
- explicit non-goals; and
- a statement that this is an independent, unofficial package.

API examples must use placeholders and sandbox-shaped identifiers. No real
credential may enter the repository history.

## 12. Non-goals for 0.1.0

- Stripe.js, Elements, Payment Element or browser-side card collection.
- Google Play Billing, Apple StoreKit or mobile entitlement verification.
- A complete generated class for every Stripe API resource.
- API v2 endpoints and their different JSON/idempotency semantics.
- Connect OAuth onboarding or platform fee policy.
- Multipart file upload and streaming file download.
- Automatic database persistence or webhook job queues.
- Automatic product, price, tax or legal-copy decisions.
- Automatic display of Stripe error text to customers.
- Asynchronous promises or background threads in the public API.

## 13. Delivery phases

### Phase 1: package and protocol core

- Repository skeleton, manifest, licence and compiler test.
- Configuration, secret loading and validation.
- Form parameter builder and encoder.
- Raw request/result/error model.
- Header capture, safe retry policy and deterministic fixtures.

### Phase 2: webhooks

- Signature header parser, constant-time multi-secret verification, replay
  window and typed event construction.
- Complete deterministic webhook fixture matrix.

### Phase 3: typed billing services

- Required resources and service operations.
- Explicit bounded pagination.
- Protocol fixtures for exact endpoints and bodies.

### Phase 4: Kilo adoption

- Replace Kilo's generic Stripe transport, form encoding, errors and signature
  verification with package calls.
- Preserve Kilo-specific mode, product/price, database and entitlement checks.
- Run Kilo unit, integration and production compile gates with billing still
  disabled.

### Phase 5: release readiness

- README and migration example complete.
- `make check` and `make test` green from a clean checkout.
- No compiler artefacts or credentials tracked.
- Package imported successfully through sibling path and package manifest.
- Version/API-version constants and changelog recorded.

## 14. Acceptance criteria

Version `0.1.0` is complete only when all of the following are true:

1. An Abla service can create a client without global state and make a bounded,
   version-pinned API v1 request.
2. All normal requests use verified TLS and cannot redirect an Authorization
   header.
3. Encoding fixtures match Stripe API v1 nested form conventions, including
   UTF-8.
4. Safe retries are bounded, respect Stripe headers and never retry a `POST`
   without an idempotency key.
5. Structured failures retain status and request ID without leaking secrets.
6. Webhook fixtures prove raw-body, constant-time, multi-secret and timestamp
   validation.
7. Every required typed service compiles and passes protocol fixtures.
8. Pagination cannot grow without a caller-provided bound.
9. The raw request escape hatch supports an untyped `/v1/` endpoint without
   bypassing authentication, limits or error handling.
10. Kilo compiles and its billing tests pass using `abla-stripe`, with billing
    remaining fail-closed until owner credentials are supplied.
11. Public documentation clearly distinguishes Abla Stripe from Stripe's
    official SDKs and states the pinned API version.
12. `make check`, `make test` and repository hygiene checks pass with no live
    Stripe credentials.

## 15. Later roadmap

- OpenAPI-driven generation of broader typed resources after Abla has a stable
  generator and compatibility-test story.
- Payment Intents, Setup Intents, invoices, refunds and disputes as demand
  emerges.
- API v2 client and include-dependent response values as a separate versioned
  surface.
- Multipart uploads, streaming downloads and richer observability hooks.
- Connect account services and OAuth only with a dedicated security PRD.
