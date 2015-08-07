
if (-not ($vmname)) 
{
    $vmname = 'Root-CA'
}

$certpath = "$PSScriptRoot\$vmname.crt"
if (-not(Test-Path $certpath)) 
{
    throw 'Certificate not found' 
}

$cert = "$PSScriptRoot\$vmname.crt"
$certPrint = New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Certificate2
$certPrint.Import("$cert")
try 
{ 
    $LocalAdmin = Import-Clixml -Path $PSScriptRoot\$vmname.LocalAdminCred.xml
    $RemoteUser = Import-Clixml -Path $PSScriptRoot\$vmname.RemoteUserCred.xml
}
catch 
{
    throw 'error importing passwords from xml'
}


$ConfigData = @{
    AllNodes = @(     
        @{
            NodeName        = 'localhost'
            CertificateFile = "$PSScriptRoot\$vmname.crt"
            Thumbprint      = "$($certPrint.Thumbprint)"
        }; 
    )
}

configuration RootCA
{
    Import-DscResource -ModuleName xComputerManagement, xAdcsDeployment, xNetworking,
        PSDesiredStateConfiguration

    node $AllNodes.NodeName 
    {    
        xIPAddress Ethernet
        {
            InterfaceAlias = 'Ethernet 4'
            IPAddress = '10.20.1.51'
            AddressFamily = 'IPv4'
            SubnetMask = 24
        }

        User LocalAdmin
        {
            UserName = 'Administrator'
            Disabled = $false
            Ensure = 'Present'
            Password = $LocalAdmin
            PasswordChangeNotAllowed = $false
            PasswordNeverExpires = $true
        }
        xComputer ComputerName
        {
            Name = 'Root-CA'
            WorkGroupName = 'Workgroup'
        }
 
        File Source
        {
            DestinationPath = 'c:\Source.wim'
            Credential = $RemoteUser
            Ensure = 'Present'
            SourcePath = '\\10.20.1.41\DSC\WIM\Source.wim'
            Type = 'File'
            DependsOn = '[xIPAddress]Ethernet'
        }
        WindowsFeature ADCS_Cert_Authority
        {
            Name = 'ADCS-Cert-Authority'
            DependsOn = '[File]Source'
            Ensure = 'Present'
            Source = 'WIM:c:\Source.wim:1'
        }     
        xAdcsCertificationAuthority Root_CA
        {
            CAType = 'StandaloneRootCA'
            Credential = $LocalAdmin
            CACommonName = 'Root-CA'
            DependsOn = '[WindowsFeature]ADCS_Cert_Authority', '[xComputer]ComputerName'
            Ensure = 'Present'
            
        }
        Script 'SetRevocationList'
        {
            GetScript = {
                (Get-CACrlDistributionPoint).Uri
            }
            SetScript = {
                $crllist = Get-CACrlDistributionPoint; foreach ($crl in $crllist) 
                {
                    Remove-CACrlDistributionPoint $crl.uri -Force
                }
                Add-CACRLDistributionPoint -Uri C:\Windows\System32\CertSrv\CertEnroll\%3%8.crl -PublishToServer -Force
                Add-CACRLDistributionPoint -Uri http://pki.contoso.com/pki/%3%8.crl -AddToCertificateCDP -Force
                $aialist = Get-CAAuthorityInformationAccess; foreach ($aia in $aialist) 
                {
                    Remove-CAAuthorityInformationAccess $aia.uri -Force
                }
                certutil.exe -setreg CA\CRLOverlapPeriodUnits 12
                certutil.exe -setreg CA\CRLOverlapPeriod 'Hours'
                certutil.exe -setreg CA\ValidityPeriodUnits 10
                certutil.exe -setreg CA\ValidityPeriod 'Years'
                certutil.exe -setreg CA\AuditFilter 127
                Restart-Service -Name certsvc
                certutil.exe -crl
            }
            TestScript = {
                if ((Get-CACrlDistributionPoint).Uri -contains 'http://pki.contoso.com/pki/<CAName><CRLNameSuffix>.crl')
                {
                    return $true
                }
                else 
                {
                    return $false
                }
            }
            DependsOn = '[xAdcsCertificationAuthority]Root_CA'
        }
        
        LocalConfigurationManager
        {
            CertificateId = $node.Thumbprint 
            ConfigurationMode = 'ApplyandAutoCorrect'
            RebootNodeIfNeeded = $true
        }
    }
}

RootCA -ConfigurationData $ConfigData -OutputPath "$PSScriptRoot\RootCA"
