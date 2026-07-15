# pi-list-tools

A [Pi](https://pi.dev) coding-agent extension that prints a **canonical, verbatim list of every tool** configured in the current session — built-in, extension, and SDK — including the exact text the model sees (descriptions, per-parameter descriptions, prompt guidelines, and source metadata).

Pi has no native flag for this: `pi --help` prints only a short static list of built-in tool *names* and omits extension/package tools. This extension surfaces Pi's live tool registry (`pi.getAllTools()`).

## Install

Copy `list-tools.ts` into an auto-discovered extensions directory:

```bash
cp list-tools.ts ~/.pi/agent/extensions/        # global (all projects)
# or
cp list-tools.ts .pi/extensions/                # project-local
```

Or register it explicitly in `~/.pi/agent/settings.json`:

```json
{ "extensions": ["/absolute/path/to/list-tools.ts"] }
```

## Usage

```bash
pi --list-tools                 # table overview (default), then exit
pi --list-tools verbose         # exhaustive markdown (everything the model sees)
pi --list-tools json            # exhaustive JSON (full parameter schemas + sourceInfo)
pi --list-tools=verbose         # equals form also works
pi --list-tools --tools-filter web,bash   # filter by name substrings (any mode)
pi --show-tool bash             # exhaustive output for a single tool
```

Inside a running session:

```
/tools [table|verbose|json] [substring]
/show-tool <name>
```

### Output modes

| Mode | What it is |
|------|-----------|
| `table` (default) | Terminal-aligned overview table: **Tool**, **Extension**, **Params**, and **Description**. Cells wrap to the terminal width; `*` marks required params. |
| `verbose` | Exhaustive Markdown grouped by extension: full description, every parameter with type/required/description, enum values, and all prompt guidelines. |
| `json` | Exhaustive JSON: full parameter schemas, prompt guidelines, and `sourceInfo`. |

The **Extension** column identifies each tool's origin: `(built-in)`, `pi-web-access (git)`, `pi-codex-goal (npm)`, etc.
The default table is sorted by extension first, then tool name.

### `--no-extensions`

With `pi --no-extensions`, Pi loads only built-in tools, so the output shows only those. Note that `--no-extensions` also disables auto/settings-discovered extensions, so load this one explicitly in that case:

```bash
pi --no-extensions -e /path/to/list-tools.ts --list-tools   # builtin-only
```

## Pipeable

Output is written to real stdout (fd 1) and flushed in full, so it composes with standard tools:

```bash
pi --list-tools | grep web_search
pi --list-tools json | jq '.[].name'
pi --list-tools verbose | less
```

## Development

```bash
npm install      # installs pinned pi + typescript + @types/node
npm run typecheck
npm test         # runs the bash test suite in test/run.sh
```

### Tests

`test/run.sh` is a dependency-free bash suite. It runs pi with `--no-extensions -e list-tools.ts` so results are **deterministic on any machine** (only the 7 built-in tools plus this extension are loaded), and needs **no API key or network** (the extension exits during `session_start`, before any model call).

Coverage includes:

- all three modes (table / verbose / json) and both flag forms (`x verbose`, `x=verbose`)
- output lands on **stdout**, not stderr (original bug)
- **>64KB piped output is not truncated** (partial-`writeSync` bug), with a `test/fixtures/big-emitter.ts` fixture that emits a 200KB payload
- valid JSON with `description` / `parameters` / `sourceInfo` and per-parameter descriptions
- `--show-tool` including the not-found + suggestion path
- `--tools-filter`
- regression: the extension stays silent when `--list-tools` is absent

## CI

GitHub Actions (`.github/workflows/ci.yml`) type-checks the extension and runs the suite on Node 20 and 22 for every push and pull request. No secrets required.

## License

MIT
