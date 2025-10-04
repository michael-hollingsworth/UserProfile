<#
.DESCRIPTION
    This is an example script that can be used to delete user profiles for users that have been disabled in AD.
.NOTES
    Author: Michael Hollingsworth
#>
function Remove-DisabledUserProfile {
    [CmdletBinding()]
    param (
    )

    # Use ADSI instead of the AD module to prevent the need to install the AD module on workstations.
    [ADSISearcher]$objSearcher = [ADSISearcher]::new()
    $objSearcher.Filter = '(&(objectClass=user)(userAccountControl:1.2.840.113556.1.4.803:=2))'
    $disabledUsers = $objSearcher.FindAll()
    #TODO: grab just the SIDs and put them in an array
    #[String[]]$disabledSids = $disabledUsers.Sid

    [UserProfile[]]$profs = Get-UserProfile

    $profsToRemove = $profs | Where-Object { $_.Sid -in $disabledSids }
    foreach ($profToRemove in $profsToRemove) {
        # Add custom logging or export a list of profiles that have been removed here

        Remove-UserProfile -InputObject $profToRemove -Force
    }
}

Remove-DisabledUserProfile