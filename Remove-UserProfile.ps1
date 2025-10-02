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
    [CmdletBinding(DefaultParameterSetName = 'Name', SupportsShouldProcess = $true, ConfirmImpact = [System.Management.Automation.ConfirmImpact]::High)]
    param (
        [Parameter(Mandatory = $false, Position = 0, ParameterSetName = 'Name')]
        [ValidateNotNullOrEmpty()]
        [Alias('Name')]
        [System.Security.Principal.NTAccount[]]$Username,
        [Parameter(Mandatory = $true, ParameterSetName = 'Sid')]
        [ValidateNotNullOrEmpty()]
        [System.Security.Principal.SecurityIdentifier[]]$Sid,
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = 'InputObject')]
        [ValidateNotNullOrEmpty()]
        [UserProfile[]]$InputObject,
        [Parameter(ParameterSetName = 'Filter')]
        [Switch]$ExcludeLocalProfiles,
        [Switch]$PassThru,
        [Switch]$Force
    )

    if ($Force -and (-not $PSBoundParameters.ContainsKey('Confirm'))) {
        $ConfirmPreference = [System.Management.Automation.ConfirmImpact]::None
    }

    # Pass filter parameters to Get-UserProfile
    if (($null -ne $Username) -or ($null -ne $Sid)) {
        [HashTable]$splat = $PSBoundParameters
        if ($splat.ContainsKey('PassThru')) {
            $splat.Remove('PassThru')
        }
        if ($splat.ContainsKey('Force')) {
            $splat.Remove('Force')
        }

        [UserProfile[]]$InputObject = Get-UserProfile @splat
    } elseif ($PSCmdlet.ParameterSetName -ne 'InputObject') {
        [UserProfile[]]$InputObject = Get-UserProfile -ExcludeLoadedProfiles -ExcludeSpecialprofiles -ExcludeLocalProfiles:(!!$ExcludeLocalProfiles)
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
            try {
                $userProfile.Delete()
            } catch {
                $PSCmdlet.WriteError($_)
            }

            if ($PassThru) {
                $PSCmdlet.WriteObject($userProfile)
            }
        }
    }
}