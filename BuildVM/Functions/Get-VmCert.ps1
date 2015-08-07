
function Get-VMCert
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

        # Path to location to store cert 
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({
                    Test-Path $_ -PathType Container
        })]
        $CertOutPath,

        # location of vert relitive to C: of VM
        $VMCertPath


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
        Write-Verbose -Message "[$vhdPath] [$MountPath]"
        mkdir $MountPath -ErrorAction Stop @ParametersToPass
        Mount-WindowsImage -ImagePath "$vhdPath" -Path "$MountPath" -Index 1 -ErrorAction Stop @ParametersToPass
        Copy-Item "$MountPath\$VMCertPath" "$CertOutPath\$VMName.crt"
    }
    catch
    {
        $msg = "Failed $($_.Exception.Message)"
        Write-Error $msg
        throw 'Error extracting Certificate'
    }
    finally
    {
        Dismount-WindowsImage -Path "$MountPath" -Discard @ParametersToPass
    }
}
