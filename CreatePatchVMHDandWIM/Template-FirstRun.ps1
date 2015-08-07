#requires -Version 2 -Modules ScheduledTasks, ServerManager
# Add any features required.
Start-Transcript -Path $PSScriptRoot\FirstRun.log

$features = Get-Content -Path $PSScriptRoot\Features.txt
Install-WindowsFeature $features -IncludeAllSubFeature -Verbose 
$features = Get-Content -Path $PSScriptRoot\FeaturesIncludingSub.txt
Install-WindowsFeature $features -Verbose 
$Paramaters = @{
  Action   = New-ScheduledTaskAction -Execute '%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe' -Argument '-NoProfile -ExecutionPolicy Bypass -File C:\PSTemp\AtStartup.ps1'
  Trigger  = New-ScheduledTaskTrigger -AtStartup
  Settings = New-ScheduledTaskSettingsSet
}
$TaskObject = New-ScheduledTask @Paramaters
Register-ScheduledTask AtStartup -InputObject $TaskObject -User 'nt authority\system' -Verbose 
Start-Sleep -Seconds 20
Restart-Computer -Verbose -Force 
Stop-Transcript