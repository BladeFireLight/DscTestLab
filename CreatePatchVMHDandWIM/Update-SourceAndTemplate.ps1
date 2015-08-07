#requires -Version 3 -Modules Dism, Hyper-V
#Wrapper arround Convert-WindowsImage script to it acts like a function. 
function Convert-WindowsImage
{
  Param
  (
    [Parameter(ParameterSetName = 'SRC', Mandatory = $true, ValueFromPipeline = $true)]
    [Alias('WIM')]
    [string]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({
          Test-Path -Path $(Resolve-Path $_)
        }
    )]
    $SourcePath,

    [Parameter(ParameterSetName = 'SRC')]
    [Alias('VHD')]
    [string]
    [ValidateNotNullOrEmpty()]
    $VHDPath,

    [Parameter(ParameterSetName = 'SRC')]
    [Alias('WorkDir')]
    [string]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({
          Test-Path $_
        }
    )]
    $WorkingDirectory = $pwd,

    [Parameter(ParameterSetName = 'SRC')]
    [Alias('Size')]
    [UInt64]
    [ValidateNotNullOrEmpty()]
    [ValidateRange(512MB, 64TB)]
    $SizeBytes        = 40GB,

    [Parameter(ParameterSetName = 'SRC')]
    [Alias('Format')]
    [string]
    [ValidateNotNullOrEmpty()]
    [ValidateSet('VHD', 'VHDX')]
    $VHDFormat        = 'VHD',

    [Parameter(ParameterSetName = 'SRC')]
    [Alias('DiskType')]
    [string]
    [ValidateNotNullOrEmpty()]
    [ValidateSet('Dynamic', 'Fixed')]
    $VHDType          = 'Dynamic',

    [Parameter(ParameterSetName = 'SRC')]
    [Alias('Unattend')]
    [string]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({
          Test-Path -Path $(Resolve-Path $_)
        }
    )]
    $UnattendPath,

    [Parameter(ParameterSetName = 'SRC')]
    [string]
    [ValidateNotNullOrEmpty()]
    $Feature,

    [Parameter(ParameterSetName = 'SRC')]
    [Alias('SKU')]
    [string]
    [ValidateNotNullOrEmpty()]
    $Edition,

    [Parameter(ParameterSetName = 'SRC')]
    [Parameter(ParameterSetName = 'UI')]
    [string]
    $BCDBoot          = 'bcdboot.exe',

    [Parameter(ParameterSetName = 'SRC')]
    [Parameter(ParameterSetName = 'UI')]
    [switch]
    $Passthru,

    [Parameter(ParameterSetName = 'UI')]
    [switch]
    $ShowUI,

    [Parameter(ParameterSetName = 'SRC')]
    [Parameter(ParameterSetName = 'UI')]
    [string]
    [ValidateNotNullOrEmpty()]
    [ValidateSet('None', 'Serial', '1394', 'USB', 'Local', 'Network')]
    $EnableDebugger = 'None',

    [Parameter(ParameterSetName = 'SRC')]
    [string]
    [ValidateNotNullOrEmpty()]
    [ValidateSet('MBR', 'GPT')]
    $VHDPartitionStyle = 'MBR',

    [Parameter(ParameterSetName = 'SRC')]
    [string]
    [ValidateNotNullOrEmpty()]
    [ValidateSet('NativeBoot', 'VirtualMachine')]
    $BCDinVHD = 'VirtualMachine',

    [Parameter(ParameterSetName = 'SRC')]
    [Switch]
    $ExpandOnNativeBoot = $true,

    [Parameter(ParameterSetName = 'SRC')]
    [Switch]
    $RemoteDesktopEnable = $False,

    [Parameter(ParameterSetName = 'SRC')]
    [string]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({
          Test-Path -Path $(Resolve-Path $_)
        }
    )]
    $Driver

  )
  #$psboundparameters

  . "$($PSScriptRoot)\Convert-WindowsImage.ps1" @psboundparameters
}


