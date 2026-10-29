# claude-touchbar

See your Claude sessions on the MacBook Pro Touch Bar: one tile per session, **gray with a spinner while Claude works, blue when it's waiting for you** (finished, asking a question, or needing permission). Each tile shows where the session lives (a terminal icon for Code, a robot for Cowork). Tap a tile to jump to that session.

![Touch Bar with Code and Cowork sessions](docs/touchbar.png)

Works with both kinds of sessions in the Claude desktop app:

- **Claude Code** (the Code tab, and the `claude` CLI): tracked with [Claude Code hooks](https://docs.claude.com/en/docs/claude-code/hooks). Tapping opens the exact session.
- **Cowork**: read from the app's sidebar through macOS Accessibility, since Cowork runs in a VM where your hooks don't reach. Tapping clicks that session's row.

The Touch Bar is drawn by [MTMR](https://github.com/Toxblh/MTMR) (My TouchBar My Rules), an open-source Touch Bar customizer. The layout also keeps music (previous / play-pause / next), brightness and volume buttons on the right.

## Requirements

- A MacBook Pro with a Touch Bar
- The Claude desktop app and/or Claude Code
- `jq` (ships with recent macOS, or `brew install jq`)
- Swift compiler from the Command Line Tools (`xcode-select --install`)
- [Homebrew](https://brew.sh), so the installer can install MTMR for you (or install MTMR yourself)

## Install

```bash
git clone https://github.com/rodrigoleanmote/claude-touchbar.git
cd claude-touchbar
./install.sh
```

The installer:

1. installs MTMR if it's missing (`brew install --cask mtmr`);
2. copies the scripts to `~/.claude/touchbar/` and builds the Cowork reader;
3. adds the hooks to `~/.claude/settings.json` (backup at `settings.json.bak-claude-touchbar`);
4. writes the MTMR layout (your previous one is backed up as `items.json.bak-claude-touchbar`).

Then:

- **If macOS says it can't verify MTMR**, click *Done* (not *Move to Trash*), go to **System Settings → Privacy & Security** and click **Open Anyway**. MTMR is signed by its author but not notarized by Apple.
- **Grant MTMR the Accessibility permission** when asked. It's needed to read Cowork sessions and to click them.
- **For Cowork**, keep one Claude window in **Chat & Cowork** mode (a small one behind the others is fine). The app only builds the Cowork list while that mode is on screen.

Code sessions appear the next time they do something (send a message, run a tool, finish).

## How it works

| Piece | What it does |
| --- | --- |
| `icons/<kind>.png` | One icon per kind of session. Each file adds a kind: the installer gives every Touch Bar position one button per kind. |
| `src/hook.sh` | Claude Code hook. On `UserPromptSubmit` / `PreToolUse` / `PostToolUse` marks the session *working*; on `Stop` / `Notification` marks it *ready*; on `SessionEnd` removes it. Writes one JSON file per session in `~/.claude/touchbar/sessions/` (`kind: "code"`), with the session title and the desktop app's session id. |
| `src/claudebar.swift` | Reads the Claude app's sidebar via Accessibility (only windows in Chat & Cowork mode). Rows marked running become *working*, rows with an unread reply become *ready*. Mirrors them as `cowork-*.json` files (`kind: "cowork"`). Also opens a Cowork session by clicking its row. |
| `src/status.sh N KIND` | Prints the Nth tile for MTMR if the Nth session is of that kind: blue background when ready, gray with a spinner when working. Otherwise prints nothing, and MTMR hides the button. |
| `src/open.sh N` | Tap action: opens a Code session with `claude://claude.ai/epitaxy/<session id>`, or a Cowork session through `claudebar press`. |
| `src/make_icon.py` | Draws the built-in icons (no dependencies). |
| `src/axprobe.swift` | Dev tool: dumps the app's accessibility tree, for fixing the reader when the app changes. |

Tiles keep their position in the order sessions started. Up to 6 tiles; a finished session disappears after 8 hours without activity, a "working" one after 30 minutes of silence (it probably died).

## Adding another tool

Any tool can put sessions on the Touch Bar by writing JSON files to `~/.claude/touchbar/sessions/`:

```json
{ "kind": "mytool", "state": "working", "title": "Deploy staging", "ts": 1793284805, "created": 1793284805 }
```

- `kind`: which icon to use; add a matching white-on-transparent 48×48 PNG as `icons/mytool.png` and re-run `./install.sh`.
- `state`: `working` or `ready`.
- `ts`: last update (Unix seconds). `created` keeps the tile's position stable.
- Delete the file when the session ends.

Tapping a tile of a new kind just brings Claude to the front; to open the session itself, add a case for your kind in `src/open.sh`.

## Limitations

- **Cowork depends on the app's UI.** The reader matches the sidebar by its structure (DOM classes and position), not by labels, so it works in any app language, but an app redesign can break it. Running sessions are detected by the status text, matched in a few languages (`running`, `en ejecución`, …); add yours in `runningWords` in `claudebar.swift`.
- **MTMR 0.27 only supports 16 ANSI colors**, so the blue is a strong one.
- **Gaps between tiles vary a little.** MTMR can't change a button's icon at runtime, so each position has one button per kind and the unused ones are hidden; hidden buttons still leave a bit of spacing.
- MTMR is no longer actively developed, but it still works on macOS 26 (Tahoe).

## Uninstall

```bash
./uninstall.sh
```

Removes the hooks, `~/.claude/touchbar/`, and restores your previous MTMR layout. MTMR itself stays installed (`brew uninstall --cask mtmr`).

## Contributing

Issues and pull requests are welcome, especially:

- status words for more languages;
- fixes when a Claude app update changes the sidebar (run `axprobe` from MTMR to see the new structure);
- support for other Touch Bar tools (BetterTouchTool, Pock).

---

**En español:** muestra tus sesiones de Claude (Code y Cowork) en la Touch Bar: gris mientras trabaja, azul cuando te necesita, y al tocar te lleva a la sesión. Instala con `./install.sh`.

## License

[MIT](LICENSE)
