@echo off
title 浙大校园助手 - 启动器
cd /d "%~dp0"

echo ================================================
echo   浙大校园助手 - 一键开发启动
echo   后端: http://127.0.0.1:7788
echo   前端: http://localhost:5173
echo ================================================
echo.

rem ---- 环境检查 ----
where node >nul 2>nul || (
    echo [错误] 未检测到 Node.js，请先安装 Node.js 20 或更高版本: https://nodejs.org
    pause
    exit /b 1
)

where pnpm >nul 2>nul
if errorlevel 1 (
    echo [提示] 未检测到 pnpm，尝试通过 corepack 启用...
    corepack enable >nul 2>nul
    where pnpm >nul 2>nul
    if errorlevel 1 (
        echo [错误] pnpm 仍不可用，请手动执行: npm install -g pnpm
        pause
        exit /b 1
    )
)

rem ---- 首次运行自动安装依赖 ----
if not exist "node_modules" (
    echo [提示] 首次运行，正在安装依赖（可能需要几分钟）...
    call pnpm install
    if errorlevel 1 (
        echo [错误] 依赖安装失败，请检查网络后重试。
        pause
        exit /b 1
    )
    echo.
)

rem ---- 后台隐藏启动：前后端服务 + 系统托盘 + 桌面挂件 ----
rem 原先两个可见的 cmd 窗口已取消，服务输出改写到 .run\server.log 与 .run\web.log
node "%~dp0scripts\dev-launcher.mjs"
if errorlevel 1 (
    echo.
    echo [错误] 启动失败，请查看上方输出或 .run\launcher.log。
    pause
    exit /b 1
)

echo.
echo ==================================================
echo   启动完成！前后端已在后台隐藏运行，不再占用任务栏。
echo   托盘图标可控制：显示/隐藏挂件、切换材质、查看日志、停止服务。
echo   需要停止时，双击 stop-dev.bat 或使用托盘菜单「退出」。
echo   本窗口将在 3 秒后自动关闭。
echo ==================================================
ping -n 4 127.0.0.1 >nul
exit /b 0
