#requires -Version 3 -Modules Dism, Hyper-V, ScheduledTasks

#region Import helper functions

  . "$($PSScriptRoot)\Convert-WindowsImage.ps1" 
#endregion

#Creates fully patched and compatcted CORE VHDX and Fully Patched GUI WIM with -Features installed. and Places them in -OutPath 
function Start-ImageBuild
{
  [CmdletBinding()]
  [Alias()]
  Param
  (
    # OutPath
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [Alias('op')] 
    [String]
    $OutPath,

    # ISO Path
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [Alias('ip')] 
    [String]
    $IsoPath,

    # VMSwitch to attach to
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [Alias('vs')] 
    [String]
    $VmSwitch,
        
    # Create WIM Only
    [switch]
    $WimOnly,

    # Iso Core Edition
    [int]
    [Alias('CoreEdition')] 
    $IsoCoreEdition = 3,

    # Iso GUI Edition
    [int]
    [Alias('GuiEdition')] 
    $IsoGuiEdition = 4,

    #features used by get-windowsFeature that you want installed on the WIM
    # [string]
    # [ValidateNotNullOrEmpty()]
    # $Feature,

    #Save patched vhdx for use with update-ImageBuild
    [switch]
    $SavedPatchVHDX,

    # Working Folder
    [Parameter()]
    [Alias('wf')] 
    [String]
    $WorkingFolder = $OutPath
  )
  #region validate input and dependent files
  Try 
  {
    Write-Verbose -Message "Testing $OutPath" 
    if (-not (Test-Path $OutPath)) 
    {
      Write-Verbose -Message "Creating $OutPath" 
      New-Item -ItemType directory -Path $OutPath -ErrorAction Stop
    }
    Write-Verbose -Message "Testing $WorkingFolder" 
    if (-not (Test-Path $WorkingFolder)) 
    {
      Write-Verbose -Message "Creating $WorkingFolder" 
      New-Item -ItemType directory -Path $WorkingFolder -ErrorAction Stop
    }
    Write-Verbose -Message "Testing $VmSwitch" 
    $null = Get-VMSwitch $VmSwitch -ErrorAction Stop
    Write-Verbose -Message "Testing $IsoPath" 
    $null = Test-Path -Path $IsoPath -ErrorAction stop
    Write-Verbose -Message "Testing $PSScriptRoot\unattend.xml" 
    $null = Test-Path -Path $PSScriptRoot\unattend.xml -ErrorAction stop
    Write-Verbose -Message "Testing $PSScriptRoot\Convert-WindowsImage.ps1" 
    $null = Test-Path -Path $PSScriptRoot\Convert-WindowsImage.ps1 -ErrorAction stop
  }
  catch 
  {
    $msg = "Failed $($_.Exception.Message)"
    Write-Error $msg
    throw 'Input validation failed'
  }
  #endregion

    
    
  if ($WimOnly) 
  {
    $vmSet = 'Source'
  }
  else 
  {
    $vmSet = 'Source', 'Template'
  }
  
  foreach ($vmType in $vmSet ) 
  {
    #region Create VM
    $vhdFile = "$($vmType)_Patch.vhdx"
    $vmName = "$($vmType)"

    #<#
    # Remove any previous VMs
    if (Test-Path -Path "$WorkingFolder\$($vmSet).wim")
    { 
      Write-Warning -Message "Removinmg old WIM file: $WorkingFolder\$($vmSet).wim" 
      Remove-Item -Path "$WorkingFolder\$($vmSet).wim" -Force
    } 

    if (Test-Path -Path $WorkingFolder\$vhdFile) 
    {
      Write-Warning -Message "Removinmg old vhdx file: $WorkingFolder\$vhdFile" 
      Remove-Item -Path "$WorkingFolder\$vhdFile" -Force
    }
    if (Get-VM -Name "$($vmType)" -ErrorAction SilentlyContinue) 
    {
      Write-Warning -Message "Removinmg old vm $($vmType)" 
      Remove-VM -Name "$($vmType)" -Force
    }

    Write-Verbose -Message "Start creation of $vmType" 

    if ($vmType -eq 'Template') 
    {
      $UseEdition = $IsoCoreEdition 
    }
    else 
    {
      $UseEdition = $IsoGuiEdition
    }

    $CwiParamaters = @{
      SourcePath        = $IsoPath
      VHDPath           = "$WorkingFolder\$vhdFile"
      #SizeBytes         = 40GB
      VHDFormat         = 'VHDX'
      VHDPartitionStyle = 'GPT'
      VHDType           = 'Dynamic'
      UnattendPath      = "$PSScriptRoot\unattend.xml"
      Edition           = $UseEdition
    }
    $CwiParamaters |Format-Table
       
    Write-Verbose -Message 'Creating VHDX from ISO' 
    #. "$($PSScriptRoot)\Convert-WindowsImage.ps1" @Paramaters -Passthru 
    Convert-WindowsImage  @CwiParamaters -Passthru
    break
    if (-not (Test-Path -Path "$WorkingFolder\Mount" )) 
    {
      mkdir -Path "$WorkingFolder\Mount" -Verbose
    }
    Mount-WindowsImage -ImagePath "$WorkingFolder\$vhdFile" -Path "$WorkingFolder\Mount" -Index 1
    if (-not (Test-Path -Path "$WorkingFolder\Mount\PSTemp")) 
    {
      mkdir -Path "$WorkingFolder\Mount\PSTemp" -Verbose
    }
    Copy-Item -Path "$PSScriptRoot\$($vmType)-FirstRun.ps1" -Destination "$WorkingFolder\Mount\PSTemp\FirstRun.ps1" -Verbose
    Copy-Item -Path "$PSScriptRoot\$($vmType)-Features.txt" -Destination "$WorkingFolder\Mount\PSTemp\Features.txt" -ErrorAction SilentlyContinue -Verbose
    Copy-Item -Path "$PSScriptRoot\$($vmType)-FeaturesIncludingSub.txt" -Destination "$WorkingFolder\Mount\PSTemp\FeaturesIncludingSub.txt" -ErrorAction SilentlyContinue -Verbose
    Copy-Item -Path "$PSScriptRoot\WinUpdate.ps1" -Destination "$WorkingFolder\Mount\PSTemp\AtStartup.ps1" -Verbose
  
    Dismount-WindowsImage -Path "$WorkingFolder\Mount" -Save
    
    Write-Verbose -Message "Creating $vmName" 
    New-VM -Name $vmName -VHDPath "$WorkingFolder\$vhdFile" -MemoryStartupBytes 1024MB -SwitchName $VmSwitch -Generation 2 -Verbose| 
    Set-VMProcessor -Count 2 -Verbose

    if ($vmType -eq 'Source') 
    {
      Add-VMDvdDrive -Path $IsoPath -VMName $vmName -Verbose
    }
    Write-Verbose -Message "Starting Patchrun on $vmName" 
    Start-VM $vmName -Verbose
    #endregion

    #region Wait for Patch
    while (Get-VM $vmName | Where-Object -Property state -EQ -Value 'running')
    {
      Write-Verbose -Message "Wating for $vmName to stop" 
      Start-Sleep -Seconds 30
    }
    #endregion
    
    #region Sysprep
    if ($vmType -eq 'Template')
    {
      Write-Verbose -Message "Copying $($vmType)_Patch.vhdx to$($vmType)_Sysprep.vhdx"
      Copy-Item -Path "$WorkingFolder\$($vmType)_Patch.vhdx" -Destination "$WorkingFolder\$($vmType)_Sysprep.vhdx" -Force -Verbose
      $vhdFile = "$($vmType)_Sysprep.vhdx"
      $vmName = "$($vmType)_Sysprep"
      New-VM -Name $vmName -VHDPath "$WorkingFolder\$vhdFile" -MemoryStartupBytes 1024MB -Generation 2 -Verbose | 
      Set-VMProcessor -Count 2 -Verbose
      
      Write-Verbose -Message "Adding SysPrep script to $WorkingFolder\$vhdFile" 
      Mount-WindowsImage -ImagePath "$WorkingFolder\$vhdFile" -Path "$WorkingFolder\Mount" -Index 1 -Verbose
      Copy-Item -Path "$PSScriptRoot\SysPrep.ps1" -Destination "$WorkingFolder\Mount\PSTemp\AtStartup.ps1" -Force -Verbose
      Dismount-WindowsImage -Path "$WorkingFolder\Mount" -Save -Verbose
      Write-Verbose -Message "Starting Cleanup and Sysprep of $vmName" 
      Start-VM $vmName -Verbose
      while (Get-VM $vmName | Where-Object -Property state -EQ -Value 'running')
      {
        Write-Verbose -Message "Wating for $vmName to stop"
        Start-Sleep -Seconds 30
      }
      Remove-VM $vmName -Force -Verbose
    }
    
    #endregion
    
    #region Create WIM
    Write-Verbose -Message "Creating WIM from $WorkingFolder\$vhdFile"
    Mount-WindowsImage -ImagePath "$WorkingFolder\$vhdFile" -Path "$WorkingFolder\Mount" -Index 1 -Verbose
    
    New-WindowsImage -CapturePath "$WorkingFolder\Mount" -Name "2012r2_$vmType" -ImagePath "$WorkingFolder\$($vmType).wim" -Description "2012r2 $vmType Patched $(Get-Date)" -Verify -Verbose
    Dismount-WindowsImage -Path "$WorkingFolder\Mount" -Discard -Verbose


    if ($vmType -eq 'Template')
    {
      $vhdFile = "$($vmType)_Sysprep.vhdx"
      $CwiParamaters = @{
        SourcePath        = "$WorkingFolder\$($vmType).wim"
        VHDPath           = "$WorkingFolder\$($vmType)_Production.vhdx"
        SizeBytes         = 40GB
        VHDFormat         = 'VHDX'
        VHDPartitionStyle = 'GPT'
        VHDType           = 'Dynamic'
        Edition           = 1
      }
      $CwiParamaters | Format-Table
        
      Write-Verbose -Message " Creating VHDX from WIM : $WorkingFolder\$($vmType).wim"
      Convert-WindowsImage  @CwiParamaters -Passthru -Verbose
      Write-Verbose -Message 'Removing Temp files' 
      Remove-Item -Path "$WorkingFolder\$($vmType)_Sysprep.vhdx" -Force
    }
    #endregion

    #region Cleanup
    if ($OutPath -ne $WorkingFolder)
    {
      Write-Verbose -Message "Moving $vmType to $OutPath"
      Remove-VM $vmType -Force -Verbose
      Copy-Item "$WorkingFolder\$($vmType)*.vhdx" $OutPath -Force -Verbose
      Copy-Item "$WorkingFolder\$($vmType).wim" $OutPath -Force -Verbose
      Write-Verbose -Message "Creating vm : $vmType"
      New-VM -Name $vmType -VHDPath "$OutPath\$($vmType)_Patch.vhdx" -MemoryStartupBytes 1024MB -SwitchName $VmSwitch -Generation 2 | 
      Set-VMProcessor -Count 2
    }
    #endregion
  }
  #region remove working if diferent from Out
  if ($OutPath -ne $WorkingFolder)
  {
    Write-Verbose -Message "Cleandup of $WorkingFolder"
    Remove-Item -Path $WorkingFolder -Recurse -Force -Verbose
  }
  #endregion
  
  #region setup Monthly update
  if ( -not (Get-ScheduledTask -TaskName UpdateSourceAndTemplate -ErrorAction SilentlyContinue))
  {
    $Paramaters = @{
      Action   = New-ScheduledTaskAction -Execute '%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File $PSScriptRoot\Update-SourceAndTemplate.ps1"
      Trigger  = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Wednesday -At 1AM 
      Settings = New-ScheduledTaskSettingsSet
    }
    $TaskObject = New-ScheduledTask @Paramaters -Verbose
    Register-ScheduledTask UpdateSourceAndTemplate -InputObject $TaskObject -User 'nt authority\system' -Verbose 
  }
  #endregion
}

Start-Transcript -Path $env:ALLUSERSPROFILE\logs\ImageBuild.log

# Production
#Start-ImageBuild -OutPath 'D:\BuildOut' -WorkingFolder 'd:\BuildWorking' -IsoPath 'D:\ISO\WindowsServer\Win_Svr_2012_R2_64Bit_English.ISO' -VmSwitch Isolated1 -Verbose
# Lab
Start-ImageBuild -OutPath 'g:\BuildOut' -WorkingFolder 'G:\BuildWorking' -IsoPath 'C:\iso\Server2012R2.ISO' -VmSwitch TestLab -Verbose

Stop-Transcript
