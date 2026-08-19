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

start "Riftward" "%GODOT_EXE%" --path "%PROJECT_DIR%"
endlocal
