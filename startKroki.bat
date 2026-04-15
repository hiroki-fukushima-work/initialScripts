@echo off

setlocal

echo ============================
echo       Kroki Starter        
echo ============================

cd %~d0%~p0
echo %~d0%~p0


for /f "delims=" %%i in ('where java') do (
    set "JAVA_PATH=%%i"
    goto :javafound
)

:javafound

REM java.exe の親フォルダ（bin）を除いたパスを JAVA_HOME に設定
for %%i in ("%JAVA_PATH%") do (
    set "JAVA_HOME=%%~dpi"
)

REM bin を除去
set "JAVA_HOME=%JAVA_HOME:~0,-5%"

echo JAVA_HOME is set to: %JAVA_HOME%


set PATH=%JAVA_HOME%\bin;%PATH%
set PLANTUML_JAVA_CMD=%JAVA_HOME%\bin\java.exe
set KROKI_PLANTUML_BIN_PATH=%~d0%~p0\plantuml-wrapper.bat

REM PlantUMLのJARファイルのパスを指定
set KROKI_LISTEN=0.0.0.0:60006

REM java -jar "%~d0%~p0lib\kroki-standalone-server-v0.26.0.jar" --config "%~d0%~p0lib\config.yml"
java -Dplantuml.include.path="%~d0%~p0lib" -Djava.awt.headless=true -Dfile.encoding=UTF-8 -Duser.language=ja -Duser.country=JP -jar "%~d0%~p0lib\kroki-standalone-server-v0.26.0.jar" --config "%~d0%~p0lib\config.yml" --listen %KROKI_LISTEN%

endlocal
