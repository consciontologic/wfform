# Tools, MCP and wfformcomp

Ordinary chat needs only your OpenRouter key and a free model. Tools are optional
program actions, such as searching code or reading Git status. An MCP server offers
tools; **wfformcomp** connects local programs/stdio servers to the browser.

**Tools are desktop-only.** Phones/tablets show a faded control explaining this;
ordinary chat still works and saved choices remain ready for your next desktop session.
Open this guide in **Tools → How to use tools**.

## Connect a server

| What you have | Connection |
|---|---|
| Remote MCP web endpoint | Connect directly in Tools; no companion |
| Local Streamable HTTP MCP | Connect its loopback endpoint if browser access is allowed |
| A stdio MCP server or local CLI | Configure [wfformcomp](wfformcomp.md), then connect to it |

1. Add your OpenRouter key in **Settings** and select a free model supporting tools.
2. Open **Tools → Add a connection**. Enter a name, full MCP endpoint and its bearer/
   pairing token if required. This token is separate from your OpenRouter key.
3. Click **Connect**, check only the tools needed for this conversation, and close.
4. Ask for the action, e.g. **“Use repository_status to list changed files.”**
5. Review the server/tool/arguments in **Run …?** and select **Allow once** or **Deny**.
   Closing the dialog denies. Each call needs approval; a turn allows four tool rounds.
6. Expand the request or **View tool result** to inspect the saved exchange.

Use the server's actual MCP endpoint, not its ordinary website. Tool support does not
force a model to call a tool; name the tool and desired action in the prompt.

## Local examples

Download the Linux or Windows portable companion from [releases](https://github.com/consciontologic/wfform/releases),
extract it and follow [companion setup](wfformcomp.md). Graphical installers and macOS
are planned. It begins with no tools enabled; installation does not grant whole-PC access.

- With the Git example configured, check **repository_status** and ask:
  **“Use repository_status to check my project without changing files.”**
- With CodeGraph configured, check **codegraph__codegraph_explore** and ask:
  **“Use CodeGraph to find where tool arguments are validated. Name the source file.”**
- A configured isolated code runner can execute code only through approved tool calls.
  Python is not built in; a code block in chat never runs itself. Choose the runner's
  working folder/limits before exposing it.

Developers can use the [example MCP/CLI playground](https://github.com/consciontologic/wfform/tree/develop/examples/tools_playground).
Descriptions, arguments and results are sent through OpenRouter to the selected model;
code-search output can include your source code.

## Reconnect and stop

History saves complete tool exchanges and selected tools. Connection names/URLs are
remembered; bearer tokens stay in memory only. After reload use **Edit / reconnect**,
enter the token and Connect. Keep the companion running while using its tools.

Uncheck tools for ordinary chat. **Remove unavailable tools** clears disconnected
selections; **Disconnect** ends the browser connection; **Forget** removes its saved
name/address. Interrupted/unknown outcomes are never replayed: inspect actual files or
program output before deliberately trying again.

## Parameters

Open **Parameters**. Leave **Override** off for provider defaults; enable a supported
field, enter a value and **Apply**. **Reset all** or field reset removes overrides after
Apply. Example: supported `temperature: 0.2` or an explicit output limit. Each field
includes an explanation and official reference. Connecting/checking tools builds the
`tools` parameter; there is no need to paste its JSON manually.

Explicit `0`, `false` and empty lists are preserved. App-owned model/message/stream/
routing fields and paid hosted search cannot be overridden. `structured_outputs` maps
to `response_format`; legacy `include_reasoning` maps to `reasoning.exclude`. Unsupported
new parameters explain their status. Default context reserve is a local estimate,
not a hidden `max_tokens` override.

## Troubleshooting and compatibility

Direct connections support **Streamable HTTP** JSON/SSE, session headers and paginated
tools, protocol `2025-11-25`, `2025-06-18`, `2025-03-26`. OAuth, legacy HTTP+SSE,
sampling and elicitation are unsupported. Use a compatible endpoint/adapter.

- No tools: configure companion commands/allowed MCP tools, restart and reconnect.
- Authentication failure: check the connection token; never put it in the URL.
- Browser blocking: server must permit the exact wfform origin, Authorization,
  Content-Type and MCP headers, exposing `MCP-Session-Id`. Allow local-network access
  if prompted. Use HTTPS or loopback HTTP (`localhost`/`127.0.0.1`); literal HTTP IPv6
  addresses are not accepted.
- Timeout/unknown outcome: inspect effects first; restart/reconnect explicitly.

Model availability varies; advertised support is not proof a route works.
References: [parameters](https://openrouter.ai/docs/api_reference/parameters),
[tool calling](https://openrouter.ai/docs/guides/features/tool-calling).
