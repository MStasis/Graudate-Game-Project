@echo off
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\verify_mission.ps1"
if errorlevel 1 pause
