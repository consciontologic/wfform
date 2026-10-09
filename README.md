# wfform

**Wrapper for Free Open Router Models** — a Flutter web app for discovering and chatting with OpenRouter’s free models.

**[Open wfform](https://wfform.com/)** · [Tools quick start](docs/tools.md) · [Documentation](docs/README.md) · [Release notes](CHANGELOG.md)

- Search the live free-model catalog and inspect pricing, capabilities and recent availability.
- Stream responses, edit and resend messages, and attach supported text, source files or media.
- Set supported model parameters, with remote defaults when unset, and connect optional MCP tools with approval for each call.
- Use the optional [wfformcomp](docs/wfformcomp.md) to connect configured local programs and stdio MCP servers.
- Resume unsent drafts and saved chats; archive, restore, export and import conversations.
- Use responsive layouts, a resizable desktop sidebar, light/dark themes and text sizes up to 200%.
- Install the PWA for an offline app shell and cached history/catalog. Chat requires a connection.

The browser calls OpenRouter directly. There is no application backend or API proxy. Free-model availability and account limits depend on OpenRouter; the app does not silently switch models or use paid fallbacks.

## Start chatting

1. [Open wfform](https://wfform.com/), open **Settings**, and add your OpenRouter API key.
2. Choose a free model in **Models**, type a message, and send it.
3. Want the model to use your tools? Follow the [simple tools, MCP and wfformcomp guide](docs/tools.md). Ordinary chat needs no companion. Compatible web MCP services connect through **Tools**; local programs and stdio MCP servers use **wfformcomp**.

## Run locally

Requires **Flutter 3.38.10 stable / Dart 3.10.9**, Git and Make.

```sh
git clone https://github.com/consciontologic/wfform.git
cd wfform
make deps
make build
make serve
```

Open [localhost:8765](http://localhost:8765/) and save your OpenRouter API key in **Settings**. This browser remembers it until you replace or clear it. Optional development configuration uses ignored `config/local.json`, copied from `config/example.json`. Browser-delivered credentials are visible to that browser’s user. Conversations stay in browser-local storage; export a backup before clearing site data or changing origins.

For hot-reload development, run `flutter run -d chrome --web-port=8080`. Test installation and offline behavior using the release build above.

## Checks and deployment

```sh
make verify        # format, analysis, deterministic tests, repository checks
make build.public  # credential-free release in build/publish-web
```

`make help` lists all targets. [Gitflow](docs/guides/GITFLOW.md) covers manual
Copilot task assignment and protected PR promotion. Start a release explicitly
from **Actions → Packages and release → Run workflow** on `main`; the owner
approves the final **production deployment** before CI publishes verified
packages and the website. Follow the [release setup](docs/guides/CI_CD.md#one-time-release-setup).
Future approved releases can also publish a versioned GHCR web container. See the
[Docker guide](docs/guides/DOCKER.md) for published-image usage and local builds.

## Learn more

- [Setup, configuration and optional checks](docs/guides/README.md)
- [Model discovery](docs/catalog.md), [chat](docs/chat.md) and [attachments](docs/multimodal.md)
- [History and backups](docs/history.md), [file rendering](docs/file-rendering.md) and [PWA behavior](docs/pwa.md)
- [Architecture](docs/code/ARCHITECTURE.md) and [interface behavior](docs/design/DESIGN.md)
- [Verification reports](docs/reports/README.md), [roadmap](docs/planning/ROADMAP.md) and [contributor instructions](AGENTS.md)

During 0.x development, minor releases may change application interfaces; review the release notes before upgrading.

Web is the verified release target. Android/iOS host identifiers are configured; [native platform support remains limited](docs/native-platforms.md).

## 🌿 Contribute and experiment

- [Gitflow and Copilot delivery](docs/guides/GITFLOW.md): feature, bugfix, hotfix, PR and plain SemVer release workflow.
- [Tools playground](examples/tools_playground/README.md): start a real example MCP server and local program, then try the sample prompts.
- [Changelog](CHANGELOG.md): user-facing release notes.

Version **1.0.0** is available in [GitHub Releases](https://github.com/consciontologic/wfform/releases/tag/1.0.0).
GHCR image publication begins with a future approved release. Tools require a desktop computer; normal
chat remains available on phones and tablets.
