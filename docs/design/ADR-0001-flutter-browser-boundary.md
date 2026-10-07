# ADR-0001: Flutter client with direct structured API access

- Status: accepted; records the implemented user-specified boundary.
- Date: 2026-10-06; initial scope requested 2026-10-05.
- Decision basis: user technology and discovery requirements.

## Context

The application must discover OpenRouter's current free models and support adaptive browser chat without introducing a second application stack. Website markup is unsuitable as a stable catalog contract, and neither a free suffix nor catalog presence is sufficient to authorize a free usable route.

## Decision

Keep UI/domain logic in Flutter/Dart and call the official structured OpenRouter API directly from browser adapters, with no application backend or API proxy.

## Consequences

- DTO parsing, price validation, capability checks and request policy are localized in model/chat adapters and can be tested without widgets.
- CORS and browser networking remain real integration constraints. An opaque fetch failure is reported honestly rather than automatically labeled CORS or bypassed through a proxy.
- Development credentials delivered to the browser are visible to its user; this demo does not add unrelated account infrastructure.
- Browser-specific storage/file/PWA ports are replaceable for future Flutter platforms, but stubs do not imply native acceptance.
- Static Dart/nginx serving and minimal web/PWA glue are infrastructure, not alternative application logic.

## Considered options

- **Flutter plus direct API, chosen:** matches the user constraint and keeps one domain/presentation stack.
- **Backend/proxy:** could change authentication/networking behavior but violates the initial scope and adds an operational service.
- **Scraping the website:** depends on presentation details instead of a structured API and cannot reliably establish pricing semantics.
- **Another frontend stack:** duplicates or replaces Flutter contrary to the requested technology.

See [architecture](../code/ARCHITECTURE.md) and [catalog policy](../catalog.md).
