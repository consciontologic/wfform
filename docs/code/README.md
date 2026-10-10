# Code documentation

| Actual project document | Use |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | System boundary, components, request/data flow and persistence |
| [MODULES.md](MODULES.md) | Change ownership, invariants, extension points and relevant tests |
| [API.md](API.md) | OpenRouter operations and replaceable local interfaces |

Feature-level details remain in the [application contract index](../README.md). Start from these current documents before creating another overlapping overview.

For a new boundary, document its purpose, public interface, invariants, dependencies and verification in the appropriate document above. Create a separate page only when the boundary needs its own maintained contract, and link it from this index.
