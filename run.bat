@echo off
echo Dang khoi dong Server MedPal...
".venv\Scripts\uvicorn.exe" main:app --reload
pause
