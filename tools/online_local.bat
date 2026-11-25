@echo off
rem An online match on this one machine: a server, a second person who plays
rem with random buttons, and a window for you. Close the window to end it.
rem
rem Usage: tools\online_local.bat [lag=<ms>] [jitter=<ms>] [loss=<percent>] [nopredict]
rem   lag=50      makes your line 50 ms slower each way (100 ms there and back)
rem   jitter=30   makes it uneven: up to 30 ms more for each message
rem   loss=3      loses 3 messages in a hundred
rem   nopredict   draws your own player where the server has him, to compare
rem Set GODOT to the Godot console exe if it is not where this file expects it.
setlocal
if "%GODOT%"=="" set GODOT=C:\Users\Andre\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe
cd /d "%~dp0.."
start "bananaz server" /min "%GODOT%" --headless --path . res://scenes/server.tscn -- port=24642
timeout /t 6 /nobreak >nul
start "bananaz bot" /min "%GODOT%" --headless --path . res://scenes/online_dev.tscn -- join=127.0.0.1 port=24642 bot
"%GODOT%" --path . res://scenes/online_dev.tscn -- join=127.0.0.1 port=24642 %*
endlocal
