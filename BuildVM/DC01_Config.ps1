
if (-not ($vmname)) 
{
    $vmname = 'DC01'
}

$certpath = "$PSScriptRoot\$vmname.crt"
if (-not(Test-Path $certpath)) 
{
    throw "Certificate not found at [$certpath]" 
}

$cert = "$PSScriptRoot\$vmname.crt"
$certPrint = New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Certificate2
$certPrint.Import("$certpath")
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
            CertificateFile = $certpath
            Thumbprint      = "$($certPrint.Thumbprint)"
        }; 
    )
}

configuration ServerConfig
{
    Import-DscResource -ModuleName xComputerManagement, 
        xAdcsDeployment, xNetworking, xActiveDirectory, xDNSServer

    node $AllNodes.NodeName 
    {    
       xIPAddress Ethernet
        {
            InterfaceAlias = 'Ethernet'
            IPAddress = '10.20.1.52'
            DefaultGateway = '10.20.1.1'
            AddressFamily = 'IPv4'
            SubnetMask = 24
        }
        xDNSServerAddress DNS
        {
            Address = '127.0.0.1', '10.20.1.1'
            InterfaceAlias = 'Ethernet'
            AddressFamily = 'IPv4'
        #    DependsOn = '[xIPAddress]Ethernet'
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
            Name = 'DC01'
            #WorkGroupName = 'Workgroup'
        }
 
        #File Source
        #{
        #    DestinationPath = 'c:\Source.wim'
        #    Credential = $RemoteUser
        #    Ensure = 'Present'
        #    SourcePath = '\\10.20.1.41\DSC\WIM\Source.wim'
        #    Type = 'File'
        #    DependsOn = '[xIPAddress]Ethernet'
        #}
        WindowsFeature AD_Domain_Services
        {
            Name = 'AD-Domain-Services'
        #    DependsOn = '[xComputer]ComputerName'
        #    DependsOn = '[File]Source', '[xComputer]ComputerName'
            Ensure = 'Present'
        #    Source = 'WIM:c:\Source.wim:1'
        }     
        WindowsFeature DNS
        {
            Name = 'DNS'
        #    DependsOn =  '[xComputer]ComputerName'
        #    DependsOn = '[File]Source', '[xComputer]ComputerName'
            Ensure = 'Present'
        #    Source = 'WIM:c:\Source.wim:1'
        }     
        WindowsFeature DHCP
        {
            Name = 'DHCP'
        #    DependsOn =  '[WindowsFeature]AD_Domain_Services', '[xComputer]ComputerName'
        #    DependsOn = '[File]Source', '[WindowsFeature]AD_Domain_Services', '[xComputer]ComputerName'
            Ensure = 'Present'
        #    Source = 'WIM:c:\Source.wim:1'
        }     
        xADDomain FirstDC
        {
            DomainAdministratorCredential = $LocalAdmin
            DomainName = 'Contoso.com'
            SafemodeAdministratorPassword = $LocalAdmin
        #    DependsOn = '[WindowsFeature]AD_Domain_Services', '[WindowsFeature]DNS' 
        }
        LocalConfigurationManager
        {
            CertificateId = $node.Thumbprint 
            ConfigurationMode = 'ApplyandAutoCorrect'
            RebootNodeIfNeeded = $true
        }
    }
}

ServerConfig -ConfigurationData $ConfigData -OutputPath "$PSScriptRoot\$vmname"
