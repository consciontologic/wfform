---
name: 'wfform static deployment'
description: 'Docker nginx and PWA deployment boundaries'
applyTo: 'deploy/**,Dockerfile,.dockerignore,Makefile*,xops/**,tool/**'
---

# Deployment

- Nginx serves the existing static Flutter release. There is no API proxy.
- Local keys must be excluded from Docker context, image layers, Git and logs.
  A requested runtime config mount is explicit and read-only.
- Headers must work with the built CanvasKit/WASM app and direct OpenRouter
  access. Test actual success/error/static routes and document CSP exceptions.
- Preserve network-only configuration, service-worker update checks, hash-verified
  cached assets and safe draft-preserving updates.
- Public builds use `--public` and must exclude configuration. The authorized
  GitHub workflow publishes to `consciontologic/wfform.com` with a scoped Actions secret;
  preserve unmanaged destination files and tested legacy cached-client migration.
  Version 1.0.0 uses flat deployment files, not __releases directories.
  Read `docs/guides/CI_CD.md` and `docs/seo.md` before changing public deployment.
- Operate only this project's Compose services and ports. Never reconfigure
  host nginx, global Docker or system certificate trust.
- State HTTPS, certificate and external-rating limits honestly; do not call
  local self-signed TLS publicly trusted or promise an unmeasured A+++ grade.
