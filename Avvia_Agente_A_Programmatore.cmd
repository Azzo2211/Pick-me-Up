@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"

echo ==============================================
echo Riftward - Agent A PROGRAMMATORE v4.11
echo Product decision router + escalation guard
echo Nessun commit, push o merge automatico
echo ==============================================
echo.

rem Prefer the Windows Python Launcher to avoid the Microsoft Store alias.
py -3 --version >nul 2>nul
if %errorlevel%==0 (
    py -3 ".\agent-a\programmer_agent_v4_11.py"
    goto :done
)

python -c "import sys; assert sys.version_info.major == 3" >nul 2>nul
if %errorlevel%==0 (
    python ".\agent-a\programmer_agent_v4_11.py"
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
