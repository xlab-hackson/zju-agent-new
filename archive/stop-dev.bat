@echo off
title 浙大校园助手 - 停止服务
cd /d "%~dp0"

echo ================================================
echo   浙大校园助手 - 停止后台服务
echo ================================================
echo.

node "%~dp0scripts\stop-dev.mjs"

echo.
pause
