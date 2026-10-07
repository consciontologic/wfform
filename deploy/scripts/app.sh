#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
export WFFORM_UID="${WFFORM_UID:-$(id -u)}"
export WFFORM_GID="${WFFORM_GID:-$(id -g)}"
if [[ "$WFFORM_UID" == 0 ]]; then
  echo 'Use a non-root WFFORM_UID/WFFORM_GID for the runtime container.' >&2
  exit 64
fi
compose=(docker compose -f deploy/compose.yaml)
if [[ "${TLS:-0}" == 1 ]]; then
  compose+=(-f deploy/compose.tls.yaml)
fi
if [[ -n "${WFFORM_CONFIG_FILE:-}" ]]; then
  [[ -f "$WFFORM_CONFIG_FILE" ]] || { echo 'Runtime config file does not exist.' >&2; exit 64; }
  export WFFORM_CONFIG_FILE="$(realpath "$WFFORM_CONFIG_FILE")"
  compose+=(-f deploy/compose.config.yaml)
fi
case "${1:-}" in
  image) dart run tool/build.dart --output=build/container-input
         dart run deploy/release.dart
         dart run deploy/package.dart
         "${compose[@]}" build ;;
  up) "${compose[@]}" up -d --no-build --wait ;;
  down) "${compose[@]}" down --remove-orphans ;;
  restart) "${compose[@]}" up -d --no-build --force-recreate --wait ;;
  logs) "${compose[@]}" logs --tail=100 -f ;;
  check) "${compose[@]}" exec -T web nginx -t
         "${compose[@]}" exec -T web sh -c 'test "$(id -u)" != 0 && test ! -e /usr/share/nginx/html/config/local.json'
         dart run deploy/check.dart "http://localhost:${HTTP_PORT:-8080}"
         if [[ "${TLS:-0}" == 1 ]]; then
           dart run deploy/check.dart "https://localhost:${TLS_PORT:-8443}" --certificate=.local/tls/cert.pem
         fi ;;
  cert) mkdir -p .local/tls
        [[ ! -e .local/tls/key.pem && ! -e .local/tls/cert.pem ]] || { echo 'Existing TLS material preserved. Move it explicitly before generating replacements.' >&2; exit 64; }
        umask 077
        openssl req -x509 -newkey rsa:3072 -sha256 -nodes -days 30 \
          -keyout .local/tls/key.pem -out .local/tls/cert.pem \
          -subj '/CN=localhost' -addext 'subjectAltName=DNS:localhost,IP:127.0.0.1,IP:::1'
        echo 'Created project-local self-signed certificate; no host trust settings changed.' ;;
  *) echo 'Usage: deploy/scripts/app.sh image|up|down|restart|logs|check|cert' >&2; exit 64 ;;
esac
