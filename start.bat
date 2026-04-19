@echo off
setlocal
chcp 65001 > nul

set PORT=3000
set URL=http://localhost:%PORT%/wizard.html

echo Starting local HTTP server on port %PORT%...

:: Start npx serve in background
start /b npx serve . -p %PORT% --no-clipboard

:: Wait for server to start
timeout /t 3 /nobreak > nul

:: Open wizard in browser
start "" "%URL%"
echo Opened: %URL%
echo.
echo Setup wizard ^-^> configure ^-^> 'Chat Screen'
echo Close this window to stop the server.
echo.
:keep_alive
timeout /t 30 /nobreak > nul
goto keep_alive
