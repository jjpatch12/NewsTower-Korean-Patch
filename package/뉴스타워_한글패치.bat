@echo off
setlocal
title News Tower Korean Patch v1.0.0

attrib +h "%~dp0.patch_data" >nul 2>&1

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0.patch_data\install.ps1" %*
set "PATCH_EXIT=%ERRORLEVEL%"

echo.
if not "%PATCH_EXIT%"=="0" (
    echo The patch did not complete. Check the error above.
)
pause
exit /b %PATCH_EXIT%
