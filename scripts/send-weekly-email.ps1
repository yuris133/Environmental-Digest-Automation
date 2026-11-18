# send-weekly-email.ps1 - sends the latest digest HTML to the owner's email.
# ASCII-only file (PowerShell 5.1 reads no-BOM files in the legacy codepage).
# Secrets come from .claude\auth-weekly.env (gitignored):
#   SMTP_USER=user@example.com
#   SMTP_PASS=<16-char Gmail app password>
#   MAIL_TO=user@example.com   (optional, defaults to the address below)
# Credentials are never printed or logged.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$defaultTo = 'user@example.com'

# --- 1. Load SMTP settings: prefer env vars (set by run-weekly.cmd), fall back to the env file ---
if (-not $env:SMTP_USER -or -not $env:SMTP_PASS) {
  $envPath = Join-Path $root '.claude\auth-weekly.env'
  if (Test-Path $envPath) {
    Get-Content $envPath -Encoding UTF8 | ForEach-Object {
      if ($_ -match '^\s*(SMTP_[A-Za-z0-9_]+|MAIL_TO)\s*=\s*(.+?)\s*$') {
        Set-Item -Path ('env:' + $Matches[1]) -Value $Matches[2]
      }
    }
  }
}
if (-not $env:SMTP_USER -or -not $env:SMTP_PASS) {
  Write-Output 'EMAIL SKIPPED: SMTP_USER/SMTP_PASS are not set in .claude\auth-weekly.env yet.'
  exit 0
}

# --- 1b. Failure alert: if today's weekly report is missing, email an alert instead of a digest ---
$today = Get-Date -Format 'yyyy-MM-dd'
$reportPath = Join-Path $root ('Report\' + $today + '-green-waste-tech-fmcg-weekly-report.md')
if (-not (Test-Path $reportPath)) {
  $logPath = Join-Path $root 'weekly-run.log'
  $logTail = ''
  if (Test-Path $logPath) { $logTail = (Get-Content $logPath -Tail 8 | Out-String).Trim() }
  $sec = ConvertTo-SecureString $env:SMTP_PASS -AsPlainText -Force
  $cred = New-Object System.Management.Automation.PSCredential($env:SMTP_USER, $sec)
  $tolist = @($env:MAIL_TO, $defaultTo) | Where-Object { $_ } | Select-Object -Unique
  Send-MailMessage -SmtpServer 'smtp.gmail.com' -Port 587 -UseSsl -Credential $cred `
    -From $env:SMTP_USER -To $tolist `
    -Subject "FAILED: weekly green-waste report $today not created" `
    -Body "The scheduled weekly run did not create Report\\$today-green-waste-tech-fmcg-weekly-report.md.`r`n`r`nLast lines of weekly-run.log:`r`n`r`n$logTail" `
    -Encoding UTF8
  Write-Output 'ALERT SENT: today report missing'
  exit 0
}

# --- 2. Find the newest digest HTML anywhere under the project root, then the matching .md ---
$html = Get-ChildItem -Path $root -Recurse -File -Filter '*-green-waste-tech-fmcg-digest.html' |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $html) {
  Write-Output 'EMAIL SKIPPED: no digest HTML found.'
  exit 0
}
$md = $mdPath = $null
if ($html.BaseName -like '*-digest') {
  $mdPath = Join-Path $html.DirectoryName ($html.BaseName + '.md')
  if (Test-Path $mdPath) { $md = Get-Item $mdPath }
}

# --- 3. Pull title and TL;DR text from the markdown version so the body/subject match it ---
$subject = 'Weekly green-waste-tech FMCG digest'
$body = ''
if ($md) {
  $lines = Get-Content -LiteralPath $md.FullName -Encoding UTF8
  $titleLine = $lines | Where-Object { $_ -like '# *' } | Select-Object -First 1
  if ($titleLine) { $subject = $titleLine.Substring(2).Trim() }
  $tldr = @()
  $inTldr = $false
  foreach ($l in $lines) {
    if ($l -like '## *') {
      if ($inTldr) { break }
      if ($l -like '*TL;DR*') { $inTldr = $true }
    } elseif ($inTldr -and $l -and ($l -notlike '---*')) {
      $tldr += $l
    } elseif ($inTldr -and (-not $l) -and $tldr.Count) {
      $tldr += ''
    }
  }
  if ($tldr.Count) { $body = ($tldr -join "`r`n").Trim() }
}
if (-not $body) { $body = 'See attached files.' }

# --- 4. Send via Gmail SMTP ---
$sec = ConvertTo-SecureString $env:SMTP_PASS -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential($env:SMTP_USER, $sec)
$tolist = @($env:MAIL_TO, $defaultTo) | Where-Object { $_ } | Select-Object -Unique
$attach = @($html.FullName)
Send-MailMessage -SmtpServer 'smtp.gmail.com' -Port 587 -UseSsl -Credential $cred `
  -From $env:SMTP_USER -To $tolist `
  -Subject $subject -Body $body -Encoding UTF8 `
  -Attachments $attach
Write-Output ('EMAIL SENT: ' + $subject)