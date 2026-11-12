@echo off
REM Abre Cortana (sin ventanas negras)
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0lanzador\Cortana.ps1"
