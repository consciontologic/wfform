# Docker and nginx deployment

wfform remains a Flutter/Dart application. nginx serves static release files; the browser calls OpenRouter directly. There is no API proxy or application backend. Using a published image requires Docker. Building from source also requires Flutter **3.38.10 / Dart 3.10.9**, Compose, Make and Bash. OpenSSL is needed only for optional local TLS.

## Use a published GHCR image

Approved releases publish the static web app as a **Linux amd64** image at
`ghcr.io/consciontologic/wfform:<version>`. Windows/macOS users need Docker's Linux
container mode; this image does not provide access to local CLI tools. Use the
separate [wfformcomp](../wfformcomp.md) for those.

This publishing path applies to future approved releases; the existing `1.0.0`
release has no GHCR image. After an image is published, replace `VERSION` below
with its exact SemVer:

```sh
docker pull ghcr.io/consciontologic/wfform:VERSION
docker run --rm --name wfform --platform linux/amd64 \
  --publish 127.0.0.1:8080:8080 \
  --read-only --cap-drop ALL --security-opt no-new-privileges \
  --tmpfs /tmp:rw,noexec,nosuid,size=64m \
  ghcr.io/consciontologic/wfform:VERSION
```

Open **http://localhost:8080** and add your own key in Settings. No registry login
is needed once the package is Public. There is no `latest` tag: choose a published
SemVer and change it explicitly to upgrade. The workflow configuration is not
proof that a tag is already available; inspect the release run's container result.

