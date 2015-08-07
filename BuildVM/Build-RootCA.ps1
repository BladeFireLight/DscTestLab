stop-vm 'Root-CA' -TurnOff -force -ErrorAction SilentlyContinue
Remove-VM 'Root-CA' -Force -ErrorAction SilentlyContinue
Remove-Item -Path 'G:\Hyper-V\Virtual Hard Disks\Root-CA.vhdx' -ErrorAction SilentlyContinue

#region Configuration
$VMName = 'Root-CA'
$DSCConfigSCript = "$PSScriptRoot\RootCA_Config.ps1"

$Start_Deploy_param = @{
    VHDSourcePath        = 'G:\UpdateOut\Template_Production.vhdx'
    InitializeScriptPath = "$PSScriptRoot\VMScripts\FirstRun.ps1"
    HelperScriptPath     = "$PSScriptRoot\Helpers"
    AtStartupScriptPath  = "$PSScriptRoot\VMScripts\SSC-Init.ps1"
    VMName               = $VMName
    VMSwitch             = 'testlab'
}

$Get_VMCert_param = @{
    VMName      = $VMName
    CertOutPath = "$PSScriptRoot"
    VMCertPath  = '\PStemp\CertFile\DSCSelfSignedCertificate.cer'
}
$Set_VmLcm_param = @{
    InitializeScriptPath = "$PSScriptRoot\VMScripts\DSC-Init.ps1"
    LocalhostMofFolder   = "$PSScriptRoot\RootCA"
    DSCResorcePath       = "$PSScriptRoot\Resorces_RootCA"
}

if (-not (Test-Path -Path $PSScriptRoot\$VMName.LocalAdminCred.xml))
{
    Get-Credential -Message 'RootCA LocalAdmin account' | 
        Export-Clixml -Path $PSScriptRoot\$VMName.LocalAdminCred.xml
}

if (-not (Test-Path -Path $PSScriptRoot\$VMName.RemoteUserCred.xml))
{
    Get-Credential -Message 'User for remote share with source.wim' | 
        Export-Clixml -Path $PSScriptRoot\$VMName.RemoteUserCred.xml
}

#endregion

#region Main script

#region Import Supporting functions
Import-Module -Name "$PSScriptRoot\Functions"
#endregion


#region Create VM and get Cert
Start-Deploy @Start_Deploy_param -Verbose
Get-VMCert @Get_VMCert_param -Verbose
#endregion

#region CreateMOF
. "$DSCConfigSCript"
#endregion

#region start DSC
set-VmLcm -VMName $VMName @Set_VmLcm_param  -verbose
Start-VM -VMName $VMName
#endregion

#endregion
Remove-Module -Name Functions
