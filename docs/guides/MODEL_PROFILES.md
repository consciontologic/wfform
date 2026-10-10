# Agent client notes

All clients follow [AGENTS.md](../../AGENTS.md), the same tests and the same Gitflow
publishing/approval rules. These notes concern integration, not claims about model
quality or OpenRouter catalog models.

- **Copilot:** assign concrete scope/base/tests and use the repository's explicit
  [model policy](../../.github/copilot-model-policy.json). Platform restrictions apply.
- **Codex:** native roles/skills are described in [setup](CODEX_SETUP.md); translate
  Copilot metadata into actually available tools.
- **Claude:** [CLAUDE.md](../../CLAUDE.md) delegates policy; keep communication concise.
- **Other/local clients:** verify instruction/tool discovery, keep tasks bounded and
  recover from repository state rather than assuming session memory.

Finish authorized work without repeated permission loops; avoid unrelated refactors,
duplicate files, omitted tests and unverified success claims. Never enable uncontrolled
auto-commit or direct protected-branch writes.
