# 🧰 Play with tools in three steps

This is a tiny, free developer example for **desktop wfform**. It includes an MCP
server, a local program, and sample JSON, YAML and CSV files. Tools are disabled
on phones and tablets; ordinary chat still works there.

You need this checkout and its Dart SDK first. Run commands from the repository
root. `dart` below means the Dart shipped with your Flutter SDK; on a checkout
using the local SDK, use `.local/flutter-sdk/bin/dart` on Linux or
`.local\flutter-sdk\bin\dart.bat` on Windows to start these commands.

## 1. Start it

```sh
dart run examples/tools_playground/start.dart
```

Leave that terminal open. The script creates settings once in
`.local/tools-playground/`, starts the **real wfformcomp**, and prints its MCP
address—normally `http://127.0.0.1:8766/mcp`. It reuses your settings on later runs.
Nothing is installed globally. No extra package or API key is needed to run the
example server.

## 2. Connect it

Open [wfform](https://wfform.com) on a PC, select a free model that supports tools,
then open **Tools → Add a connection**:

| Field | Enter |
|---|---|
| Connection name | `My playground` |
| MCP endpoint | The address printed in the terminal |
| Bearer / pairing token | Open `.local/tools-playground/pairing-token` in your editor and paste its contents here |

Click **Connect**, then check the three tools. The token is private: keep it out
of chat prompts, screenshots and Git. Your OpenRouter key belongs in wfform's
normal **Settings**, separately from this token.

## 3. Ask it something

Try these messages one at a time, then choose **Allow once** when wfform asks:

- **“Use playground__add_numbers to add 17 and 25.”** → `42`.
- **“Use playground__read_sample to read fruit. What colors are listed?”** → red,
  yellow and green from the bundled JSON file.
- **“Use playground__read_sample to read notes. Show the YAML.”** → the bundled
  YAML, with comments and a multiline message.
- **“Run sales_report and tell me the total in dollars.”** → three rows, `$19.50`.

The first two tool types run through the example **stdio MCP server**. The last
tool runs a separate **local Dart CLI program** through wfformcomp. All three are
read-only, accept only narrow inputs, and cannot choose a command or file path.
Sample data returned by a tool goes to the selected model through OpenRouter;
normal model/account limits still apply. Ctrl+C in the terminal stops the server.

## 🛠 Change a sample or build your own tool

| File | What to try |
|---|---|
| [server.dart](server.dart) | See MCP `initialize`, `tools/list`, `tools/call`, input validation and text results. |
| [sales_report.dart](sales_report.dart) | A fixed program that reads the sample CSV and returns JSON. Try `dart run examples/tools_playground/sales_report.dart` directly. |
| [fixtures/fruit.json](fixtures/fruit.json) | Change a fruit, then ask the model to read it again. |
| [fixtures/notes.yaml](fixtures/notes.yaml) | Try comments and multiline YAML in the readable result viewer. |
| [fixtures/sales.csv](fixtures/sales.csv) | Change a quantity, then run the report again. Prices are integer cents. |
| [settings.dart](settings.dart) | The initial allowlist for the MCP server and fixed CLI program. |

Generated settings are in `.local/tools-playground/config.json`; edit that file
and restart to change the port, exact allowed website origins or tools. The
defaults allow `https://wfform.com` and loopback previews on ports 8765 and 8080.
If you move the checkout or SDK, update its absolute program paths. The starter
does not overwrite existing settings.

For another MCP client, launch `dart` with the absolute path to `server.dart` as
its argument. On Windows use the real SDK `dart.exe`, not a `.bat`/`.cmd` wrapper,
inside companion settings. The server also offers `resources/list` and
`resources/read` for `playground://samples/fruit` and `playground://samples/notes`.
**wfform currently exposes MCP tools only**; `read_sample` lets you use those same
files in wfform. This small teaching server is not a production MCP SDK.

## ✅ Check it without a model

```sh
dart run companion/test/example_playground_test.dart
```

The check launches the actual server and local CLI, connects through the real
companion HTTP bridge, checks the results, rejects invalid inputs, and removes
its temporary private settings. It does not make any OpenRouter request.

If **Connect** fails, keep the terminal open, check the endpoint/token, allow your
browser's local-network prompt if shown, and ensure your preview's exact origin
is listed in the generated config. If port 8766 is busy, change `port` in that
file and restart. Never enter the sample server path as a web endpoint.

More: [simple tools guide](../../docs/tools.md) ·
[companion configuration](../../docs/wfformcomp.md).
