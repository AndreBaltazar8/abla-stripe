# Abla Stripe

Abla Stripe is an independent, server-side Stripe API client written in
[Abla](https://github.com/AndreBaltazar8/ablac). It follows the client/service
shape and safety behaviour of Stripe's official Node.js and PHP SDKs without a
language sidecar or C Stripe library.

This package is not developed, maintained or endorsed by Stripe.

## Current release

Version `0.1.0` explicitly sends Stripe API version
`2026-07-29.dahlia`. Applications do not silently inherit the Stripe account's
default API version.

The release includes:

- certificate-verified HTTPS to `api.stripe.com`;
- secret-file and environment configuration;
- deterministic nested API v1 form encoding with UTF-8 support;
- request options for idempotency, Connect accounts, API versions, timeouts and
  retry limits;
- bounded safe retries that respect `Stripe-Should-Retry` and `Retry-After`;
- opt-in telemetry carrying only the previous request ID and duration;
- structured errors, response bodies, request IDs and rate-limit reasons;
- typed Customers, Checkout Sessions, Billing Portal Sessions, Subscriptions,
  Products, Prices and Events;
- bounded cursor pagination;
- constant-time, replay-bounded, multi-secret webhook verification; and
- a guarded raw `/v1/` request API for endpoints not yet represented by a typed
  service.

## Import

```abla
import github("AndreBaltazar8/abla-stripe")
```

During sibling-checkout development:

```abla
import "../../abla-stripe/src/stripe.ab"
```

## Configuration

The smallest production setup reads a restricted or secret Stripe key from the
environment:

```abla
val stripe = stripeClient(stripeConfigFromEnvironment())
```

Supported variables are:

- `STRIPE_SECRET_KEY` or `STRIPE_SECRET_KEY_FILE`;
- `STRIPE_API_VERSION` (defaults to the package-pinned version);
- `STRIPE_TIMEOUT_MS` (defaults to `30000`);
- `STRIPE_MAX_NETWORK_RETRIES` (defaults to `1`, maximum `5`); and
- `STRIPE_ENABLE_TELEMETRY` (defaults to `false`).

The direct secret value takes precedence over the file. A secret file may end
with CR/LF, which is removed. Keys and webhook secrets never appear in package
errors.

Telemetry is disabled by default. When explicitly enabled, requests after the
first include Stripe's `X-Stripe-Client-Telemetry` JSON with only the previous
Stripe request ID and its duration. It never contains request parameters,
response bodies, credentials or account data.

Applications that want client identification can construct a configuration:

```abla
val stripe = stripeClient(StripeConfig(
    secretKey,
    stripeDefaultApiVersion(),
    30000,
    1,
    1048576,
    false,
    StripeAppInfo("my-service", "1.0.0", "https://example.com"),
    "api.stripe.com",
    443,
    false
))
```

Normal configuration accepts only `api.stripe.com:443`. The separately named
`stripeLoopbackTestClient` accepts only `127.0.0.1` and exists for protocol
fixtures; it must not be used with real credentials.

## Customers

Typed mutations require a caller-owned idempotency key:

```abla
val params = stripeParams()
params.add("email", "andre@example.com")
params.add("name", "André")
params.add("metadata[account_id]", accountId)

val created = stripe.customersCreate(
    params,
    stripeIdempotentRequest("customer-$accountId")
)

if (!created.succeeded) {
    // Log created.response.requestId and a suitable internal error code.
    // Do not show the raw Stripe message directly to an end user.
    return
}

val customerId = created.customer.id
```

Retrieve, update and list use `customersRetrieve`, `customersUpdate` and
`customersList`. Every typed result retains its `StripeResult`, including the
complete bounded JSON value and body.

## Checkout and Customer Portal

```abla
val checkout = stripeParams()
checkout.add("mode", "subscription")
checkout.add("customer", customerId)
checkout.add("line_items[0][price]", priceId)
checkout.addInt("line_items[0][quantity]", 1)
checkout.add("success_url", "https://example.com/billing/success")
checkout.add("cancel_url", "https://example.com/billing/cancelled")
checkout.addBool("automatic_tax[enabled]", true)

val session = stripe.checkoutSessionsCreate(
    checkout,
    stripeIdempotentRequest(operationId)
)
```

For a portal session:

```abla
val portal = stripeParams()
portal.add("customer", customerId)
portal.add("return_url", "https://example.com/settings")

val session = stripe.billingPortalSessionsCreate(
    portal,
    stripeIdempotentRequest(operationId)
)
```

The application must still allow-list returned Checkout and Portal URL origins
before redirecting a browser.

## Request options and retries

`StripeRequestOptions` can set an idempotency key, `Stripe-Account`, an API
version override, timeout and retry count. `stripeRequestOptions()` creates
empty defaults; `stripeIdempotentRequest(key)` is the common mutation form.

The default is one retry. `GET` and `DELETE` are safe to retry. A `POST` is
never automatically retried without an idempotency key. Retried requests reuse
the exact body and key. Delays are exponential with jitter, honour a bounded
`Retry-After`, and never exceed the configured retry count.

Stripe idempotency prevents duplicated remote mutations; it does not replace
application database idempotency or durable webhook event deduplication.

## Errors and request IDs

Expected failures return values rather than terminating the process:

```abla
val result = stripe.pricesRetrieve("price_123")
if (!result.succeeded) {
    val errorType = result.response.error.kind
    val requestId = result.response.requestId
    val status = result.response.status
}
```

Structured errors preserve Stripe's type, code, decline code, parameter,
documentation URL and related Payment Intent/Method/Setup Intent IDs when
present. Unknown fields remain in the raw JSON.

## Pagination

List methods return one explicit page. Use `collectList` only with a positive
hard bound:

```abla
val filters = stripeParams()
filters.add("email", "andre@example.com")
val customers = stripe.collectList("/v1/customers", filters, 500)
```

The helper adds `starting_after`, stops at the limit, and rejects empty or
repeated cursors. It deliberately has no unbounded collect-all form.

## Webhooks

Pass the exact request bytes before JSON parsing or any whitespace/encoding
normalisation:

```abla
val verified = stripeWebhookConstructEvent(
    request.body,
    request.header("Stripe-Signature"),
    [currentEndpointSecret, previousEndpointSecret],
    unixSeconds,
    300
)

if (!verified.succeeded) return httpText("invalid signature", 400)
val event = verified.event
```

Verification checks every `v1` signature in constant time, supports overlapping
secrets during rotation and rejects stale or future timestamps. A tolerance of
zero is rejected because it would disable replay protection.

Persist and deduplicate `event.id`, return `2xx` quickly and move complex
business work to a durable queue. The package authenticates and parses events;
it does not decide entitlements or store processing state.

`stripeWebhookGenerateTestHeader` creates deterministic fixture signatures. It
does not alter production verification.

## Raw API

```abla
val params = stripeParams()
params.add("example", "value")
val result = stripe.rawRequest(
    "POST",
    "/v1/new_endpoint",
    params,
    stripeIdempotentRequest(operationId)
)
```

Only relative `/v1/` paths and `GET`, `POST` or `DELETE` are accepted. Absolute
URLs, raw query strings, fragments, traversal and control characters are
rejected. The escape hatch uses the same TLS, limits, retries, errors and
redaction as typed services.

## Build and test

Build `../ablac`, then run:

```sh
make check
make test
```

`make check` compiles and runs deterministic encoding, client, retry, resource,
pagination and webhook fixtures. `make test` also starts a temporary loopback
HTTP server and verifies the exact request protocol over a real socket. No
Stripe credential or network connection is needed.

## Scope

Version `0.1.0` is server-side API v1 infrastructure. It does not include
Stripe.js/Elements, mobile store billing, Connect OAuth, API v2, file uploads,
database persistence or product/tax/legal policy. See [PRD.md](PRD.md) for the
acceptance contract and roadmap.

## License

MIT. See [LICENSE](LICENSE).
