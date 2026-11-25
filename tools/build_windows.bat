@echo off
rem Exports the game for Windows into build\windows (the exe and its .pck: both
rem are needed, side by side). online.cfg goes in with it, so the build finds
rem the matchmaker. Needs Godot's export templates for this version installed.
rem Set GODOT to the Godot console exe if it is not where this file expects it.
setlocal
if "%GODOT%"=="" set GODOT=C:\Users\Andre\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe
cd /d "%~dp0.."
if not exist build\windows mkdir build\windows
"%GODOT%" --headless --path . --export-release Windows build/windows/FootballBananaz.exe
endlocal
