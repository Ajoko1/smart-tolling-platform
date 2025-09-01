@echo off
REM BlockSurvey Submit Command - Batch wrapper
REM This script makes the Python automation tool executable as a command

REM Check if Python is installed
python --version >nul 2>&1
if errorlevel 1 (
    echo ERROR: Python is not installed or not in PATH
    echo Please install Python and try again
    exit /b 1
)

REM Install requirements if they don't exist
if not exist "%~dp0venv" (
    echo Installing dependencies...
    pip install -r "%~dp0requirements.txt"
)

REM Run the Python script with all arguments
python "%~dp0blocksurvey_submit.py" %*
