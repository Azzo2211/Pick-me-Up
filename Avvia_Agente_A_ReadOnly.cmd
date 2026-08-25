@echo off
setlocal
cd /d "%~dp0"

rem Prefer the Windows Python Launcher. It avoids the Microsoft Store python.exe alias.
py -3 --version >nul 2>nul
if %errorlevel%==0 (
    py -3 ".\agent-a\readonly_agent_v5.py" --benchmark
    goto :done
)

rem Fall back to a real python executable only if it can actually run Python.
python -c "import sys; assert sys.version_info.major == 3" >nul 2>nul
if %errorlevel%==0 (
    python ".\agent-a\readonly_agent_v5.py" --benchmark
    goto :done
)

echo.
echo Python 3 non trovato.
echo Installa Python 3 oppure rendi disponibile il comando py/python e riprova.
echo.

:done
echo.
pause
endlocal
