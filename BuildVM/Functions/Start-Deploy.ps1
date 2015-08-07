
function Start-Deploy
{
    [CmdletBinding()]
    Param
    (
        $VirtualHardDiskRootPath = (Get-VMHost).VirtualHardDiskPath,
        # Path to Virtual Machine definition
        $VirtualMachinePath = (Get-VMHost).VirtualMachinePath,

        # Path to VHD Template (must be syspreped)
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({
                    Test-Path $_ -PathType Leaf
        })]
        $VHDSourcePath,

        # Name for the VM
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({
                    (-not(Get-VM $_ -ErrorAction SilentlyContinue)) -or
                    (-not(Test-Path -Path $VirtualHardDiskRootPath\$_))
        })]
        $VMName,

        # Path to script to ctreate scedualed task 
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({
                    Test-Path $_ -PathType Leaf
        })]
        $InitializeScriptPath,

        # Path to script to run AtStarup 
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({
                    Test-Path $_ -PathType Leaf
        })]
        $AtStartupScriptPath,

        # Path to helper scripts
        [ValidateScript({
                    Test-Path $_ -PathType Container
        })]
        $HelperScriptPath,

        # VM Switch to connect NIC1 to 
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({
                    Get-VMSwitch $_
        })]
        $VMSwitch,

        # Path to Unattend.xml
        [ValidateScript({
                    (Test-Path -Path $_)
        })]
        $Unattend = "$PSScriptRoot\Unattend.xml"

    )
    $ParametersToPass = @{}
    foreach ($key in ('Whatif', 'Verbose', 'Debug'))
    {
        if ($PSBoundParameters.ContainsKey($key)) 
        {
            $ParametersToPass[$key] = $PSBoundParameters[$key]
        }
    }
    

    #region Prepair VHD
    $MountPath = "$env:temp\$([System.IO.Path]::GetRandomFileName())"
    $vhdDestination = "$VirtualHardDiskRootPath\$VMName.vhdx"
    Try 
    {
        #region Validation
        if (Test-Path -Path $vhdDestination) 
        {
            throw "$vhdDestination exists"
        }
        if (Test-Path -Path $MountPath) 
        {
            throw "$MountPath exists"
        }  
        #endregion
    
        Copy-Item -Path $VHDSourcePath -Destination $VirtualHardDiskRootPath\$VMName.vhdx -ErrorAction Stop @ParametersToPass
        mkdir $MountPath -ErrorAction Stop @ParametersToPass
        Mount-WindowsImage -ImagePath $vhdDestination -Path $MountPath -ErrorAction Stop @ParametersToPass -Index 1
        Copy-Item $Unattend $MountPath\Unattend.xml -ErrorAction Stop @ParametersToPass
        mkdir $MountPath\PSTemp -ErrorAction SilentlyContinue @ParametersToPass
        Copy-Item $InitializeScriptPath  $MountPath\PSTemp\FirstRun.ps1 -ErrorAction Stop  @ParametersToPass
        if ($HelperScriptPath)
        {
            Copy-Item $HelperScriptPath\* $MountPath\PSTemp\ -Recurse
        }
        if ($AtStartupScriptPath) 
        {
            Copy-Item $AtStartupScriptPath $MountPath\PSTemp\AtStartup.ps1 -Recurse
        }
    }
    catch 
    {
        $msg = "Failed $($_.Exception.Message)"
        Write-Error $msg
        throw 'Error Prepairing VHDX'
    }
    finally
    {
        Dismount-WindowsImage -Path $MountPath -Save
    }
    
    #endregion
    
    #region Create and Start VM
    Try
    {
        New-VM -Name $VMName -MemoryStartupBytes 1GB -VHDPath $vhdDestination -SwitchName $VMSwitch  -Generation 2 -ErrorAction stop @ParametersToPass 
        Start-VM $VMName -ErrorAction stop @ParametersToPass 
        while (Get-VM $VMName | Where-Object -Property state -EQ -Value 'running')
        {
            Write-Verbose -Message "Wating for $VMName to stop"
            Start-Sleep -Seconds 30
        }
    }
    catch
    {
        $msg = "Failed $($_.Exception.Message)"
        Write-Error $msg
        throw 'Failed creating VM'
    }
    #endregion
}
