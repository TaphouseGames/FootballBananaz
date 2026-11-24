@echo off
rem An online match on this one machine: a server, a second person who plays
rem with random buttons, and a window for you. Close the window to end it.
rem Usage: tools\online_local.bat [path to the Godot console exe]
setlocal
set GODOT=%~1
if "%GODOT%"=="" set GODOT=C:\Users\Andre\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe
cd /d "%~dp0.."
start "bananaz server" /min "%GODOT%" --headless --path . res://scenes/server.tscn -- port=24642
timeout /t 6 /nobreak >nul
start "bananaz bot" /min "%GODOT%" --headless --path . res://scenes/online_dev.tscn -- join=127.0.0.1 port=24642 bot
"%GODOT%" --path . res://scenes/online_dev.tscn -- join=127.0.0.1 port=24642
endlocal
