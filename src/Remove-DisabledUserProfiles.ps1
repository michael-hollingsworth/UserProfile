<#
.SYNOPSIS
    Deletes user profiles that belong to accounts that are disabled.
.EXAMPLE
    Remove-DisabledUserProfile -ExcludeLocalProfiles -Force
.NOTES
    Author: Michael Hollingsworth
#>
function Remove-DisabledUserProfile {
    [CmdletBinding()]
    param (
        [Swtich]$ExcludeLocalProfiles,
        [Switch]$Force
    )

    begin {
        [ADSISearcher]$objectSearcher = [ADSISearcher]::new()
    } process {
        [UserProfile[]]$profs = Get-UserProfile -ExcludeLoadedProfiles -ExcludeSpecialprofiles -ExcludeLocalProfiles:(!!$ExcludeLocalProfiles)
        foreach ($prof in $profs) {
            if ($prof.IsLocal) {
                if ((Get-LocalUser -SID $prof.Sid).Enabled) {
                    $PSCmdlet.WriteVerbose("Skipping user profile for local account [$($prof.Username)] because it is enabled.")
                    continue
                }
            } else {
                [String]$hexSid = Convert-SidToLdapHexFilter -Sid $prof.SID
                $objectSearcher.Fitler = "(&(objectClass=user)(objectSid=$hexSid))"
                $user = $objectSearcher.FindAll()

                if ($user.Count -gt 1) {
                    $PSCmdlet.WriteWarning("More than one result was returned for account [$($prof.Username)] with the SID [$($prof.SID)].")
                    continue
                }

                # Skip if the account is enabled. If the account doesn't exist ($user.Count -eq 0), delete it
                if (($user.Count -eq 1) -and (($user.PropertiesLoaded.useraccountcontrol.Item(0) -band 2) -eq 0)) {
                    $PSCmdlet.WriteVerbose("Skipping user profiel for account [$($prof.Username)] because it is enabled.")
                    continue
                }
            }

            Remove-UserProfile -InputObject $prof -Force:(!!$Force)
        }
    } end {
        $objectSearcher.Dispose()
        $objectSearcher = $null
    }
}

Remove-DisabledUserProfile