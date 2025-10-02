<#
.DESCRIPTION
    Unlike `Remove-UserProfile`, `Clean-UserProfile` is used to delete the remnants of user profiles that weren't deleted correctly.
.NOTES
    For the love of god, DOT NOT RELY ON THIS FUNCTION. Windows is a very complex OS and I don't have the time or care to figure out every registry key that references
    a user profile. This also doesn't take into account any applications that may try to cache that information elsewhere.

    You are using this function at your own risk.
.NOTES
    Author: Michael Hollingsworth
#>
function Clean-UserProfile {
    [Cmdletbinding(SupportsShouldProcess = $true, ConfirmImpact = [System.Management.Automation.ConfirmImpact]::High, DefaultParameterSetName = 'Name')]
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
        [Switch]$PassThru,
        [Switch]$Force
    )

    if ($Force -and (-not $PSBoundParameters.ContainsKey('Confirm'))) {
        $ConfirmPreference = [System.Management.Automation.ConfirmImpact]::None
    }

    if ($PSCmdlet.ParameterSetName -ne 'InputObject') {
        [HashTable]$splat = $PSBoundParameters
        if ($splat.ContainsKey('PassThru')) {
            $splat.Remove('PassThru')
        }
        if ($splat.ContainsKey('Force')) {
            $splat.Remove('Force')
        }

        [UserProfile[]]$InputObject = Get-UserProfile @splat -ExcludeLoadedProfiles -ExcludeSpecialProfiles
    }

    foreach ($userProfile in $InputObject) {
        if (-not $PSCmdlet.ShouldProcess($userProfile.Username)) {
            continue
        }

        try {
            $userProfile.Delete()
        } catch {
            $PSCmdlet.WriteWarning("Failed to delete user profile [$($userProfile.Username)]. Attempting to delete manually.")
            # Remove everything manually
            Remove-Item -LiteralPath $userProfile.ProfilePath -Recurse -Force -ErrorAction Continue
            Remove-Item -LiteralPath "HKU:\$($userProfile.Sid)" -Recurse -Force -ErrorAction Continue
            Remove-Item -LiteralPath "HKU:\$($userProfile.Sid)_Classes" -Recurse -Force -ErrorAction Continue
            Remove-Item -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\$($userProfile.Sid)" -Recurse -Force -ErrorAction Continue
            Remove-Item -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$($userProfile.Sid)" -Recurse -Force -ErrorAction Continue
            Remove-Item -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileService\References\$($userProfile.Sid)" -Recurse -Force -ErrorAction Continue
        }

        if ($PassThru) {
            $PSCmdlet.WriteObject($userProfile)
        }
    }
}