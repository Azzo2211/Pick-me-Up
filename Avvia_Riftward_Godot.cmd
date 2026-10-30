@echo off
setlocal
set "GODOT_EXE=C:\Users\SysAdmin\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64.exe"
set "PROJECT_DIR=%~dp0godot"

if not exist "%GODOT_EXE%" (
  echo Godot non trovato in:
  echo %GODOT_EXE%
  echo.
  echo Apri Godot manualmente e importa il file:
  echo %PROJECT_DIR%\project.godot
  pause
  exit /b 1
)

rem Prima aggiorna font, immagini e script nuovi arrivati da GitHub,
rem altrimenti il gioco non parte dopo un git pull.
echo Aggiorno i file del gioco...
start "Riftward - aggiornamento" /wait "%GODOT_EXE%" --headless --path "%PROJECT_DIR%" --import
start "Riftward" "%GODOT_EXE%" --path "%PROJECT_DIR%"
endlocal
