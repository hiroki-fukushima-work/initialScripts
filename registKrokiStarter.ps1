$scriptPath = Split-Path -Path $MyInvocation.MyCommand.Path -Parent

$taskName = "KrokiStarter"

$batPath = join-path $scriptPath "startKroki.bat"

$action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c `"$batPath`""
$trigger = New-ScheduledTaskTrigger -AtLogOn
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERNAME" -LogonType Interactive -RunLevel Highest

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Force
