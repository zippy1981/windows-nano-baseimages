@echo off
rem Builds nanoserver-base and its -pwsh variant for one Windows version (default 2025), as CI does.
rem   build.cmd [2019|2022|2025]
rem Tags nanoserver-base:ltsc<ver> and nanoserver-base:ltsc<ver>-pwsh. Run the smoke tests afterwards with:
rem   pwsh images\nanoserver-base\smoke-test.ps1 -Image nanoserver-base:ltsc<ver>
rem   pwsh images\nanoserver-base-pwsh\smoke-test.ps1 -Image nanoserver-base:ltsc<ver>-pwsh
setlocal
set WINDOWS_VERSION=%~1
if "%WINDOWS_VERSION%"=="" set WINDOWS_VERSION=2025

rem Hyper-V isolated builds default to 1 GB of memory, which is too little for the Server Core download stage
docker build --memory 4g --build-arg WINDOWS_VERSION=%WINDOWS_VERSION% -t nanoserver-base:ltsc%WINDOWS_VERSION% "%~dp0."
if errorlevel 1 exit /b %errorlevel%

docker build --memory 4g --build-arg WINDOWS_VERSION=%WINDOWS_VERSION% --build-arg BASE_IMAGE=nanoserver-base:ltsc%WINDOWS_VERSION% -t nanoserver-base:ltsc%WINDOWS_VERSION%-pwsh "%~dp0..\nanoserver-base-pwsh"
if errorlevel 1 exit /b %errorlevel%
