# ADR-0003: Explicit content-addressed PWA releases

- Status: accepted; records the implemented release/cache design.
- Date: 2026-10-06.
- Decision basis: required installability, offline shell and safe update behavior.

## Context

A Flutter web build alone does not establish this application's offline/update guarantees. Running tabs must continue loading a consistent release while a new version is installed. Catalog and chat data have a different lifecycle from static shell assets.

## Decision

Assemble complete immutable Flutter releases with a Dart build tool and a minimal service worker that verifies an explicit content-hash manifest, caches only shell assets and activates updates through an explicit saved-state flow.

## Consequences

- Unchanged content keeps a stable release identity; configuration changes do not manufacture shell updates.
- Installation verifies size/hash and reuses matching assets. Incomplete generations never activate.
- Old tabs retain versioned asset URLs. Cache cleanup keeps the current/preceding generations and those needed by known open clients.
- API calls, keys, configuration, conversation bodies and attachments never enter the service-worker response cache.
- Offline startup still requires a successfully installed shell; remote chat remains unavailable offline.
- Browser eviction, HTTPS/localhost requirements and implementation differences need real release-browser verification. Unit source-contract tests alone cannot prove installation or updates.

## Considered options

- **Explicit worker plus Dart assembly, chosen:** gives testable cache boundaries and consistent releases within the permitted minimal web glue.
- **Assume Flutter build defaults:** does not satisfy the required update/cache policy or verification scope.
- **Cache all runtime responses:** mixes authenticated/private requests with shell assets and creates stale API behavior.
- **No service worker:** avoids cache complexity but fails the requested offline/installable PWA behavior.

See [PWA behavior](../pwa.md) and [release identity/measurement](../performance.md).
