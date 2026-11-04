@echo off
cd /d "%~dp0"
where py >nul 2>nul
if %errorlevel%==0 (
  py -3 download_project.py
) else (
  python download_project.py
)
pause
