<#
.DESCRIPTION
    This function is used to get user profiles on a computer that haven't been accessed in an extended period of time.
.NOTES
    Author: Michael Hollingsworth
#>
function Get-InactiveUserProfile {
    [CmdletBinding(DefaultParameterSetName = 'Days')]
    [OutputType([UserProfile[]])]
    param (
        [Parameter(Position = 0, ParameterSetName = 'Days')]
        [ValidateRange(1, [Int32]::MaxValue)]
        [Int32]$MinDaysSinceLastLogon = 90,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = 'CutoffDate')]
        [DateTime]$CutoffDate,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = 'CutoffTimeSpan')]
        [DateTime]$CutoffTimeSpan,
        [Switch]$ExcludeLocalProfiles,
        [Switch]$CalculateProfileSize
    )

    if ($PSCmdlet.ParameterSetName -eq 'Days') {
        [DateTime]$CutoffDate = [DateTime]::Now.AddDays(-$MinDaysSinceLastLogon)
        [TimeSpan]$CutoffTimeSpan = [DateTime]::Now - $CutoffDate
    } elseif ($PSCmdlet.ParameterSetName -eq 'CutoffDate') {
        [TimeSpan]$CutoffTimeSpan = [DateTime]::Now - $CutoffDate
    } elseif ($PSCmdlet.ParameterSetName -eq 'CutoffTimeSpan') {
        [DateTime]$CutoffDate = [DateTime]::Now.Add(-$CutoffTimeSpan)
    }

    $PSCmdlet.WriteVerbose("Date cutoff [$CutoffDate].")

    [UserProfile[]]$UserProfiles = Get-UserProfile -ExcludeSpecialprofiles -ExcludeLoadedProfiles -ExcludeLocalProfiles:(!!$ExcludeLocalProfiles)

    $PSCmdlet.WriteVerbose("[$($userProfiles.Count)] profiles were found.")

    foreach ($userProfile in $userProfiles) {
        if ($userProfile.LastUseTime -gt $CutoffDate) {
            $PSCmdlet.WriteVerbose("Skipping user profile [$($userProfile.Username)] because it has logged in in the last [$($CutoffTimeSpan.Days)] days: [$($userProfile.LastUseTime)]")
            continue
        }

        if ($CalculateProfileSize) {
            $userProfile.CalculateProfileSize()
        }

        $PSCmdlet.WriteObject($userProfile)
    }
}