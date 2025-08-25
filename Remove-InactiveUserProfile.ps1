<#
.DESCRIPTION
    This function is used to delete user profiles on a computer that haven't been accessed in an extended period of time.
.NOTES
    Author: Michael Hollingsworth
#>
function Remove-InactiveUserProfile {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High',DefaultParameterSetName = 'Days')]
    param (
        [Parameter(Position = 0, ParameterSetName = 'Days')]
        [ValidateRange(1, [Int32]::MaxValue)]
        [Int32]$MinDaysSinceLastLogon = 90,
        [Parameter(Position = 0, ParameterSetName = 'CutoffDate')]
        [DateTime]$CutoffDate,
        [Parameter(Position = 0, ParameterSetName = 'CutoffTimeSpan')]
        [DateTime]$CutoffTimeSpan,
        [Switch]$ExcludeLocalProfiles,
        [Switch]$CalculateProfileSize,
        [Switch]$PassThru,
        [Switch]$Force
    )

    if ($Force -and (-not $PSBoundParameters.ContainsKey('Confirm'))) {
        $ConfirmPreference = 'None'
    }

    if ($PSCmdlet.ParameterSetName -eq 'Days') {
        [DateTime]$CutoffDate = [DateTime]::Now.AddDays(-$MinDaysSinceLastLogon)
        [TimeSpan]$CutoffTimeSpan = [DateTime]::Now - $CutoffDate
    } elseif ($PSCmdlet.ParameterSetName -eq 'CutoffDate') {
        [TimeSpan]$CutoffTimeSpan = [DateTime]::Now - $CutoffDate
    } elseif ($PSCmdlet.ParameterSetName -eq 'CutoffTimeSpan') {
        [DateTime]$CutoffDate = [DateTime]::Now.Add(-$CutoffTimeSpan)
    }

    $PSCmdlet.WriteVerbose("Date cutoff [$CutoffDate].")

    foreach ($userProfile in (Get-UserProfile -ExcludeSpecialprofiles -ExcludeLoadedProfiles -ExcludeLocalProfiles:(!!$ExcludeLocalProfiles))) {
        if ($userProfile.LastUseTime -gt $CutoffDate) {
            $PSCmdlet.WriteVerbose("Skipping user profile [$($userProfile.Username)] because it has logged in in the last [$($CutoffTimeSpan.Days)] days: [$($userProfile.LastUseTime)]")
            continue
        }

        if ($CalculateProfileSize) {
            $userProfile.CalculateProfileSize()
        }

        # Write the object to to the console so the user can determine if they want to delete it or not based on other properties.
        Write-Host -Object $userProfile
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