#requires -Version 2
Function Add-WindowsUpdate

{
  [CmdletBinding()]
  param (
    [string]$Criteria = "IsInstalled=0 and Type='Software' and IsHidden=0" , 
    [switch]$AutoRestart, 
    [Switch]$ShutdownAfterUpdate, 
    [switch]$ForceRestart, 
    [Switch]$ShutdownOnNoUpdate
  ) 

  $resultcode = @{
    0 = 'Not Started'
    1 = 'In Progress'
    2 = 'Succeeded'
    3 = 'Succeeded With Errors'
    4 = 'Failed'
    5 = 'Aborted'
  }

  $updateSession = New-Object -ComObject 'Microsoft.Update.Session'
  
  Write-Progress -Activity 'Updating' -Status 'Checking available updates'  
  $updates = $updateSession.CreateupdateSearcher().Search($Criteria).Updates #| Where {$_.Title -notlike '*Language Pack*'}
  $updates | Select Title | Write-Verbose

  if ($updates.Count -eq 0)  
  {
    Write-Verbose -Message 'There are no applicable updates.' -Verbose
    if ($ShutdownOnNoUpdate)
    {
      Stop-Computer
    }
  }   
  else 
  {
    $downloader = $updateSession.CreateUpdateDownloader()   
    $downloader.Updates = $updates  

    Write-Progress -Activity 'Updating' -Status "Downloading $($downloader.Updates.count) updates" 
    $Result = $downloader.Download()  
    $Result
    if (($Result.Hresult -eq 0) -and (($Result.resultCode -eq 2) -or ($Result.resultCode -eq 3)) ) 
    {
      $updatesToInstall = New-Object -ComObject 'Microsoft.Update.UpdateColl'

      $updates |
      Where-Object -FilterScript {
        $_.isdownloaded
      } |
      ForEach-Object -Process {
        $null = $updatesToInstall.Add($_)
      }
      $installer = $updateSession.CreateUpdateInstaller()
      $installer.Updates = $updatesToInstall


      Write-Progress -Activity 'Updating' -Status "Installing $($installer.Updates.count) updates"
      $installationResult = $installer.Install()
      $installationResult
      $Global:counter = -1
      $installer.updates | Format-Table -AutoSize -Property Title, EulaAccepted, @{
        label      = 'Result'
        expression = {
          $resultcode[$installationResult.GetUpdateResult($Global:counter++).resultCode ]
        }
      } 
      if ($AutoRestart -and $installationResult.rebootRequired) 
      {
        Restart-Computer
      }
      if ($ForceRestart) 
      {
        Restart-Computer
      }
      if ($ShutdownAfterUpdate) 
      {
        Stop-Computer
      }  
    } 
  }
}

Function Get-WindowsUpdate {

    [Cmdletbinding()]
    Param()

    Process {
        try {
            Write-Verbose "Getting Windows Update"
            $Session = New-Object -ComObject Microsoft.Update.Session            
            $Searcher = $Session.CreateUpdateSearcher()            
            $Criteria = "IsInstalled=0 and DeploymentAction='Installation' or IsPresent=1 and DeploymentAction='Uninstallation' or IsInstalled=1 and DeploymentAction='Installation' and RebootRequired=1 or IsInstalled=0 and DeploymentAction='Uninstallation' and RebootRequired=1"            
            $SearchResult = $Searcher.Search($Criteria)           
            $SearchResult.Updates
        } catch {
            Write-Warning -Message "Failed to query Windows Update because $($_.Exception.Message)"
        }
    }
}

Function Show-WindowsUpdate {
    Get-WindowsUpdate |
    Select Title,isHidden,
        @{l='Size (MB)';e={'{0:N2}' -f ($_.MaxDownloadSize/1MB)}},
        @{l='Published';e={$_.LastDeploymentChangeTime}} |
    Sort -Property Published
}

Function Set-WindowsHiddenUpdate {

    [Cmdletbinding()]

    Param(
        [Parameter(ValueFromPipeline=$true,Mandatory=$true)]
        [System.__ComObject[]]$Update,

        [Parameter(Mandatory=$true)]
        [boolean]$Hide
    )

    Process {
        $Update | ForEach-Object -Process {
            if (($_.pstypenames)[0] -eq 'System.__ComObject#{c1c2f21a-d2f4-4902-b5c6-8a081c19a890}') {
                try {
                    $_.isHidden = $Hide
                    Write-Verbose -Message "Setting IsHidden to $Hide for update $($_.Title)"
                } catch {
                    Write-Warning -Message "Failed to perform action because $($_.Exception.Message)"
                }
            } else {
                Write-Warning -Message "Ignoring object submitted"
            }
        }
    }
}

Start-Transcript -Path $PSScriptRoot\Patch.log

Get-WindowsUpdate | Where {
    ($_.Title -Like '*Language Pack*') -or 
    ($_.Title -Match '^Skype') -or 
    ($_.Title -Match '^Internet Explorer 11 for')
    } | 
        Set-WindowsHiddenUpdate -Hide $true -Verbose
 
Add-WindowsUpdate -ForceRestart -ShutdownOnNoUpdate 

Stop-Transcript