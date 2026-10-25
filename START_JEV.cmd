@echo off
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\start_demo.ps1" -Provider Jev
if errorlevel 1 pause
