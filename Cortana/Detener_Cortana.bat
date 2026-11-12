@echo off
REM Apaga Cortana para liberar memoria
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0lanzador\Cortana.ps1" -Detener
