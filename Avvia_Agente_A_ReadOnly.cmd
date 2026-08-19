@echo off
setlocal
cd /d "%~dp0"

where python >nul 2>nul
if %errorlevel%==0 (
    python ".\agent-a\readonly_agent.py" --benchmark
    goto :done
)

where py >nul 2>nul
if %errorlevel%==0 (
    py -3 ".\agent-a\readonly_agent.py" --benchmark
    goto :done
)

echo.
echo Python 3 non trovato nel PATH.
echo Installa Python 3 oppure rendi disponibile il comando python/py e riprova.
echo.

:done
echo.
pause
endlocal
