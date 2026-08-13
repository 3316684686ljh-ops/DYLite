@echo off
chcp 65001 >nul
cd /d "%~dp0"

echo Pushing DYLite to GitHub...
git push --force -u origin main

if %errorlevel% neq 0 (
    echo [FAILED] Run "设置推送Token.bat" first to set up authentication.
    pause
    exit /b 1
)

echo.
echo SUCCESS! Check Actions page:
echo   https://github.com/3316684686LJH-ops/DYLite/actions
start https://github.com/3316684686LJH-ops/DYLite/actions
pause
