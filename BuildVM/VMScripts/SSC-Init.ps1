Start-Transcript -Path $PSScriptRoot\SSC-Init.log

. "$($PSScriptRoot)\New-SelfSignedCertificateEx.ps1"

$cert = Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object -FilterScript {
    $_.Subject -eq 'CN=DSC SelfSigned Certificate'
}

if (-not $cert)
{
    $pfxfile  = Get-ChildItem -Path "$PSScriptRoot\*DSC Test Certificate.pfx" | Select-Object -First 1
    if (-not $pfxfile)
    {
        $pfxfile = Get-ChildItem -Path '.\*DSC Test Certificate.pfx' | Select-Object -First 1
    }

    if  ($pfxfile)
    {
        $password = ConvertTo-SecureString -String 'password' -Force -AsPlainText
        Import-PfxCertificate -FilePath $pfxfile -Exportable -Password $password `
        -CertStoreLocation Cert:\Localmachine\My
    }
    else
    {
        Write-Verbose -Message 'Creating new Self signed Certificate' -Verbose
        New-SelfSignedCertificateEx -Subject 'CN=DSC SelfSigned Certificate' -StoreLocation LocalMachine -StoreName My -EnhancedKeyUsage 'Client Authentication'
    }
   
    $cert = Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object -Property Subject -EQ -Value 'CN=DSC SelfSigned Certificate'
}

mkdir -Path $PSScriptRoot\CertFile
$certfile = "$PSScriptRoot\CertFile\DSCSelfSignedCertificate.cer"
Export-Certificate -Cert $cert -FilePath $certfile

Stop-Computer

