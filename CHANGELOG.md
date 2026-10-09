# 🌊 Changelog

User-visible changes to wfform are recorded here, starting with 0.3.0.

## [Unreleased]

### ➖ Removed

- 🤖 Routine delivery no longer starts AI tasks, merges PRs, opens promotions or
  back-merges, or dispatches releases. Maintainers coordinate these steps
  explicitly; protected PR checks and the final human deployment approval remain.

### ✨ Added

- 🐳 Approved releases can publish a Linux amd64 web container to GitHub Container
  Registry under a plain SemVer tag, with cached dependencies, verified
  public assets and no extra registry secret. Existing version tags cannot be replaced.

### 🩹 Fixed

- 📦 Container builds pull the identical pinned nginx image from Docker's official
  ECR Public mirror, avoiding Docker Hub's shared-runner anonymous pull limit.
- 🛠️ Container packaging uses the runner's bundled Docker builder, removing an
  additional Docker Hub image pull before builds can start.

## [1.0.0] - 2026-10-09

📦 Published through the reviewed release workflow with human production approval.

### ✨ Added

- 🤖 Routine delivery for authorized Copilot tasks, PR checks, auto-merge and
  release promotion, with protected branches and resolved conversations.
- ✅ One final human deployment approval authorizes automatic SemVer tagging,
  verified packages, website publication and a back-merge PR.

- 🧪 Runnable MCP and local CLI playground with safe fixtures and a short walkthrough.
- 🌿 Gitflow branches, guarded agent publication through `make git`, plain SemVer release packages and free quality/security reports.
- 🤖 MAI-Code-1.1-Flash is the default Copilot task model, verified by a completed live trial; the owner’s ordered alternatives replace costly automatic Codex selection.

- Model-specific parameter controls with official explanations, validation, saved overrides and remote defaults when unset.
- Optional Streamable HTTP MCP connections, per-conversation tools, approval before every call, streamed tool exchanges and saved tool results.
- wfformcomp: an authenticated local Dart companion for configured commands and existing stdio MCP servers, with optional hosting of the same Flutter web build.
- A plain-language tools, MCP and wfformcomp guide available directly from Tools.
- Windows x64 companion executable/archive packaging and native Windows CI checks; the graphical installer and native acceptance remain separate release gates.

### 🔄 Changed

- ⚡ Quality, security and native tests run only on develop PRs and hotfix PRs
  into main. Promotions reuse verified source evidence; pinned tool and
  dependency caches reduce repeated setup, and security scans run once.
- 🖥️ Tools are available on desktop computers; phones/tablets show a faded control with an explanation while ordinary chat and saved settings remain usable.
- 📋 Copy actions are limited to essential messages, code, files and diagnostic reports.
- 📦 Web deployment uses flat assets and verified PWA caches instead of __releases folders. Release and tag names use plain MAJOR.MINOR.PATCH.

- Replaced the W logo with Open Cradle: an open folded band around two linked AI nodes. Updated the ten companion symbols, favicons and launcher artwork with matching rounded shapes and light/dark variants. All 40 PNGs now have fully transparent backgrounds, including iOS and legacy maskable exports; the PWA selects general-purpose transparent icons.
- Default output reserve is now a local context estimate; normal chat no longer implicitly sends max_tokens or enables reasoning.
- Tool exchanges preserve opaque reasoning details and never replay actions after interruption or reload.
- HTTP redirects are disabled to keep connection credentials at their configured endpoint.
- Structured data shares readable previews across tool approvals/results, diagnostics, code blocks and files, with exact original content retained for copying and export.

### 🔒 Security

- 🔐 Automation and website credentials use separate environments restricted to
  `main`; PR checks receive neither credential. Published tags and assets cannot
  be silently replaced on a retry.

### 🐛 Fixed

- 🪟 Windows source launches recognize both Dart runtime executables and read
  the launch gate asynchronously, preserving queued MCP bytes on Windows pipes.
  The trusted helper keeps its runtime environment while configured tools retain
  explicit environment isolation and literal arguments. Empty Windows tool
  environments use a non-secret compatibility marker to avoid launch errors.
- 📡 Oversized companion requests receive their HTTP 413 response before the
  upload stream is cancelled, including on Windows.
- 🌿 Fully validated PRs merge directly through GitHub protection when ready,
  avoiding an invalid attempt to enable auto-merge on an already mergeable PR.
- 🔐 Windows credential setup applies only the intended owner and access rules,
  without depending on inherited PowerShell module paths, while retaining strict
  validation that other users cannot access the file.
- 🌿 Release verification retains strict source evidence when GitHub removes
  workflow-to-PR links after merging, rejecting ambiguous or retargeted histories.

## [0.3.0] - 2026-10-09

### 🔄 Changed

- Replaced the main logo with a rounded W wrapping a lavender module, using
  warm neutrals and restrained purple accents.
- Added a matching family of ten icons for Models, Chat, History, Documents,
  Settings, Diagnostics, Context, Chats, Drafts, and Archived across navigation,
  controls, and dialogs.
- Made app artwork transparent and adapted its outlines and accents to light
  and dark themes, including filled and disabled controls.
- Updated browser-tab favicons, installed-app icons, and public-page branding.
  Browser tabs now have matching light and dark icon variants.
- Preserved visible labels and selection checkmarks, with wrapping icon labels
  that remain usable on narrow screens at 200% text size.
