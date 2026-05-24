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

    # PreToolUse 위젯을 띄울 "위험 명령" 정규식.
    #  - 이 패턴에 매치되는 Bash 명령에만 허용/차단 위젯이 뜸 (나머지는 평소대로 동작).
    #  - 모든 Bash 명령에서 위젯을 띄우고 싶으면  '.'  으로 바꾸세요.
    #  - PreToolUse 위젯을 끄려면 settings.json에서 PreToolUse hook을 제거하세요.
    DangerPattern = '(^|\s)(rm|del|rmdir|rd)\s|Remove-Item|-Recurse|\bformat\b|\bmkfs|dd\s+if=|git\s+push\b.*--force|--force\b|>\s*/dev/|chmod\s+-R|takeown|\bshutdown\b'
}
