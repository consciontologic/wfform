# Docker/nginx

The image serves static wfform; browser calls go directly to OpenRouter. It provides
no local CLI access or inference proxy. Use [wfformcomp](../wfformcomp.md) for tools.

## Use a published GHCR image

Future approved releases publish **Linux amd64** images; 1.0.0 has no GHCR image.
After publication replace `VERSION` with the exact SemVer (no `latest` tag):

```sh
docker pull ghcr.io/consciontologic/wfform:VERSION
docker run --rm --name wfform --platform linux/amd64 \
  --publish 127.0.0.1:8080:8080 --read-only --cap-drop ALL \
  --security-opt no-new-privileges --tmpfs /tmp:rw,noexec,nosuid,size=64m \
  ghcr.io/consciontologic/wfform:VERSION
```

Open **http://localhost:8080**, add your own key in Settings. Windows/macOS need Linux
container mode. First publication creates a private package: set **Packages → wfform →
Package settings → Public**, connect it to the source repo and allow its Actions write
access. Public pulls need no login. Publisher uses job-scoped `GITHUB_TOKEN` after the
same human release approval; tags are immutable. [GHCR is currently free](https://docs.github.com/en/billing/concepts/product-billing/github-packages);
Actions/artifacts have separate limits. Configuration is not proof an image exists.

## Build and run locally

Requires Docker/Compose, Make/Bash and pinned Flutter/Dart. OpenSSL is only for TLS.

```sh
make deps
make image
make up
make check
# After source changes: make image, then make restart
make logs
make down
```

`make image` uses isolated container build directories without replacing the running
Dart-host build. `make down` removes only this Compose project, not browser data.
`HTTP_PORT=8081 make up` changes loopback port; use the same value for check/restart.
A new port means a separate browser history origin. Runtime is non-root, read-only,
capability-dropped, with bounded resources/tmpfs. No host service/firewall changes.

## Credentials and asset ownership

`deploy/package.dart` accepts only verified manifest-listed public files plus public
nginx config, rejecting symlinks, corrupt sizes/hashes and recognizable credentials.
Dockerfile uses the generated context, never `COPY .` from the repository. Its pinned
nginx base uses the [official ECR Public mirror](https://gallery.ecr.aws/docker/library/nginx),
avoiding Docker Hub shared-runner quotas. Review digest changes deliberately.

An optional explicit read-only runtime mount is supported:

```sh
WFFORM_CONFIG_FILE="$PWD/config/local.json" make up
WFFORM_CONFIG_FILE="$PWD/config/local.json" make check
```

Use restart when adding/removing a mount. Only `/config/local.json` is served, with
no-store and no access logging; without a mount it returns 404. It never enters image
or PWA cache. Browser users can read delivered keys; prefer each user's Settings key.

## Local TLS and headers

```sh
make tls.cert
make tls.up
make tls.check
```

These create/preserve project-local 30-day localhost certificates in ignored `.local/tls`
and expose **https://localhost:8443** alongside HTTP. No trust-store install or insecure
verification bypass. Production certificate issuance/renewal/ingress is operator work.
Do not claim public TLS acceptance from this local check.

[headers.conf](../../deploy/nginx/headers.conf) owns CSP: bounded script/connect origins,
exact hashes for fixed inline analytics/bootstrap snippets, WebAssembly permission and
Flutter-required style-only inline permission. Keep hash tests aligned after snippet
edits. Roboto/Roboto Mono are bundled; remote glyph fallback remains permitted but is
not guaranteed offline. Clipboard self permission supports Flutter paste while browser
consent/secure-context rules still apply.

Security headers apply on successes/errors. Flat assets/entrypoints/config use no-store;
the verified worker owns offline caching. Missing assets return real 404s, never SPA
HTML. TLS-only HSTS begins at one day; expand only after validating real deployment.
Do not invent scanner grades or add isolation headers without compatibility evidence.

`make check` verifies nginx config, non-root/no-baked-key behavior, headers/MIME, denied
methods/files and every shell asset's bytes/hash. `tls.check` adds certificate/HSTS
checks. Real Flutter rendering, PWA updates and live API/CORS need a browser.
