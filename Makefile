# ┊┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃
#  wfform application, deployment and repository operations
# ──────────────────────────────────────────────────────────────
#  Repository targets dispatch to xops/makefile/<module>.py (stdlib-only).
#  Flutter/Dart and nginx deployment targets share this single Makefile.
#
#  Convention:
#    • daily verbs are short  : help, git
#    • everything else uses   : domain.action  (track.add, git.dry, roadmap.status)
# ┊┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃

PYTHON ?= python3
XOPS   := $(PYTHON) xops/makefile

# Tracking append defaults (override on CLI: make track.add ACTION=note SUMMARY="...")
ACTION  ?= note
STATUS  ?= completed
SCOPE   ?= general
AGENT   ?= human
SUMMARY ?=
REFS    ?=
RUN_ID  ?=

.DEFAULT_GOAL := help

.PHONY: help git git.dry track.add track.list roadmap.status codeg codeg.check

## help              List all available targets
help:
	@grep -h -E '^## ' $(MAKEFILE_LIST) | sed 's/^## /  make /' | sort

## git               Commit pending tracking rows as conventional commits + push
git:
	@$(XOPS)/git_ops.py push

## git.dry           Preview what `make git` would commit and push (read-only)
git.dry:
	@$(XOPS)/git_ops.py dry

## track.add         Append a row to docs/tracking/tracking.csv (vars: ACTION STATUS SCOPE AGENT SUMMARY REFS RUN_ID)
track.add:
	@$(XOPS)/track_ops.py add \
		--action="$(ACTION)" --status="$(STATUS)" --scope="$(SCOPE)" \
		--agent="$(AGENT)"   --summary="$(SUMMARY)" --refs="$(REFS)" \
		$(if $(RUN_ID),--run-id="$(RUN_ID)",)

## track.list        Show recent tracking rows (last 20)
track.list:
	@$(XOPS)/track_ops.py list

## roadmap.status    Summarize ROADMAP.md checkbox progress
roadmap.status:
	@$(XOPS)/roadmap_ops.py status

## codeg             Initialize or update the CodeGraph index
codeg:
	@$(XOPS)/codegraph_ops.py update

## codeg.check       Verify real CodeGraph MCP/Dart queries and ignored-file exclusions
codeg.check:
	@$(PYTHON) xops/agent/check_codegraph.py

# Flutter/Dart application and isolated nginx runtime.
.PHONY: deps format analyze test verify repository.check build build.public serve image up down restart logs check tls.cert tls.up tls.check tls.down
## deps              Resolve locked Flutter dependencies
deps:
	flutter pub get
## format            Check Dart formatting without rewriting files
format:
	dart format --output=none --set-exit-if-changed lib test tool deploy
## analyze           Analyze Flutter/Dart source and tools
analyze:
	flutter analyze
## test              Run deterministic Flutter tests (live checks remain opt-in)
test:
	flutter test --reporter expanded
## repository.check  Check repository secret/config hygiene
repository.check:
	dart run tool/check_repository.dart
## verify            Run formatting, analysis, tests and repository checks
verify: format analyze test repository.check
## build             Build complete versioned release PWA for Dart host
build:
	dart run tool/build.dart
## build.public      Build a credential-free release for https://wfform.com/
build.public:
	dart run tool/build.dart --public --output=build/publish-web --base-href=/
## serve             Serve the release on localhost:8765
serve:
	dart run tool/serve.dart --port=8765
## image             Build isolated credential-free PWA and official nginx image
image:
	deploy/scripts/app.sh image
## up                Start nginx on localhost:8080 (run make image first)
up:
	deploy/scripts/app.sh up
## down              Stop only this project's nginx container
down:
	deploy/scripts/app.sh down
## restart           Recreate nginx with the latest built image; browser storage stays intact
restart:
	deploy/scripts/app.sh restart
## logs              Follow bounded nginx logs, without query strings or secrets
logs:
	deploy/scripts/app.sh logs
## check             Verify nginx config, non-root image, health, headers and PWA integrity
check:
	deploy/scripts/app.sh check
## tls.cert          Generate a project-local self-signed localhost certificate
tls.cert:
	deploy/scripts/app.sh cert
## tls.up            Start localhost HTTPS:8443 alongside HTTP:8080
tls.up:
	TLS=1 deploy/scripts/app.sh up
## tls.check         Verify HTTP and HTTPS with the project certificate
tls.check:
	TLS=1 deploy/scripts/app.sh check
## tls.down          Stop the TLS-enabled project container
tls.down:
	TLS=1 deploy/scripts/app.sh down
