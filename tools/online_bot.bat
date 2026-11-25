@echo off
rem An opponent for the real thing: a second "person" with random buttons who
rem looks for a match through the matchmaker of online.cfg. Run this, then
rem press ONLINE in the game (or the other way round). It ends with its match.
rem Set GODOT to the Godot console exe if it is not where this file expects it.
setlocal
if "%GODOT%"=="" set GODOT=C:\Users\Andre\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe
cd /d "%~dp0.."
"%GODOT%" --headless --path . res://scenes/online.tscn -- find bot
endlocal