function Update-SourceAndTemplate
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

    # Create WIM Only
    [switch]
    $WimOnly,

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
      New-Item -ItemType directory -Path $OutPath -ErrorAction Stop -Verbose
    }
    Write-Verbose -Message "Testing $WorkingFolder" 
    if (-not (Test-Path $WorkingFolder)) 
    {
      Write-Verbose -Message "Creating $WorkingFolder" 
      New-Item -ItemType directory -Path $WorkingFolder -ErrorAction Stop -Verbose
    }
    if (-not (Test-Path -Path "$WorkingFolder\Mount" )) 
    {
      mkdir -Path "$WorkingFolder\Mount" -Verbose
    }
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
    #region cleanup target WIM
    if (Test-Path -Path "$WorkingFolder\$($vmType).wim")
    {
      Remove-Item -Path "$WorkingFolder\$($vmType).wim" -Verbose
    }
    #endregion  
    
    #region StartVM and wait
    Write-Verbose -Message "starting vm : $vmType"
    Start-VM $vmType -Verbose
    Start-Sleep -Seconds 30
    while (Get-VM $vmType | Where-Object -Property state -EQ -Value 'running')
    {
      Write-Verbose -Message "Wating for $vmType to stop" 
      Start-Sleep -Seconds 30
    }
    $vhdFile = (Get-VM $vmType | Get-VMHardDiskDrive -Verbose).Path
    
    #region Sysprep
    if ($vmType -eq 'Template')
    {
      Write-Verbose -Message "Copying $vhdFile to $WorkingFolder\$($vmType)_Sysprep.vhdx"
      Copy-Item -Path "$vhdFile" -Destination "$WorkingFolder\$($vmType)_Sysprep.vhdx" -Force -Verbose
      $vhdFile = "$WorkingFolder\$($vmType)_Sysprep.vhdx"
      $vmName = "$($vmType)_Sysprep"
      New-VM -Name $vmName -VHDPath $vhdFile -MemoryStartupBytes 1024MB -Generation 2 -Verbose| 
      Set-VMProcessor -Count 2 -Verbose
      
      Write-Verbose -Message "Adding SysPrep script to $vhdFile" 
      Mount-WindowsImage -ImagePath $vhdFile -Path "$WorkingFolder\Mount" -Index 1 -Verbose
      Copy-Item -Path "$PSScriptRoot\SysPrep.ps1" -Destination "$WorkingFolder\Mount\PSTemp\AtStartup.ps1" -Force -Verbose
      Dismount-WindowsImage -Path "$WorkingFolder\Mount" -Save -Verbose
      Write-Verbose -Message "Starting Cleanup and Sysprep of $vmName" 
      Start-VM $vmName -Verbose
      Start-Sleep -Seconds 30
      while (Get-VM $vmName | Where-Object -Property state -EQ -Value 'running')
      {
        Write-Verbose -Message "Wating for $vmName to stop"
        Start-Sleep -Seconds 30
      }
      Remove-VM $vmName -Force
    }
    #endregion
    
    #region Create WIM
    Write-Verbose -Message "Creating WIM from $vhdFile"
    Mount-WindowsImage -ImagePath "$vhdFile" -Path "$WorkingFolder\Mount" -Index 1 -Verbose
    
    New-WindowsImage -CapturePath "$WorkingFolder\Mount" -Name "2012r2_$vmType" -ImagePath "$WorkingFolder\$($vmType).wim" -Description "2012r2 $vmType Patched $(Get-Date)" -Verify -Verbose
    Dismount-WindowsImage -Path "$WorkingFolder\Mount" -Discard -Verbose


    if ($vmType -eq 'Template')
    {
      $vhdFile = "$WorkingFolder\$($vmType)_Sysprep.vhdx"
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
      Remove-Item -Path "$WorkingFolder\$($vmType).wim" -Force -Verbose
      Remove-Item -Path "$WorkingFolder\$($vmType)_Sysprep.vhdx" -Force -Verbose
    }
    #endregion
    if ($OutPath -ne $WorkingFolder)
    {
      Write-Verbose -Message "Moving $vmType to $OutPath"
      Copy-Item "$WorkingFolder\$($vmType)*.vhdx" $OutPath -Force -Verbose
      Copy-Item "$WorkingFolder\$($vmType).wim" $OutPath -Force -Verbose -ErrorAction SilentlyContinue
    }  
  }

  if ($OutPath -ne $WorkingFolder)
  {
    Remove-Item -Path $WorkingFolder -Recurse -Force
  }
}
Start-Transcript -Path "$env:ALLUSERSPROFILE\Logs\UpdateSorce.log"
Update-SourceAndTemplate -OutPath G:\UpdateOut -WorkingFolder G:\UpdateWorking -Verbose 
Stop-Transcript