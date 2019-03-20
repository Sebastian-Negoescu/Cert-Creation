# Cert-Creation
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