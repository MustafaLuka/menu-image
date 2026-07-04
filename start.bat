@echo off
title Menu Image Matcher - Server
echo Starting Menu Image Matcher...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0serve.ps1"
echo.
echo Server stopped.
pause
