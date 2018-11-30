REM force this execution to run in the same folder as this cmd file
cd /d %~dp0 
PowerShell -NoProfile -ExecutionPolicy Bypass -Command ".\local-website-deployment.ps1 --Target=Kudu-Deploy|Out-String -Stream; exit $LastExitCode;"
REM powershell -NoProfile -NoLogo -ExecutionPolicy Unrestricted -Command "& "$pwd\deploy.ps1" 2>&1 | echo"