**First publication:** GitHub initially creates a private package. In your account's
**Packages → wfform → Package settings → Change visibility**, set it to **Public**
to allow anonymous pulls. This is a one-time package setting. Ensure the package
is connected to `consciontologic/wfform` and grants its Actions workflow write
access. The publisher uses the built-in `GITHUB_TOKEN`; no separate registry
secret is required. See [GitHub's Container Registry guide](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry).

Container Registry storage and bandwidth are currently free under
[GitHub's billing policy](https://docs.github.com/en/billing/concepts/product-billing/github-packages).
GitHub Actions usage and retained workflow artifacts have separate limits.
Images are built from allowlisted public files and published only after the same
human production approval as the release. Existing version tags are preserved.

## Start a local container

From the project root:

```sh
make deps
make image
make up
make check
```

Open **http://localhost:8080**. Paste your development API key in Settings. Docker uses a separate browser origin from the Dart host on 8765, so its IndexedDB history is separate. `make image` compiles under `build/container-input`, then publishes an isolated release under `build/container-web`; it does not replace `build/web` or interrupt an existing Dart server. Packaging preserves verified flat release assets and the custom service worker; a raw `flutter build web` is insufficient. A hash of the public nginx policy contributes to the Docker release identity, so changing CSP creates new stamped HTML and a safe PWA update rather than silently retaining old cached headers. Identical application bytes and policy retain a stable identity.

```sh
make logs       # follow the last 100 container log lines
make restart    # recreate from the current image without rebuilding
make down       # stop/remove only this Compose project's containers/network
```

Rebuild with `make image`, then use `make restart` to deploy changed source. Version 1.0.0 uses flat assets, without physical `__releases` directories. The service worker preserves verified cached generations and offers an explicit update; an old uncached asset requires an update rather than substituting changed bytes. Its integrity and safe-update behavior remains authoritative. This simple local workflow can briefly interrupt HTTP during container replacement; it is not a zero-downtime orchestrator. Browser-managed data is not a container volume and is unaffected by `down`.

`HTTP_PORT=8081 make up` chooses another loopback port; use the same variable for `check` and `restart`. Changing the origin changes browser-local storage. Defaults never publish on all network interfaces. The runtime runs as the invoking host user's non-root UID/GID, with a read-only root filesystem, dropped Linux capabilities, `no-new-privileges`, bounded memory/CPU/PIDs and one small writable `/tmp` tmpfs. No host firewall, system nginx or Docker daemon configuration is changed.

## Credential boundary

`tool/build.dart` copies the ignored development configuration into its local build output for the Dart host. **The container packager deliberately does not copy it.** `deploy/package.dart` creates an isolated allowlisted context at `build/docker-context`, validates asset sizes and SHA-256 hashes, rejects symlinks and recognizable OpenRouter/private-key material, and includes only manifest-listed shell assets plus public nginx configuration. Unknown files, source maps, repository metadata and runtime configuration are excluded. `.dockerignore` independently rejects configuration/key files. `Dockerfile` receives only this generated context; do not change it to `COPY .`.

An explicit, optional runtime configuration can be mounted read-only:

```sh
WFFORM_CONFIG_FILE="$PWD/config/local.json" make up
WFFORM_CONFIG_FILE="$PWD/config/local.json" make check
```

When adding/removing a mount on an existing container, use the same command with `make restart`. Without this setting `/config/local.json` returns 404 and the app uses defaults or a saved browser key. A mount is served only at that exact path with `Cache-Control: no-store`; other `/config/` paths stay 404. It never enters the image or PWA cache. The access log omits this endpoint, query strings and headers. Credentials delivered to a browser remain accessible to that browser's user; a shared mounted key is not a production secret boundary. Prefer each user's own saved browser key for shared hosting.

## HTTPS for local checks

```sh
make tls.cert
make tls.up
make tls.check
```

This creates a 30-day self-signed certificate with localhost/loopback SANs under ignored `.local/tls`, without installing it in any trust store. Existing certificate material is preserved rather than overwritten. `tls.up` adds **https://localhost:8443** alongside local HTTP; `TLS_PORT=8444 make tls.up` changes that port. `tls.check` verifies the server using this explicit project certificate, not an insecure certificate bypass. The browser will still require a trusted certificate for normal secure-context/PWA behavior; local HTTP on localhost is the simplest browser development origin. `make tls.down` stops the same project.

For production, supply a certificate chain and matching private key from your CA/ACME workflow at the read-only TLS mount, readable only by the intended container UID. Use a real DNS name and configure `server_name`, network publication and HTTP-to-HTTPS redirection for that specific deployment. For example, a dedicated public HTTP server can `return 308 https://your.actual.domain$request_uri;`; do not copy that placeholder unchanged. Alternatively terminate TLS at a trusted ingress and keep this static container on its private network. Certificate issuance/renewal, ingress configuration, monitoring and public DNS are operator responsibilities; this demo does not install host services or claim a publicly deployed TLS configuration.

TLS uses 1.2/1.3, an explicit forward-secret TLS1.2 cipher list, session caching and disabled session tickets. HTTPS responses initially send `Strict-Transport-Security: max-age=86400`. After verifying public HTTPS and renewal, a production policy can use `max-age=31536000` (one year) or longer. Add `includeSubDomains` only when every affected subdomain supports HTTPS, and request preload only with an appropriate long-term policy. HTTP sends no HSTS. Local TLS intentionally retains local HTTP rather than silently redirecting the developer's existing origin.

## Headers and Flutter compatibility

The enforced policy lives in `deploy/nginx/headers.conf`:

- Scripts load from this origin and the explicitly allowed Google tag loader at **`https://www.googletagmanager.com/gtag/js`**. Its fixed inline bootstrap is permitted by a SHA-256 hash; unrestricted inline scripts and event handlers remain blocked. WebAssembly is allowed with **`'wasm-unsafe-eval'`**, not general JavaScript `'unsafe-eval'`.
- Flutter/CanvasKit and the startup host need generated/inline styles, so **style-only `'unsafe-inline'`** is deliberate. Removing it or adding nonces only to the host HTML does not cover Flutter's generated styles.
- Connections allow this origin, **`https://openrouter.ai`**, Flutter's fallback-font path **`https://fonts.gstatic.com/s/`**, and the explicit Google analytics destinations in the checked-in policy. Analytics pixel requests use the matching `img-src` permissions; advertising endpoints are excluded. A different configured API base requires an explicit reviewed CSP update. This is not a CORS workaround; the upstream still determines cross-origin API access.
- Roboto, app images and CanvasKit/WASM are bundled. Glyphs missing from those fonts can trigger Flutter's documented remote Noto fallback. Real browser verification exposed blocked Noto Sans Symbols/SC requests under the initial CSP; the font-fetch path is now allowed in `font-src` and `connect-src`. These fallback fonts are not shell-precached, so arbitrary non-bundled glyph coverage is not guaranteed offline. `data:`/`blob:` support is restricted to image/media/font or worker directives as appropriate; script and connection sources are explicitly bounded by the policy above.
- Framing, plugins and form submissions are blocked; `nosniff`, `no-referrer`, a restrictive Permissions Policy, same-origin opener/resource policies and frame denial apply to both successes and errors. Uploading a file does not require camera/microphone permission. Clipboard read and write are allowed only for **`self`**: Flutter 3.38.5's editable Paste control calls `Clipboard.getData`, which its web engine implements with `navigator.clipboard.readText()`. Denying clipboard read would break that path even when native keyboard paste still works. This origin allowance does not grant browser permission: secure-context, focus, user-activation and consent requirements still apply according to the browser.
- COEP is not forced: the current app needs no cross-origin-isolation feature. Headers are not an authentication system, and no invented “A+++” security grade is claimed. No external scanner grade has been measured.

The `add_header ... always` directives are included only at server scope; locations introduce no `add_header` directives that could erase inheritance. Root aliases, HTML, the worker, release metadata, configuration and 404s use **no-store**. Flat asset responses also use `no-store`; the service worker manages content-verified cache generations. Gzip is enabled for eligible JS/JSON/CSS/WASM responses. Missing assets return real 404s, never SPA HTML, so an incomplete deployment cannot be mistaken for valid cached JavaScript. The web app currently mounts at `/`; deploying a subpath also requires compatible Flutter base href, nginx locations and CSP review.

## Verification commands and limits

```sh
make verify
flutter test test/deploy --reporter expanded
make image
make up
make check
make tls.cert
make tls.up
make tls.check
```

`make check` executes `nginx -t`, verifies a non-root runtime and absence of baked local configuration, then checks HTTP health, CSP/security headers, no-store configuration/entrypoints, denied POST/dotfiles, uncached asset misses, correct WASM MIME, and the bytes/SHA-256/cache policy of every current verified shell asset. It sends no OpenRouter request and never prints configuration content. `tls.check` adds HTTPS certificate verification and TLS-only HSTS checks. The Docker healthcheck itself performs a bounded local HTTP request every 15 seconds.

Unit tests cover allowlisting, malformed/traversal manifests, damaged content preserving the previous context, symlink/credential rejection, and the header/TLS contract. Browser rendering, CanvasKit, PWA install/update and live direct API behavior need a real browser; passing header checks alone is not evidence for them. Public TLS/ACME renewal, OS-level installation, scanner grades, deployed subpaths and other browser engines remain separate acceptance work.

## Official references

Reviewed **2026-10-06**:

- [Official nginx image on ECR Public](https://gallery.ecr.aws/docker/library/nginx): the Docker Official Images mirror serves the same `1.30.5-alpine` image and checked digest in `Dockerfile`. Anonymous pulls require no AWS account or secret and avoid Docker Hub's shared-runner pull quota. [AWS documents this official mirror and anonymous access](https://aws.amazon.com/blogs/containers/docker-official-images-now-available-on-amazon-elastic-container-registry-public/). Review upstream updates and replace the digest deliberately; a pin does not update itself.
- [nginx response-header module](https://nginx.org/en/docs/http/ngx_http_headers_module.html): `always` and inheritance behavior.
- [nginx HTTPS server configuration](https://nginx.org/en/docs/http/configuring_https_servers.html) and [SSL module](https://nginx.org/en/docs/http/ngx_http_ssl_module.html): certificates, TLS policy and session settings.
- [MDN script CSP](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/script-src) and [style CSP](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/style-src): distinct WebAssembly and inline-style permissions.
- [Flutter web initialization](https://docs.flutter.dev/platform-integration/web/initialization): the documented fallback-font base when bundled glyphs are insufficient. The current documentation describes a newer Flutter version; the 3.38.5 browser run independently observed this same default fallback origin.
- [MDN Clipboard API](https://developer.mozilla.org/en-US/docs/Web/API/Clipboard_API): browser-specific clipboard permission and user-interaction requirements. The Paste implementation was checked directly in the installed Flutter 3.38.5 SDK's `editable_text.dart`, services `clipboard.dart`, and web engine `clipboard.dart`.
- [OWASP HTTP Headers Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/HTTP_Headers_Cheat_Sheet.html): header purposes and deployment tradeoffs.
