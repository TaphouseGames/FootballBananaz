@echo off
rem Packs the game for the match server into build\server.pck (some seconds).
rem The container of server\Dockerfile is built from it.
rem Set GODOT to the Godot console exe if it is not where this file expects it.
setlocal
if "%GODOT%"=="" set GODOT=C:\Users\Andre\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe
cd /d "%~dp0.."
if not exist build mkdir build
"%GODOT%" --headless --path . --export-pack Server build/server.pck
endlocal
