# Project operations

This directory contains the installed agent-workspace operations, implemented with Bash and Python's standard library. They are development/repository tools, not part of the Flutter application. Application build and deployment commands use Flutter, Dart and shell directly; no Python application server or extra application stack is introduced.

## Ownership

| Location | Purpose |
| --- | --- |
| `xops/agent/` | Bootstrap/recovery, captured command execution and tracking append scripts |
| `xops/lib/log.sh` | Shared shell logging |
| `xops/makefile/` | Repository tracking, human git workflow, roadmap and CodeGraph dispatchers |
| `Makefile` | The single command entry point for repository operations, Flutter checks/build/serve and nginx deployment |
| `tool/` | Dart release assembly, static serving, PWA fixtures, measurements and repository checks |
| `deploy/scripts/app.sh` | Container lifecycle and optional local TLS; calls Docker Compose with validated paths |
| `deploy/package.dart` | Validates release integrity and builds a credential-free Docker context |
| `deploy/release.dart` | Includes public nginx policy in PWA identity so cached headers update safely |
| `deploy/check.dart` | Loopback HTTP/HTTPS health, header and immutable-asset checks |

The original framework scaffolder is not installed in this project. Do not add an `xops/init` path or rerun an imagined local scaffold command. CodeGraph is enabled: `make codeg` initializes or syncs the local index using the pinned `xops/agent/codegraph.sh` launcher. `make codeg.check` performs bounded real MCP/Dart queries and verifies ignored-file exclusions. The launcher keeps its package cache under ignored `.local/codegraph/`; no global installation is needed. See [MCP setup](../docs/guides/MCP_SETUP.md) for client configuration and live connection checks.

## Commands

`make help` lists all targets from the root Makefile. Daily app commands are `make deps`, `format`, `analyze`, `test`, `repository.check`, `verify`, `build` and `serve`. Container commands are `make image`, `up`, `down`, `restart`, `logs`, `check` and `tls.cert`, `tls.up`, `tls.check`, `tls.down`. See [Docker deployment](../docs/guides/DOCKER.md) for credential handling, ports and TLS limits.

Repository operations remain `make track.add`, `track.list`, `roadmap.status`, `git.dry` and the human-only `make git`. Agents do not commit or push; delegated agents return evidence to the coordinating parent, who performs the authorized tracking/staging pass.

## Runtime helpers

- [session-bootstrap.sh](agent/session-bootstrap.sh) reports the working tree, tracking and recovery state, including a fresh repository with no commits.
- [safe-run.sh](agent/safe-run.sh) records command/output/exit evidence before returning; use it for builds and verification that must survive interruption.
- [tracking_append.sh](agent/tracking_append.sh) validates and appends tracking rows.
- [run-with-retry.sh](agent/run-with-retry.sh) is a bounded retry wrapper for appropriate repository tooling. It does not authorize automatic retry of application chat requests.

Treat every non-zero exit as a result to investigate. Repeated commands are not universally idempotent: image builds update artifacts, certificate generation deliberately refuses replacement, tracking appends records, and `make git` changes remote state. Preserve prior and concurrent work.

## Adding a target

Keep targets thin and document them with a `##` help line. Repository framework operations belong in `xops/makefile/` and use its existing standard-library helpers. Flutter/application tooling belongs in `tool/` or `deploy/`, using Dart or shell and existing dependencies. Add tests for new behavior, run relevant gates and keep application logic out of generic scaffold operations. Do not add another stack merely to dispatch a command.
