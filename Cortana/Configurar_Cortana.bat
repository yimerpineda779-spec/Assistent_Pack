@echo off
REM Cambiar las claves de Gemini o Tavily
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0lanzador\Cortana.ps1" -Configurar
