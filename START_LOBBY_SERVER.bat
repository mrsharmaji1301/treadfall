@echo off
rem TREADFALL lobby server for online play. Keep this window open while playing.
cd /d "%~dp0server"
where node >nul 2>nul || (echo Node.js is not installed. Get it from https://nodejs.org and run this again. & pause & exit /b)
node lobby_server.js
pause
