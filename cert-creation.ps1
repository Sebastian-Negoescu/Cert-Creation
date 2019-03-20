#
# --------- Create certificatet w/ Let's Encrypt --------- #
#
<#
In order to successfully use use this script and create a certificate, make sure that you first and foremost use a custom domain that you own!!!
In the script below we are completing the DNS Challenge - MANUALLY. Just follow the steps on the article below for the ease of the process.

https://github.com/ebekker/ACMESharp/wiki/Quick-Start#method-3---handling-the-dns-challenge-manually

Things to also take in consideration when using the script:
    1. You need to have the ACMESharp module for PowerShell installed --> Install-Module ACMESharp | Import-Module ACMESharp
    2. The script uses the latest Az version for PowerShell with Azure; if you still fancy the AzureRM Module, you can simply adjust the cmdlets below;
        ** just know that when you open PowerShell the session will already have one of the modules loaded so most probably you'll run into a compatibility error if you have both of the modules installed.
#>
#
# --------- Now let the shenanigans begin. :)  --------- #
#
param([string]$HostName = "sn-webapp.usa.cc",
    [string]$CertMailContact = "mailto:sebastian.negoescu@gmail.com", # Don't forget the mailto, or you'll get "contact method is not supported"
    [bool]$EnableLetsEncryptStaging = $false)

function Generate-Certificate($HostName, $Contact, $Staging = $false) {

    [hashtable]$Result = @{}
    $date = Get-Date -Format mmHHddMMyyyy
    
    # Setup Vault Profile
    $profileName = "sn-profile-$date"
    if ($Staging) {
        $profileName = $profileName + "-staging"
    }

    $vaultProfile = Get-ACMEVaultProfile -ProfileName $profileName
    if ($vaultProfile -eq $null) {
        Set-ACMEVaultProfile -ProfileName $profileName -Provider local -VaultParameters @{ RootPath = "C:\Users\s.negoescu\$profileName"; CreatePath = $true}
    }
    
    # Use staging for test purposes, to avoid Let's Encrypt rate limit
    if (!$Staging) {
        Initialize-ACMEVault -VaultProfile $profileName -ErrorAction Continue
        Set-ACMEVault -BaseService LetsEncrypt -VaultProfile $profileName
        New-ACMERegistration -Contacts $Contact -AcceptTos -VaultProfile $profileName -ErrorAction Continue
    }
    else {
        Initialize-ACMEVault -VaultProfile $profileName -BaseService LetsEncrypt-STAGING -ErrorAction Continue
        Set-ACMEVault -BaseService LetsEncrypt-STAGING -VaultProfile $profileName
        New-ACMERegistration -Contacts $Contact -AcceptTos -VaultProfile $profileName -ErrorAction Continue
    }

    # Set aliases
    
    $alias = "$HostName$date"
    $aliasCert = $alias + "-cert"
    $certName = $aliasCert + ".pfx"

    New-ACMEIdentifier -Dns $HostName -Alias $alias -VaultProfile $profileName
    Write-Host "Identifier created : " $alias


    # DNS Challenge
    Write-Host "Get Challenge"
    $challengeResponse = Complete-ACMEChallenge -IdentifierRef $alias -ChallengeType dns-01 -Handler manual -Force -VaultProfile $profileName

    # Get the returned DNS challenges
    $challenges = $challengeResponse.Challenges.Where( {$_.Type -eq "dns-01"})
    $challenge = $challenges[0].Challenge

    # Add the DNS Record
    $resultAddDns = Add-AzDnsTxtRecord -name $challenge.RecordName -value $challenge.RecordValue

    if ($resultAddDns) {
        Submit-ACMEChallenge -IdentifierRef $alias -ChallengeType dns-01 -Force -VaultProfile $profileName
    }
    else {
        Write-Host "Error adding the dns txt record"
    }

    # Let's Encrypt will validate the challenge. It may takes a few seconds. Wait until it's ok.
    $counter = 0
    do
    {
        Start-Sleep -s 10
        $statusIdentifier = (Update-ACMEIdentifier $alias -VaultProfile  $profileName).Status
        $counter++
    } while ($statusIdentifier -notin ('valid') -and ($counter -lt 10))

    if($statusIdentifier -eq "valid"){
           Write-Host $alias " valid"
    }
    else{
        Write-Host $alias " not valid"
        return $false    
    }

    # Generate Certificate
    Write-Host "Generate Certificate"
    New-ACMECertificate $alias -Generate -Alias $aliasCert -VaultProfile $profileName
    Submit-ACMECertificate $aliasCert -VaultProfile $profileName

    # Check Cert generation status
    Write-Host "Check certificate status"

    $counter = 0
    do
    {
        Start-Sleep -s 5
        $certSerialNumber = (Update-ACMECertificate $aliasCert -VaultProfile $profileName).IssuerSerialNumber
        Write-Host $certSerialNumber
        $counter++
    } while ($certSerialNumber -eq $null -and ($counter -lt 10))

    # Export Certificate to a .pfx file
    Get-ACMECertificate $aliasCert -ExportPkcs12 "$env:TEMP\$certName" -CertificatePassword $aliasCert -VaultProfile $profileName
    
    # return full path and password
    Write-Host "$env:TEMP\$certName"
    $Result.FullPath = "$env:TEMP\$certName"
    $Result.Password = $aliasCert
    return $Result
}

