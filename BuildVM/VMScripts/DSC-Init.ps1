#region cleanup
Start-Transcript -Path $PSScriptRoot\DSC-Init.log 
Get-ScheduledTask -TaskName AtStartup | Unregister-ScheduledTask -Confirm:$false
Remove-Item -Path c:\unattend.xml
#endregion


#region Start-DSC
Update-xDscEventLogStatus -Channel Analytic -Status Enabled
Update-xDscEventLogStatus -Channel Debug -Status Enabled
Set-DscLocalConfigurationManager  -Path "$PSScriptRoot\ServerConfig" -Verbose
Start-DscConfiguration -Path "$PSScriptRoot\ServerConfig"  -Force -Wait -Verbose
#endregion

Stop-Transcript