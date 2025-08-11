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
    [Cmdletbinding(DefaultParameterSetName = 'Name')]
    param (
        [Parameter(Mandatory = $false, Position = 0, ParameterSetName = 'Name')]
        [Alias('Name')]
        [System.Security.Principal.NTAccount[]]$Username,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = 'Sid')]
        [System.Security.Principal.SecurityIdentifier[]]$Sid,
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0, ParameterSetName = 'InputObject')]
        [ValidateNotNullOrEmpty()]
        [UserProfile[]]$InputObject,
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

        [UserProfile[]]$InputObject = Get-UserProfile @splat -ExcludeLoadedProfiles -ExcludeSpecialProfiles
    }

    foreach ($userProfile in $InputObject) {
        #TODO: Validate the the ShouldProcess prompt is passed through from Remove-UserProfile
        try {
            Remove-UserProfile -InputObject $userProfile -ErrorAction Stop
        } catch {
            # Remove everything manually
            Remove-Item -LiteralPath $userProfile.ProfilePath -Recurse -Force
            Remove-Item -LiteralPath "HKU:\$($userProfile.Sid)" -Recurse -Force
            Remove-Item -LiteralPath "HKU:\$($userProfile.Sid)_Classes" -Recurse -Force
            Remove-Item -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\$($userProfile.Sid)" -Recurse -Force
            Remove-Item -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$($userProfile.Sid)" -Recurse -Force
            Remove-Item -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileService\References\$($userProfile.Sid)" -Recurse -Force
        }
    }
}