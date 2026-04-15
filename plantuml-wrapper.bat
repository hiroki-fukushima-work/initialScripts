@echo off
setlocal

REM PlantUML JAR のパス
set PLANTUML_JAR="%~d0%~p0lib\plantuml-1.2025.4.jar"

REM Java 実行ファイルのパスを取得
for /f "delims=" %%i in ('where java') do (
    set "JAVA_CMD=%%i"
    goto :found
)

:found
REM PlantUML を実行（標準出力のみ）
REM echo "%JAVA_CMD%" -jar %PLANTUML_JAR% %*
"%JAVA_CMD%" -Dfile.encoding=UTF-8 -Duser.language=ja -Duser.country=JP -jar %PLANTUML_JAR% %*

endlocal
