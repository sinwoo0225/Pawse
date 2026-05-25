# claude-widget 사용자 설정
# 이 파일을 수정한 뒤 저장하면 다음 위젯부터 반영됩니다. (Claude Code 재시작 불필요)
@{
    # 위젯이 뜰 때 알림음 재생 여부
    Sound = $true

    # Notification(토스트) 자동 닫힘 시간(초)
    NotificationAutoCloseSeconds = 8

    # Stop 위젯의 직전 메시지 미리보기 최대 글자 수(초과분은 '…'로 잘림).
    #   0으로 두면 자르지 않음(전체 표시, 박스 안에서 스크롤).
    PreviewMaxChars = 2000

    # 등장 슬라이드인 애니메이션. 생략/주석 시 Windows "애니메이션 표시" 설정을 따름.
    #   $true 강제 켜기 / $false 강제 끄기
    # Animate = $true

    # 테마 모드: 'auto'(Windows 라이트/다크 따름) | 'light' | 'dark'
    Mode = 'auto'

    # 강조색(Primary 버튼/포커스). 라이트/다크 각각 지정. 생략 시 기본값 사용.
    #   라이트 기본 '#6C4DD6' (흰 글자 대비 ~5.7:1, WCAG AA 통과)
    #   다크  기본 '#B9A4FF'
    Accent     = '#6C4DD6'
    AccentDark = '#B9A4FF'

    # PreToolUse 위젯을 띄울 명령 정규식. (위젯 hook은 default 권한 모드에서만 동작)
    #
    # ── 현재: '.' = "터미널 미러" 모드 ──────────────────────────────────────
    #   '.'은 비어있지 않은 모든 명령에 매치되므로, default 모드에서
    #   allowlist(permissions.allow)에 없는 "모든" 명령에 위젯이 뜸
    #   = 터미널 권한 프롬프트와 동일하게 동작.
    #
    #   ▶ 자주 쓰는 명령은 settings.json / settings.local.json 의 permissions.allow 에
    #     등록해두면 위젯이 안 뜸. 위젯 hook은 'Bash' 도구에 걸리므로 규칙도 Bash(...) 형식.
    #       "permissions": { "allow": [ "Bash(git *)", "Bash(npm run *)", "Bash(ls *)" ] }
    #     (Claude Code 프롬프트에서 "허용하고 다시 묻지 않기"를 골라도 여기에 자동 추가됨)
    #
    # ── "위험 명령만" 모드로 되돌리려면 ──────────────────────────────────────
    #   아래 DangerPattern = '.' 줄을 주석 처리(#)하고,
    #   그 밑의 주석 처리된 위험-패턴 줄의 주석을 풀어 활성화하세요. (둘 중 하나만 활성)
    #   패턴은 정규식이며 `|`로 항목을 추가할 수 있습니다.
    #     예: ...|takeown|\bshutdown\b|\bcurl\b|새_위험명령
    #
    #   ※ PreToolUse 위젯 자체를 끄려면 settings.json에서 PreToolUse hook을 제거하세요.
    DangerPattern = '.'
    # DangerPattern = '(^|\s)(rm|del|rmdir|rd)\s|Remove-Item|-Recurse|\bformat\b|\bmkfs|dd\s+if=|git\s+push\b.*--force|--force\b|>\s*/dev/|chmod\s+-R|takeown|\bshutdown\b'
}
