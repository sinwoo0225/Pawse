# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**pawse** (mascot: the lion **Leo**) — an interactive widget for Claude Code, built as a single PowerShell + WPF script wired into Claude Code [hooks](https://code.claude.com/docs/en/hooks). When Claude stops or needs input, a desktop popup appears; the user types a reply in the widget and Claude continues. Windows-only, no install/build step. See `README.md` for user-facing docs.

## Commands

There is **no build/compile** — it's an interpreted PowerShell script. Use Windows PowerShell 5.1 (`powershell.exe`), not `pwsh` (see STA note below).

```powershell
# Logic tests (no GUI): danger regex, UTF-8 round-trip, transcript preview, syntax check
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\test-widget.ps1

# Manual GUI test — pipe a sample hook JSON to one event
'{"hook_event_name":"Stop","stop_hook_active":false,"transcript_path":""}' | powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\claude-widget.ps1 -Event Stop
'{"tool_name":"Bash","tool_input":{"command":"rm -rf build"}}'             | powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\claude-widget.ps1 -Event PreToolUse
'{"notification_type":"idle_prompt","message":"hi"}'                        | powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\claude-widget.ps1 -Event Notification

# Syntax check without running
$e=$null; [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path .\claude-widget.ps1),[ref]$null,[ref]$e); $e
```

Because the widget windows are modal (`ShowDialog`), automated render-testing launches the script as a child process, sleeps ~2s, checks `HasExited` (still running ⇒ XAML parsed & window shown), then `Kill()`s it. See the test harness pattern used during development.

## Architecture

`claude-widget.ps1` is a single entry point: `-Event Stop|Notification|PreToolUse`. Flow:

1. Read hook JSON from **stdin** → load `config.psd1` → compute light/dark **palette** (from `Mode`, or the system theme via `HKCU:\...\Themes\Personalize\AppsUseLightTheme`).
2. `switch ($Event)` builds an event-specific WPF window from an inline XAML here-string and shows it.
3. The chosen decision is written to **stdout as compact JSON**; everything else (the window, errors) must stay off stdout.

Shared helpers (all defined inside the top-level `try`): `Write-StdoutUtf8`, `ConvertFrom-Xaml` (runtime `XamlReader`), `Get-WindowResources` (button/textbox styles + palette interpolation), `Get-VectorCharacterXaml` / `New-CharacterElement` (character), `Get-LastAssistantText` (transcript preview), `Start-Entrance` (slide-in), `Set-CommonWindowBehavior` (bottom-right placement, drag, focus, entrance).

The three events map to distinct hook contracts:

| Event | Output to resume/decide | Notes |
|---|---|---|
| **Stop** | `{"decision":"block","reason":"<user text>"}` → Claude continues with that text | Empty input / close ⇒ no output ⇒ Claude stops. The widget shows on **every** stop (the `stop_hook_active` skip-guard was intentionally removed; empty-input-stops + Claude Code's consecutive-block cap prevent runaway). |
| **Notification** | none — informational only | Toast, auto-dismiss. Cannot answer permission prompts. |
| **PreToolUse** | `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow\|deny\|ask",...}}` | Only shown when the command matches `DangerPattern`; otherwise `exit 0` (no widget, normal flow). |

**Character resolution**: `New-CharacterElement` uses `assets/<event>.png` if present (the Leo lion faces), else falls back to a built-in XAML vector cat. So changing the character is just swapping PNGs — no code change.

**Hook wiring lives outside the repo**, in `~/.claude/settings.json` under `hooks` (one command per event, calling this script with `-Event …`). `settings-hooks.snippet.json` holds a copy to paste. Editing `config.psd1` takes effect on the next widget (read each run); editing `settings.json` hooks requires restarting Claude Code.

## Critical gotchas (these will silently break things)

- **Encoding is everywhere.** Windows PowerShell 5.1 reads BOM-less files as ANSI. After any edit, the `.ps1`/`.psd1` **must be saved as UTF-8 *with* BOM** or Korean/non-ASCII (and string parsing) corrupts. Re-save with:
  `[System.IO.File]::WriteAllText($p, [System.IO.File]::ReadAllText($p), (New-Object System.Text.UTF8Encoding $true))`
  Correspondingly the script reads **stdin** via `OpenStandardInput()` + `UTF8.GetString` (and strips a leading U+FEFF BOM), writes **stdout** via `OpenStandardOutput()` + `UTF8.GetBytes` (`[Console]::Out` would use the OEM codepage), and reads the transcript via `ReadAllLines(..., UTF8)` (not `Get-Content`, which defaults to ANSI).
- **STA + `powershell.exe`.** WPF requires an STA thread with a Dispatcher; `powershell.exe` (5.1) is STA by default, `pwsh` is not. Hooks and tests must invoke `powershell.exe`.
- **XAML is parsed at runtime** (`XamlReader.Load`), so XAML mistakes only surface as runtime exceptions — there is no compile-time check. Validate by actually rendering (launch/sleep/kill), not just syntax-parsing the script.
- **stdout must be pure decision JSON.** Suppress WPF return values (`$null = $win.ShowDialog()`), and on any error the top-level `catch` does `exit 0` with no stdout so a widget bug never blocks Claude.
- **`[int]` in PowerShell rounds, not truncates** — use integer arithmetic (e.g. `($p - $x)/$W`) for array/pixel indices.

## Design constraints (when changing the UI)

Keep Windows 11 Fluent alignment: 8px card / 4px control corner radius, soft shadow + 1px border, Segoe UI Variable type ramp (20 SemiBold title / 14 body / 12 caption — never below 12, SemiBold not Bold), WCAG AA (≥4.5:1) text contrast. Accent/danger/warn colors are palette-driven (`Get-WindowResources`, the light/dark block) and chosen to pass AA — don't hardcode colors in the XAML. On the destructive **PreToolUse** card, keep the safe "차단/Block" as the focused primary and the risky "허용/Allow" de-emphasized.
