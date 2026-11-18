@echo off
rem ==== Diagnostic: replicate run-weekly.cmd auth loading, then test claude -p ====
rem NOTE: keep this file ASCII-only
cd /d "C:\Users\Windows\My Ai\market-research-agent"
if exist ".claude\auth-weekly.env" (
  for /f "usebackq delims=" %%a in (".claude\auth-weekly.env") do set "%%a"
)
echo auth vars loaded
claude -p "Reply with exactly OK"
echo exit code: %errorlevel%
