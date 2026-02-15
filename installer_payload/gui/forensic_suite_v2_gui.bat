@echo off
setlocal

REM Move from gui\ to the suite root
cd /d "%~dp0.."

REM Activate venv
call venv\Scripts\activate.bat

REM Launch GUI
python -m forensic_suite_v2.cli gui

endlocal

