# claude-touchbar

See your Claude sessions on the MacBook Pro Touch Bar: one tile per session, with an icon for where it lives (a terminal for Code, a robot for Cowork) that turns **blue when it's waiting for you** (finished, asking a question, or needing permission) and **gray with a spinner while Claude works**. Tap a tile to jump to that session.

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
2. copies the scripts to `~/.claude/touchbar/`, draws the tile icons and builds `claudebar`;
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
| `icons/<kind>.png` | A white glyph per kind of session. The installer turns each into a blue (*ready*) and a gray (*working*) tile icon. |
| `src/hook.sh` | Claude Code hook. On `UserPromptSubmit` / `PreToolUse` / `PostToolUse` marks the session *working*; on `Stop` / `Notification` marks it *ready*; on `SessionEnd` removes it. Writes one JSON file per session in `~/.claude/touchbar/sessions/` (`kind: "code"`), with the session title and the desktop app's session id. |
| `src/claudebar.swift` | `claudebar daemon` runs in the background (MTMR starts it, so it inherits MTMR's Accessibility permission). Every 3s it reads the Claude app's sidebar (windows in Chat & Cowork mode): rows marked running become *working*, rows with an unread reply become *ready*, mirrored as `cowork-*.json` files (`kind: "cowork"`). Every second it lays out the tiles into `~/.claude/touchbar/slots/N.txt` (title and icon) and `N.tsv` (what a tap opens). `claudebar press` opens a Cowork session by clicking its row. |
| MTMR tiles | AppleScript buttons that only read `slots/N.txt` and pick the icon. They run inside MTMR: MTMR's shell-script buttons leak a pipe on every run, which at a 1-second refresh crashes MTMR within minutes. |
| `src/open.sh N` | Tap action: opens a Code session with `claude://claude.ai/epitaxy/<session id>`, or a Cowork session through `claudebar press`. |
| `src/make_icon.py` | Draws the built-in icons (no dependencies). |
| `src/axprobe.swift` | Dev tool: dumps the app's accessibility tree, for fixing the reader when the app changes. |

Tiles keep their position in the order sessions started. Up to 6 tiles; a finished session disappears after 8 hours without activity, a "working" one after 30 minutes of silence (it probably died).

## Adding another tool

Any tool can put sessions on the Touch Bar by writing JSON files to `~/.claude/touchbar/sessions/`:

```json
{ "kind": "mytool", "state": "working", "title": "Deploy staging", "ts": 1793284805, "created": 1793284805 }
```

- `kind`: which icon to use; add a matching white glyph on a transparent background (8-bit RGBA PNG, 48×48) as `icons/mytool.png` and re-run `./install.sh`.
- `state`: `working` or `ready`.
- `ts`: last update (Unix seconds). `created` keeps the tile's position stable.
- Delete the file when the session ends.

Tapping a tile of a new kind just brings Claude to the front; to open the session itself, add a case for your kind in `src/open.sh`.

## Limitations

- **Cowork depends on the app's UI.** The reader matches the sidebar by its structure (DOM classes and position), not by labels, so it works in any app language, but an app redesign can break it. Running sessions are detected by the status text, matched in a few languages (`running`, `en ejecución`, …); add yours in `runningWords` in `claudebar.swift`.
- **The color is on the icon, not the whole tile.** MTMR's AppleScript buttons can swap icons but not background colors.
- **Up to 6 tiles** (`SLOTS` in `install.sh` and `slotCount` in `claudebar.swift`).
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

**En español:** muestra tus sesiones de Claude (Code y Cowork) en la Touch Bar, cada una con su icono: gris mientras trabaja, azul cuando te necesita, y al tocar te lleva a la sesión. Instala con `./install.sh`.

## License

[MIT](LICENSE)
