#requires -Version 3 -Modules ScheduledTasks, ServerManager
# Add any features required.
Start-Transcript -Path $PSScriptRoot\FirstRun.log

Get-WindowsFeature |
Where-Object -Property InstallState -EQ -Value Removed |
Install-WindowsFeature -Source D:\sources\sxs -Verbose 
$features = Get-Content -Path $PSScriptRoot\Features.txt
Install-WindowsFeature $features  -Verbose 
$features = Get-Content -Path $PSScriptRoot\FeaturesIncludingSub.txt
Install-WindowsFeature $features -IncludeAllSubFeature -Verbose 
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