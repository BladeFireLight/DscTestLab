
function Set-VmLcm
{
    [CmdletBinding()]
    Param
    (
        $VirtualHardDiskRootPath = (Get-VMHost).VirtualHardDiskPath,
        # Path to Virtual Machine definition
        $VirtualMachinePath = (Get-VMHost).VirtualMachinePath,


        # Name for the VM
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({
                    ((Get-VM $_ -ErrorAction SilentlyContinue) -or
                    (Test-Path -Path "$VirtualHardDiskRootPath\$_.vhdx"))
        })]
        $VMName,

        # Path script to use as AtBoot (must also remove AtBoot task) 
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({
                    Test-Path $_ -PathType Leaf
        })]
        $InitializeScriptPath,

        # Path to folder containing localhost.mof and localhost.meta.mof
        $LocalhostMofFolder,
        # Path to configuration MOF
        $ConfigMofPath,
        # Multiling string content of Meta MOF
        $MetaMofContent,
        # Path to DSC REsorces to copy
        [ValidateScript({
                    Test-Path $_ -PathType Container
        })]
        $DSCResorcePath


    )
    $ParametersToPass = @{}
    foreach ($key in ('Whatif', 'Verbose', 'Debug'))
    {
        if ($PSBoundParameters.ContainsKey($key)) 
        {
            $ParametersToPass[$key] = $PSBoundParameters[$key]
        }
    }
    $vhdPath = "$VirtualHardDiskRootPath\$VMName.vhdx"
    $MountPath = "$env:temp\$([System.IO.Path]::GetRandomFileName())"
    
    try 
    {
        if (Get-VM $VMName | Where-Object -Property state -EQ -Value 'running')
        {
            Stop-VM $VMName
            while (Get-VM $VMName | Where-Object -Property state -EQ -Value 'running')
            {
                Write-Verbose -Message "Wating for $VMName to stop"
                Start-Sleep -Seconds 30
            }
        }
        Write-Verbose -Message "Mounting [$vhdPath] to [$MountPath]"
        mkdir $MountPath -ErrorAction Stop @ParametersToPass
        Mount-WindowsImage -ImagePath "$vhdPath" -Path "$MountPath" -Index 1 -ErrorAction Stop @ParametersToPass
        Copy-Item "$InitializeScriptPath" "$MountPath\PSTemp\AtStartup.ps1" -Force @ParametersToPass
        if ($LocalhostMofFolder)
        {
            Test-Path "$LocalhostMofFolder\localhost.mof" -ErrorAction Stop
            mkdir $MountPath\PSTemp\serverConfig -ErrorAction SilentlyContinue
            Copy-Item "$LocalhostMofFolder\localhost*" "$MountPath\PSTemp\serverConfig\" @ParametersToPass
        }
        else 
        { 
            if  ($ConfigMofPath)
            {
                Test-Path $ConfigMofPath -ErrorAction stop
                Copy-Item "$ConfigMofPath" "$MountPath\Windows\System32\Configuration\Pending.mof" @ParametersToPass
            }
            if ($MetaMofContent)
            {
                Set-Content -Path "$MountPath\Windows\System32\Configuration\metaconfig.mof" -Value $MetaMofContent -Encoding unicode @ParametersToPass
            }
        }
        if ($DSCResorcePath)
        {
            Copy-Item "$DSCResorcePath\*" "$MountPath\Program Files\WindowsPowerShell\Modules" -Recurse @ParametersToPass
        }
    }
    catch
    {
        $msg = "Failed $($_.Exception.Message)"
        Write-Error $msg
        throw 'Error Bootstraping DSC'
    }
    finally
    {
        Dismount-WindowsImage -Path "$MountPath" -Save @ParametersToPass
    }
}
