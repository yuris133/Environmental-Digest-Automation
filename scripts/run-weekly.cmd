@echo off
rem ==== Weekly market research run (Task Scheduler: Fri 10:05) ====
rem NOTE: keep this file ASCII-only (batch parser uses a legacy codepage)
cd /d "C:\Users\Windows\My Ai\market-research-agent"
rem ==== load auth from local (gitignored) env file ====
if exist ".claude\auth-weekly.env" (
  for /f "usebackq delims=" %%a in (".claude\auth-weekly.env") do set "%%a"
)
echo === %date% %time%: weekly run start === >> weekly-run.log
claude -p "Weekly news collection. Follow the role and rules in this project's CLAUDE.md. Search the web for news published in the last 7 days about green waste-recycling technologies used by FMCG companies: packaging and recycling, food production surplus, confectionery manufacturing, upcycling into pet food, AI and digital technologies in recycling. Build the report following the structure of the template file 'Report/_template.md' (trend of the week, topic sections, trend summary, list of sources with links). Save the report as 'Report/YYYY-MM-DD-green-waste-tech-fmcg-weekly-report.md' where YYYY-MM-DD is today's date. If a file with this name already exists, add a -2 suffix instead of overwriting (if -2 also exists, add -3, -4 and so on). Write the report in Russian and include markdown links to sources." >> weekly-run.log 2>&1
set "CLAUDE_EXIT=%errorlevel%"
for /f %%d in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd"') do set "TODAY=%%d"
if exist "Report\%TODAY%-green-waste-tech-fmcg-weekly-report.md" (
  echo === %date% %time%: run finished, exit code %CLAUDE_EXIT%, report file OK === >> weekly-run.log
) else (
  echo === %date% %time%: FAILED: claude exit code %CLAUDE_EXIT%, report Report\%TODAY%-green-waste-tech-fmcg-weekly-report.md NOT created === >> weekly-run.log
  echo === %date% %time%: failure alert will be attempted by send-weekly-email.ps1 === >> weekly-run.log
)
rem ==== send digest by email (needs SMTP_USER/SMTP_PASS in .claude\auth-weekly.env) ====
rem ==== or a failure alert if today's report is missing — logic inside the PS script ====
powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "send-weekly-email.ps1" >> weekly-run.log 2>&1
echo === %date% %time%: email step done === >> weekly-run.log