function Add-AzDnsTxtRecord($name, $value) {
    Write-Host "Add TXT Record : " $name
    $recordAdded = $false
    $dnsZone = $name

    $zones = Get-AzDnsZone

    # Search related Dns Zone in Azure Subscription.
    for ($i = 0; $i -lt 127; $i++) {
        # A while loop would be pretier, but I wan't to avoid infinite loops. 127 is the thorical max depth for a domain name

        # When submitting a Let's Encrypt Challent 
        # The first iteration should fail to find the DNS zone since the $name looks like _acme-challenge.something
        
        if ([string]::IsNullOrEmpty($entryName)) {
            $entryName = $dnsZone.Split(".", 2)[0]
        }
        else {
            $entryName += "." + $dnsZone.Split(".", 2)[0]
        }

        $dnsZone = $dnsZone.Split(".", 2)[1]

        if ([string]::IsNullOrEmpty($dnsZone)) {
            # We didn't find a zone in the Azure Subscription
            break;
        }
        
        $zoneSearch = $zones.Where( {$_.Name -eq $dnsZone})

        if ($zoneSearch.Count -gt 0) {
            # The Dns Zone exists. We add or update the TXT Record
            $txtRecords = Get-AzDnsRecordSet -RecordType TXT -ZoneName $zoneSearch[0].Name -ResourceGroupName $zoneSearch[0].ResourceGroupName
            $entry = $txtRecords.Where( {$_.Name -eq $entryName})

            if ($entry.Count -gt 0) {
                # Update record
                $entry[0].Records = (New-AzDnsRecordConfig -Value $value)
                $updatedRecord = Set-AzDnsRecordSet -RecordSet $entry[0]
                if ($updatedRecord.Records[0].Value -eq $value) {
                    $recordAdded = $true
                }
                break;
            }
            else {
                # Create record
                New-AzDnsRecordSet -Name $entryName -RecordType TXT -ZoneName $zoneSearch[0].Name -ResourceGroupName $zoneSearch[0].ResourceGroupName -Ttl 3600 -DnsRecords (New-AzDnsRecordConfig -Value $value)
            }
        }
        else {
            continue
        }

    }
    return $recordAdded
}

# --------- Script Start -----------
$newCert = Generate-Certificate -HostName $HostName -Contact $CertMailContact -Staging $EnableLetsEncryptStaging

Write-Output $newCert.FullPath
Write-Output $newCert.Password

