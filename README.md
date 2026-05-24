# 🦁 pawse

**English** · [한국어](#한국어)

> An interactive hook widget for Claude Code: when Claude **pauses**, the lion **Leo** peeks out so you can reply straight from a desktop popup.

When Claude finishes a task (Stop) or waits for your input (Notification), pawse shows a small desktop widget. **Type your next instruction right in the widget and Claude keeps going.** It also asks you to allow or block risky commands before they run. Built with PowerShell + WPF — **no install required** (Windows only).

## Screenshots

| Stop — type your next instruction | Notification — Claude needs you |
|:--:|:--:|
| <img src="screenshots/stop1-capture.png" width="420" alt="pawse Stop widget"> | <img src="screenshots/noti-capture.png" width="300" alt="pawse Notification toast"> |

## What each event does

| Event | Trigger | Widget | Leo |
|---|---|---|---|
| **Stop** | Claude finishes a response | Preview of the last message + an input box. Type to make Claude continue (`{"decision":"block"}`); leave it empty to just stop. | 😊 happy |
| **Notification** | Permission / idle input wait | Toast notification (auto-dismiss). Informational only. | 😮 surprised `!` |
| **PreToolUse** | Right before a risky Bash command | Shows the command + `허용 / 직접 확인 / 차단` (Allow / Ask / Block). Safe **Block** gets default focus; risky **Allow** is de-emphasized (outline). | 🤔 puzzled `?` |

> **Design**: aligned with Windows 11 Fluent (8px card / 4px controls, soft shadow + 1px border, Segoe UI Variable type ramp 20/14/12, WCAG AA-passing colors), automatic light/dark following the system, and a slide-in entrance (respecting the system "Show animations" setting).

## How it works

The widget script is wired into Claude Code [hooks](https://code.claude.com/docs/en/hooks). The key idea is that it's **bidirectional**:

```
Claude finishes ─▶ Stop hook ─▶ pawse widget appears
                                     │  you type the next instruction
                                     ▼
       {"decision":"block","reason":"<your text>"}  ─▶ Claude continues
```

## Install

1. Clone this repo wherever you like.
2. Add the following to `hooks` in `~/.claude/settings.json`. **Replace `<install-path>` with the absolute path to `claude-widget.ps1`.**

```json
"hooks": {
  "Stop": [{ "hooks": [{ "type": "command", "timeout": 600,
    "command": "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"<install-path>\\claude-widget.ps1\" -Event Stop" }] }],
  "Notification": [{ "hooks": [{ "type": "command", "timeout": 30,
    "command": "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"<install-path>\\claude-widget.ps1\" -Event Notification" }] }],
  "PreToolUse": [{ "matcher": "Bash", "hooks": [{ "type": "command", "timeout": 600,
    "command": "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"<install-path>\\claude-widget.ps1\" -Event PreToolUse" }] }]
}
```

3. **Restart** Claude Code to load the hooks.

> WPF needs an STA thread, so it's invoked with **`powershell.exe`** (Windows PowerShell 5.1), not `pwsh`.

## Configuration (`config.psd1`)

| Key | Description |
|---|---|
| `Sound` | Play a sound when the widget appears |
| `NotificationAutoCloseSeconds` | Toast auto-dismiss time (seconds) |
| `PreviewMaxChars` | Max chars for the Stop preview (`0` = unlimited) |
| `Mode` | `'auto'` (follow Windows light/dark) · `'light'` · `'dark'` |
| `Accent` / `AccentDark` | Light/dark accent (primary button & focus). Defaults pass WCAG AA (≥4.5:1) |
| `Animate` | Slide-in entrance. If omitted, follows the Windows "Show animations" setting (`$true`/`$false` to force) |
| `DangerPattern` | Regex for which commands trigger the PreToolUse widget. Use `'.'` for every Bash command; remove the PreToolUse hook in settings.json to disable |

`config.psd1` is read every time a widget appears, so changes apply **without restarting** Claude Code.

## Changing the character (Leo)

The `assets/` folder contains Leo's three expressions (`stop.png`, `notification.png`, `pretooluse.png`). Replace them with your own **transparent PNGs** (square recommended) to change the character. Delete them to fall back to the built-in vector character.

## Try it directly

```powershell
# Stop widget (type, continue → check JSON output)
'{"hook_event_name":"Stop","stop_hook_active":false,"transcript_path":""}' |
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\claude-widget.ps1 -Event Stop

# PreToolUse widget (risky command)
'{"tool_name":"Bash","tool_input":{"command":"rm -rf build"}}' |
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\claude-widget.ps1 -Event PreToolUse

# Notification toast
'{"notification_type":"idle_prompt","message":"Waiting for input"}' |
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\claude-widget.ps1 -Event Notification
```

Logic only (no GUI): `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\test-widget.ps1`

## Details & limitations

- **Stop**: when the hook writes `{"decision":"block","reason":"<text>"}` to stdout, Claude resumes with that text as its next instruction. If `stop_hook_active` is true (already in a widget-triggered resume), the widget is skipped to avoid an infinite loop.
- **Notification** is informational only and can't answer permission prompts — permission decisions are handled by the PreToolUse widget.
- While the widget waits for input, Claude waits too. If it exceeds `timeout` (seconds) the hook is killed and the widget closes, so **600** is recommended for Stop/PreToolUse.
- All of stdin, stdout, transcript reads, and the script file are handled as UTF-8 so non-ASCII (e.g. Korean) doesn't break.

## Layout

| File | Role |
|---|---|
| `claude-widget.ps1` | Single entry point; dispatches on `-Event Stop\|Notification\|PreToolUse` |
| `config.psd1` | User settings |
| `assets/` | Leo expression PNGs (customizable) |
| `test-widget.ps1` | Dependency-free logic tests |

## License

MIT — see [LICENSE](LICENSE).

---

# 한국어

> Claude Code가 **멈출 때**(_pause_) 사자 **Leo**가 고개를 쏙 내미는, Claude Code용 양방향 hook 위젯.

Claude Code가 작업을 마치거나(Stop) 입력을 기다릴 때(Notification) 데스크톱에 작은 위젯을 띄우고, **그 위젯에서 바로 다음 지시를 입력**하면 Claude가 이어서 작업합니다. 위험한 명령을 실행하기 전에는 허용/차단도 물어봅니다. PowerShell + WPF로 만들어 **별도 설치가 필요 없습니다**(Windows 전용).

## 이벤트별 동작

| 이벤트 | 트리거 | 위젯 | Leo |
|---|---|---|---|
| **Stop** | Claude가 응답을 마침 | 마지막 메시지 미리보기 + 입력창. 입력하면 Claude가 이어서 작업(`{"decision":"block"}`). 비워두면 그냥 종료. | 😊 웃음 |
| **Notification** | 권한/입력 대기(idle) | 토스트 알림(자동 닫힘). 정보 전용. | 😮 놀람 `!` |
| **PreToolUse** | 위험한 Bash 명령 실행 직전 | 명령 표시 + `허용 / 직접 확인 / 차단`. 안전한 `차단`이 기본 포커스, 위험한 `허용`은 아웃라인으로 약화. | 🤔 갸웃 `?` |

> **디자인**: Windows 11 Fluent 정합(8px 카드 / 4px 컨트롤, 부드러운 그림자 + 1px 테두리, Segoe UI Variable 타입램프 20/14/12, WCAG AA 통과 색), 시스템 라이트/다크 자동 전환, 등장 슬라이드인(시스템 "애니메이션 표시" 설정 존중).

## 동작 방식

Claude Code의 [hooks](https://code.claude.com/docs/en/hooks)에 위젯 스크립트를 연결합니다. 핵심은 **양방향**이라는 점 — Stop hook이 `{"decision":"block","reason":"<입력>"}`을 반환하면 그 입력이 Claude의 다음 지시가 되어 작업이 이어집니다. (다이어그램은 위 영어 섹션 참고.)

## 설치

1. 이 저장소를 원하는 위치에 클론합니다.
2. `~/.claude/settings.json`의 `hooks`에 위 영어 섹션의 JSON을 추가합니다. **`<install-path>`를 `claude-widget.ps1`의 실제 절대경로로 바꾸세요.**
3. Claude Code를 **재시작**하면 hook이 로드됩니다.

> WPF는 STA 스레드가 필요하므로 `pwsh`가 아니라 **`powershell.exe`**(Windows PowerShell 5.1)로 호출합니다.

## 설정 (`config.psd1`)

| 키 | 설명 |
|---|---|
| `Sound` | 위젯 등장 시 알림음 |
| `NotificationAutoCloseSeconds` | 토스트 자동 닫힘 시간(초) |
| `PreviewMaxChars` | Stop 미리보기 최대 글자 수(`0`이면 무제한) |
| `Mode` | `'auto'`(Windows 라이트/다크 따름) · `'light'` · `'dark'` |
| `Accent` / `AccentDark` | 라이트/다크 강조색(Primary 버튼·포커스). 기본값은 WCAG AA(≥4.5:1) 통과 |
| `Animate` | 등장 슬라이드인. 생략 시 Windows "애니메이션 표시" 설정을 따름(`$true`/`$false`로 강제) |
| `DangerPattern` | PreToolUse 위젯을 띄울 명령 정규식. 모든 Bash에 띄우려면 `'.'`, 끄려면 settings.json에서 PreToolUse hook 제거 |

`config.psd1`은 위젯이 뜰 때마다 읽으므로 **Claude Code 재시작 없이** 반영됩니다.

## 캐릭터(Leo) 바꾸기

`assets/` 폴더에 사자 Leo의 표정 3종(`stop.png`, `notification.png`, `pretooluse.png`)이 들어 있습니다. 원하는 **투명 PNG**(정사각형 권장)로 교체하면 캐릭터가 바뀝니다. 파일을 지우면 스크립트에 내장된 벡터 캐릭터가 대신 표시됩니다.

## 동작 원리 / 한계

- **Stop**: hook이 `{"decision":"block","reason":"<입력>"}`을 stdout으로 반환하면 Claude가 그 지시로 작업을 재개합니다. `stop_hook_active`가 true면(이미 위젯이 유발한 재개 중) 위젯을 띄우지 않아 무한 루프를 막습니다.
- **Notification**은 정보 전용이라 권한을 직접 응답할 수 없습니다 — 권한 응답은 PreToolUse 위젯이 담당합니다.
- 위젯이 입력 대기로 떠 있는 동안 Claude는 기다립니다. `timeout`(초)을 넘기면 hook이 종료되고 위젯이 닫히므로 Stop/PreToolUse는 **600** 권장.
- 한글 등 비ASCII가 깨지지 않도록 stdin·stdout·트랜스크립트 읽기·스크립트 파일을 모두 UTF-8로 처리합니다.

---

<sub>made for Claude Code · PowerShell + WPF · Windows</sub>
