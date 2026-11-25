@echo off
rem The way in from the main menu, on this one machine: a server, a second
rem person who plays with random buttons, and the game itself. Press ONLINE,
rem pick a team and find a match: it is this server. Close the window to end it.
rem (The server takes one match: run this again for another.)
rem Set GODOT to the Godot console exe if it is not where this file expects it.
setlocal
if "%GODOT%"=="" set GODOT=C:\Users\Andre\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe
cd /d "%~dp0.."
start "bananaz server" /min "%GODOT%" --headless --path . res://scenes/server.tscn -- port=24642
timeout /t 6 /nobreak >nul
start "bananaz bot" /min "%GODOT%" --headless --path . res://scenes/online.tscn -- join=127.0.0.1 port=24642 bot
"%GODOT%" --path . -- online=127.0.0.1:24642 %*
endlocal
