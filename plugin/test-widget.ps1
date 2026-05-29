<#
  claude-widget 자체 테스트 (의존성 없음)
  GUI를 띄우지 않는 순수 로직만 검증한다. 실행:
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\test-widget.ps1
#>
$ErrorActionPreference = 'Stop'
$pass = 0; $fail = 0
function Check([string]$name, [bool]$cond) {
    if ($cond) { "  [PASS] $name"; $script:pass++ }
    else { "  [FAIL] $name"; $script:fail++ }
}

"== 1. 위험 명령 정규식 (config.psd1) =="
$cfg = Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot 'config.psd1')
$dp = $cfg.DangerPattern
Check "rm -rf 매칭"            ('rm -rf build' -match $dp)
Check "git push --force 매칭"  ('git push origin main --force' -match $dp)
Check "Remove-Item 매칭"       ('Remove-Item -Recurse x' -match $dp)
Check "ls -la 비매칭"          (-not ('ls -la' -match $dp))
Check "npm test 비매칭"        (-not ('npm test' -match $dp))

"== 2. UTF-8 stdin/stdout 왕복 =="
$json = @{ reason = '한글 테스트 メッセージ 🐾' } | ConvertTo-Json -Compress
$bytes = [System.Text.Encoding]::UTF8.GetBytes($json + "`n")
$decoded = ([System.Text.Encoding]::UTF8.GetString($bytes)).Trim()
Check "UTF-8 왕복 일치" ($decoded -eq $json)
Check "한글 바이트(ED 95 9C=한) 포함" (($bytes -join ' ') -match '237 149 156')

"== 3. 트랜스크립트 한글 미리보기 추출 =="
$tmp = [System.IO.Path]::GetTempFileName()
$line = '{"type":"assistant","message":{"content":[{"type":"text","text":"작업을 마쳤습니다 ✓"}]}}'
[System.IO.File]::WriteAllText($tmp, $line, (New-Object System.Text.UTF8Encoding $false))
$lines = [System.IO.File]::ReadAllLines($tmp, (New-Object System.Text.UTF8Encoding $false))
$obj = $lines[0] | ConvertFrom-Json
$text = ($obj.message.content | Where-Object { $_.type -eq 'text' } | ForEach-Object { $_.text }) -join "`n"
Remove-Item $tmp -Force
Check "한글 미리보기 무손실" ($text -eq '작업을 마쳤습니다 ✓')

"== 4. 메인 스크립트 문법 =="
$errs = $null
[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'claude-widget.ps1'), [ref]$null, [ref]$errs) | Out-Null
Check "claude-widget.ps1 문법 정상" (-not $errs)

""
"결과: PASS=$pass  FAIL=$fail"
if ($fail -gt 0) { exit 1 } else { exit 0 }
