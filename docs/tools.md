# Tools, MCP and wfformcomp: a quick start

You can chat normally without installing anything. Tools are optional extras that let a model ask another program to do something, such as search your code or check a project’s Git status.


**Tools are desktop-only.** On a phone or tablet the faded **Tools** control
explains why. Chat works normally, and saved tool choices stay ready for your
next desktop session; they do not run from a mobile device.

- **Tool:** one action the model can request, such as `repository_status`.
- **MCP server:** a program that offers a list of tools.
- **wfformcomp:** the optional companion on your computer. It connects wfform to local programs and local MCP servers.

You choose the tools. The model requests an action. You approve it. wfform sends the result back to the model so it can answer. You can reopen this guide inside **Tools → How to use tools**.

## 1. Start with ordinary chat

1. Open wfform and add your OpenRouter API key in **Settings**.
2. Choose a free model in **Models**.
3. Type a message and send it. No tool connection is needed.

Example: **“Explain what an MCP server does in two sentences.”**

## 2. Choose how to connect your tools

| What you have | What to use |
|---|---|
| An MCP service with a web address | Connect it directly in **Tools**. No companion needed. |
| A local MCP server with an HTTP endpoint | Connect its `http://localhost:…/mcp` address in **Tools**, if it permits browser connections. |
| A local MCP server launched with a command, such as CodeGraph | Run it through **wfformcomp**, then connect to the companion. |
| A command-line program on your PC | Add a specific command to **wfformcomp**, then connect to the companion. |

An MCP server’s normal website is not necessarily its MCP endpoint. Use the endpoint and token supplied by its owner. A server described as **stdio** uses a local process instead of a web address; that is the companion route.

## 3. Connect an MCP service

1. Select a model that supports tools. If it does not, **Tools** will tell you to choose a compatible model.
2. Open **Tools** below the message box.
3. Under **Add a connection**, fill in:
   - **Connection name:** a label you will recognize, such as `My project tools`.
   - **MCP endpoint:** the server’s full MCP address.
   - **Bearer / pairing token (optional):** the server’s token, if required. This is separate from your OpenRouter API key.
4. Click **Connect**. The server’s tools appear with checkboxes.
5. Check only the tools you want to use in this conversation, then close the window.
6. Ask for an action using one of those tools.

For example, if your server offers a documentation search tool: **“Use the documentation search tool to find how to export a CSV. Summarize the steps and include the source.”**

The server must support **Streamable HTTP** and allow connections from the address where you opened wfform. These are server settings. See “If something does not work” below.

## 4. Use tools on your own computer

The Linux companion is currently a portable preview with manual setup. Windows build and ZIP packaging support has been added, but its native Windows CI checks must pass before a maintainer can publish a Windows download; that native run has not been verified here. A graphical installer is still planned; macOS is deferred. For an available package, extract it and follow the one-time setup in **Tools → Companion setup** or the [companion guide](wfformcomp.md).

Start **wfformcomp** with the local commands or MCP servers you want to make available. It gives you an MCP address; use that address and its pairing token in the same **Tools** form above.

The companion starts with **no tools enabled**. Installing it does not give the model access to your entire PC. Add the programs and actions you intend to use. The [companion setup guide](wfformcomp.md) includes copyable configuration examples for a read-only Git command and CodeGraph, plus platform and build instructions.

### Example: search your project with CodeGraph

After CodeGraph has indexed your project and is configured in the companion:

1. Connect to wfformcomp in **Tools**.
2. Check `codegraph__codegraph_explore`.
3. Ask: **“Use CodeGraph to find where this project validates tool arguments. Explain what it checks and name the source file.”**
4. Review the proposed query and approve it. The model receives the actual search result and can answer from your code.

The companion opens its own CodeGraph process using the configured installation and project index. A CodeGraph session already running for another app can stay open.

### Example: use a local CLI command

With the guide’s `repository_status` tool configured:

1. Check `repository_status` in **Tools**.
2. Ask: **“Use repository_status to check my project. List the changed files without changing anything.”**
3. Approve the call. The companion runs the configured `git status --short` command, and the model explains its output.

### What about running code?

A tool can run a program or a configured code runner. For example, with a Python runner already configured, you could ask: **“Run Python to make a CSV containing the numbers 1 to 10 and their squares. Save it in the runner’s output folder.”**

A Python tool is not built in, and a code block in chat does not run by itself. Whoever sets up the runner must choose its working folder and limits; use an isolated runner for model-written code. Every requested tool call still needs your approval.

