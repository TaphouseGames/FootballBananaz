@echo off
rem The kit painter: brush by hand which parts of a player are jersey, pants
rem and socks (see tools/kit_painter.gd).
rem
rem Usage: tools\kit_painter.bat [player=<id>]
rem   player=fuji_stem   opens on that player
rem Set GODOT to the Godot console exe if it is not where this file expects it.
setlocal
if "%GODOT%"=="" set GODOT=C:\Users\Andre\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe
cd /d "%~dp0.."
"%GODOT%" --path . res://tools/kit_painter.tscn -- %*
endlocal
