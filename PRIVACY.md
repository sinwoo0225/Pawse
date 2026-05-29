# Privacy Policy — pawse

_Last updated: 2026-05-29_

**English** · [한국어](#개인정보-처리방침-한국어)

pawse is a **local, offline** desktop widget for Claude Code (Windows). This policy describes exactly what it does — and does not do — with your data.

## Summary

**pawse does not collect, store, transmit, or share any personal data.** It has no servers, no telemetry, no analytics, and makes **no network connections of any kind**. Everything happens locally on your own machine.

## What pawse accesses (all locally)

- **Hook input from Claude Code** (read from stdin): the current event (`Stop` / `Notification` / optional `PreToolUse`) and, for `PreToolUse`, the tool name and command being run.
- **The Claude Code transcript file** referenced by the hook — read only to display a short preview of the last assistant message in the Stop widget.
- **Its own configuration** (`config.psd1`) and image assets.
- **Only for the optional PreToolUse feature:** the `permissions.allow` rules in your local Claude Code `settings.json` files, read to decide whether to show a confirmation widget.

## What pawse does with it

- Renders a widget on your local desktop.
- When you type a reply in the Stop widget, your text is written back to your **local** Claude Code process (as the hook's stdout) so Claude can continue. This text goes only to that local process — pawse never sends it anywhere else.
- On first run as a plugin, it copies the bundled default `config.psd1` into your per-plugin data folder so your settings survive plugin updates.

## What pawse does NOT do

- No network requests, ever.
- No telemetry, analytics, crash reporting, or usage tracking.
- No collection or transmission of your prompts, code, file contents, or any personal data to the author or any third party.
- No storage of your data beyond the local configuration it reads/writes on your own machine.

## Third parties

pawse integrates only with your local Claude Code installation. Your use of Claude Code itself is governed by Anthropic's own policies, which are separate from this plugin.

## Contact & changes

Questions or concerns: open an issue at <https://github.com/sinwoo0225/Pawse>. Any change to this policy will be committed to this file in the repository.

---

## 개인정보 처리방침 (한국어)

pawse는 Claude Code용 **로컬·오프라인** 데스크톱 위젯(Windows)입니다. 데이터와 관련해 무엇을 하고 하지 않는지 그대로 설명합니다.

**요약: pawse는 어떤 개인정보도 수집·저장·전송·공유하지 않습니다.** 서버·텔레메트리·분석이 없고, **어떤 네트워크 연결도 하지 않습니다.** 모든 처리는 사용자의 로컬 머신에서만 일어납니다.

**pawse가 접근하는 것(모두 로컬):**
- Claude Code의 hook 입력(stdin): 현재 이벤트(`Stop`/`Notification`/선택 `PreToolUse`)와, `PreToolUse`의 경우 실행될 도구 이름·명령.
- hook이 가리키는 Claude Code 트랜스크립트 파일 — Stop 위젯에 직전 메시지 미리보기를 보여주기 위해서만 읽음.
- 자체 설정(`config.psd1`)과 이미지 에셋.
- **선택 기능 PreToolUse에서만:** 로컬 `settings.json`의 `permissions.allow` 규칙(확인 위젯을 띄울지 판단용).

**pawse가 하는 일:** 로컬 데스크톱에 위젯을 띄우고, Stop 위젯에 입력한 텍스트를 **로컬** Claude Code 프로세스로(hook stdout) 돌려줘 작업을 잇게 함. 그 텍스트는 로컬 프로세스로만 전달되며 외부로 보내지 않음. 플러그인 첫 실행 시 번들 기본 `config.psd1`을 플러그인 데이터 폴더로 복사(설정 보존용).

**pawse가 하지 않는 일:** 네트워크 요청·텔레메트리·분석·사용 추적 없음. 프롬프트·코드·파일 내용·개인정보를 작성자나 제3자에게 수집/전송하지 않음. 로컬 설정 외 별도 저장 없음.

**문의/변경:** <https://github.com/sinwoo0225/Pawse> 이슈로 문의. 정책 변경은 이 파일에 커밋됩니다.
