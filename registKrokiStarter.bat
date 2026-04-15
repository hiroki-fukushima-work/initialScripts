@echo off

echo ============================
echo       Regist Kroki Starter
echo ============================

cd %~d0%~p0
echo %~d0%~p0

@echo off

:: 管理者権限チェック（管理者なら '1' が返る）
net session >nul 2>&1
if %errorlevel% == 0 (
	echo 管理者権限で PowerShell スクリプトを実行します...

    powershell -ExecutionPolicy Bypass -File "%~dp0registKrokiStarter.ps1
    goto :eof
) else (
    echo 管理者権限が必要です。再起動します...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    goto :eof
)


@echo off