## 5. Approve the action and read the result

When the model requests a tool, a **Run …?** window shows the server, tool and arguments—the inputs it wants to send.

- Choose **Allow once** to run that one call.
- Choose **Deny** to decline. Closing the window also declines it.
- Expand the tool request or **View tool result** in the conversation to inspect what happened. The result is saved with the chat.

A model may need more than one tool call. Each needs approval; one turn allows up to four tool rounds. Tool descriptions, arguments and results are sent to the selected model through OpenRouter. For CodeGraph, this can include the source code returned by its search.

## 6. Reopen a chat or disconnect

Chat history remembers tool calls, results and selected tools. Connection names and addresses are remembered too. Pairing/bearer tokens are kept only for the current browser session.

After a reload, open **Tools → Edit / reconnect**, enter the token again if needed, and click **Connect**. Keep wfformcomp running while using local tools.

To go back to ordinary chat, uncheck the tools. For a disconnected selection, **Remove unavailable tools** clears it. **Disconnect** stops the browser connection; **Forget** also removes its saved name and address.

If a call was interrupted and says its outcome is unknown, check what the tool actually did before asking it to run again. wfform does not automatically repeat it.

## Optional: change model parameters

Open **Parameters** below the message box. Leave **Override** off to use the provider’s default. Turn it on, enter a value, and choose **Apply** to save it for this conversation. To remove overrides, choose **Reset all** or a field’s **Reset to provider defaults**, then **Apply**.

For example, if the model supports **temperature**, try `0.2` for a more focused response. If it supports **max_tokens**, you can set an output limit. Each setting includes its explanation and an official OpenRouter reference. Available settings depend on the selected model.

You do not need to paste a `tools` JSON object: connecting a server and checking its tools builds that parameter for you.

## If something does not work

| What you see | What to do |
|---|---|
| The model does not support tools | Select another model that advertises tool support. You can still use the current model for ordinary chat. |
| Connected, but no tools to check | Check that the server offers tools. For wfformcomp, add a command or an allowed MCP tool to its configuration, then restart it and reconnect. |
| Tools appear, but the model only replies in text | Name the tool and the action in your prompt. Tool support does not force a model to use it. |
| Authentication or access failed | Check the connection’s token and the server’s permitted browser address. Do not put a token in the endpoint URL. |
| The browser blocks the connection | The server must allow your exact wfform address through CORS. For local tools, allow local-network access if the browser asks. An HTTPS endpoint or an HTTP endpoint on `localhost` / `127.0.0.1` is required. |
| Tools became unavailable after reload | Use **Edit / reconnect**, enter the token again, and click **Connect**. |
| A local tool times out or its outcome is unknown | Inspect its output/files first. Resolve the local problem, restart wfformcomp if needed, then reconnect. The old action is not replayed. |

## Compatibility details

Direct connections support MCP Streamable HTTP JSON/SSE responses, session headers and paginated tool discovery, with protocol versions `2025-11-25`, `2025-06-18` and `2025-03-26`. OAuth sign-in, legacy HTTP+SSE, sampling and elicitation are not currently supported. A service requiring these needs a compatible endpoint or adapter. Literal HTTP IPv6 addresses are not accepted; use `localhost` for a loopback server that resolves over IPv6.

A server administrator must allow the exact browser origin, `Authorization`, `Content-Type` and MCP request headers, and expose `MCP-Session-Id`. Changing a model parameter cannot bypass browser connection restrictions.

Parameter overrides preserve explicit `0`, `false` and empty lists. Unsupported newly advertised parameters show an explanation until supported. App-owned model/message/stream/routing fields and paid hosted search cannot be overridden. `structured_outputs` is represented through `response_format`; legacy `include_reasoning` is normalized to `reasoning.exclude`. The Context output reserve is a local estimate until explicitly changed. Ordinary requests do not silently add `max_tokens` or reasoning settings; health probes have their own small limit.

Saved chats and exports retain the complete request/result exchange, including reasoning details supplied by the provider. Excluding old context preserves whole tool exchanges. Interrupted calls are marked as interrupted and never run automatically; turns that requested tools do not offer an automatic replay or ordinary Retry.

See the [verification report](reports/connected-tools-verification.md) for tested models and actual MCP/CLI examples. Model availability can change; advertised tool support alone does not guarantee a working route.

Official references: [OpenRouter parameters](https://openrouter.ai/docs/api_reference/parameters) and [tool calling](https://openrouter.ai/docs/guides/features/tool-calling).
