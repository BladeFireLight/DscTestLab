#requires -Version 1 -Modules ScheduledTasks, ServerManager
#region cleanup
Start-Transcript -Path c:\sysprep.log 
Get-ScheduledTask -TaskName AtStartup | Unregister-ScheduledTask -Confirm:$false
Remove-Item -Path c:\unattend.xml
Get-ChildItem -Path c:\pstemp\ -Exclude AtStartup.ps1 | Remove-Item 
Get-WindowsFeature |
Where-Object -FilterScript {
  $_.Installed -eq 0 -and $_.InstallState -eq 'Available'
} |
Uninstall-WindowsFeature -remove
Dism.exe /online /cleanup-image /StartComponentCleanup /ResetBase
Defrag.exe c: /UVX
#endregion

#region sysprep
C:\Windows\System32\sysprep\sysprep.exe /quiet /generalize /oobe /shutdown /mode:vm
Stop-Transcript
#endregion
