<#
.SYNOPSIS
    This function is used to delete user profiles from a computer.
.DESCRIPTION
    This function is not the same as Remove-LocalUser. This function doesn't delete user accounts.
    Instead, it deletes the "profile" from the system, cleaning up disk space.
    If the account is created locally, it will stil exist and be allowed to log in but all of their files and registry settings will be deleted.
    If the account is an AD account, the account will not be deleted from AD. It will still exist in AD but their local profile will be deleted.
.EXAMPLE
    Delete the user profile for the user mhollingsworth.
    Remove-UserProfile -Username mhollingsworth
.EXAMPLE
    Delete the user profiles for users that haven't signed in in the past 90 days.
    Get-UserProfile | Where-Object { $_.LastUseTime -lt [DateTime]::Now.AddDays(-90) } | Remove-UserProfile -Force
.NOTES
    Author: Michael Hollingsworth
.LINK
    https://learn.microsoft.com/en-us/previous-versions/windows/desktop/userprofileprov/win32-userprofile
#>
function Remove-UserProfile {
    [CmdletBinding(DefaultParameterSetName = 'Name', SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param (
        [Parameter(Mandatory = $false, Position = 0, ParameterSetName = 'Name')]
        [Alias('Name')]
        [System.Security.Principal.NTAccount[]]$Username,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = 'Sid')]
        [System.Security.Principal.SecurityIdentifier[]]$Sid,
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0, ParameterSetName = 'InputObject')]
        [ValidateNotNullOrEmpty()]
        [UserProfile[]]$InputObject,
        [Switch]$ExcludeLocalProfiles,
        [Switch]$PassThru,
        [Switch]$Force
    )

    # https://learn.microsoft.com/en-us/powershell/scripting/learn/deep-dives/everything-about-shouldprocess#implementing--force
    if ($Force -and (-not $PSBoundParameters.ContainsKey('Confirm'))) {
        $ConfirmPreference = 'None'
    }

    if ($PSCmdlet.ParameterSetName -ne 'InputObject') {
        [HashTable]$splat = $PSBoundParameters
        if ($splat.ContainsKey('PassThru')) {
            $splat.Remove('PassThru')
        }
        if ($splat.ContainsKey('Force')) {
            $splat.Remove('Force')
        }

        [UserProfile[]]$InputObject = Get-UserProfile @splat -ExcludeLoadedProfiles -ExcludeSpecialProfiles -ExcludeLocalProfiles:(!!$ExcludeLocalProfiles)
    }

    foreach ($userProfile in $InputObject) {
        # Loaded profiles can't be deleted
        if ($userProfile.IsLoaded) {
            $PSCmdlet.WriteWarning("Skipping user profile [$($userProfile.Username)] with SID [$($userProfile.Sid)] since it is currently loaded.")
            continue
        }

        # Special profiles can't/shouldn't be deteled
        if ($userProfile.IsSpecial) {
            $PSCmdlet.WriteWarning("Skipping user profile [$($userProfile.Username)] with SID [$($userProfile.Sid)] since it is a special profile.")
            continue
        }

        if ($PSCmdlet.ShouldProcess($userProfile.Username)) {
            #TODO: Fix error handling to allow `Clean-UserProfile` to work.
            ## Ideally, that function could call this one and perform its own logic in the event that this one throws an error.
            try {
                $userProfile.Delete()
            } catch {
                $PSCmdlet.WriteError($_)
            }
            if ($PassThru) {
                $PSCmdlet.WriteObject($profile)
            }
        }
    }
}