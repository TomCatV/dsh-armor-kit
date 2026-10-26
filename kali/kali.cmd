@echo off
REM kali shim (cmd 入口) —— 转发进 kali-redteam 容器
REM 完整逻辑见同目录 kali.ps1
setlocal

set CONTAINER=kali-redteam

REM 自检
if "%~1"=="--check" (
  docker exec %CONTAINER% bash -lc "for t in nmap masscan sqlmap hydra john hashcat ffuf gobuster dirsearch nikto whatweb chisel proxychains4 smbclient enum4linux nc socat python3; do printf '  %-22s ' %%t; command -v %%t >/dev/null 2>&1 && echo OK || echo MISS; done"
  exit /b %ERRORLEVEL%
)

REM 交互 shell
if "%~1"=="--shell" (
  docker exec -it %CONTAINER% bash -l
  exit /b %ERRORLEVEL%
)
if "%~1"=="--sh" (
  docker exec -it %CONTAINER% bash -l
  exit /b %ERRORLEVEL%
)

if "%~1"=="" (
  echo 用法: kali ^<command^> [args...]
  echo   kali nmap -sV TARGET    转发进容器执行
  echo   kali --shell            进容器交互 shell
  echo   kali --check            自检工具链
  exit /b 0
)

REM 容器存在性
docker inspect -f "{{.State.Running}}" %CONTAINER% >nul 2>&1
if errorlevel 1 (
  echo [kali] 容器 %CONTAINER% 不存在。先跑: scripts\kali-setup.ps1
  exit /b 1
)

docker start %CONTAINER% >nul 2>&1

REM 拼接命令并转发
setlocal EnableDelayedExpansion
set "CMD="
:loop
if "%~1"=="" goto :run
set "CMD=!CMD! %~1"
shift
goto :loop

:run
docker exec -it %CONTAINER% bash -lc "!CMD!"
exit /b %ERRORLEVEL%
