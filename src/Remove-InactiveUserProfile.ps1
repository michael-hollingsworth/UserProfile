<#
.DESCRIPTION
    This function is used to delete user profiles on a computer that haven't been accessed in an extended period of time.
.NOTES
    Author: Michael Hollingsworth
#>
function Remove-InactiveUserProfile {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = [System.Management.Automation.ConfirmImpact]::High, DefaultParameterSetName = 'Days')]
    param (
        [Parameter(Position = 0, ParameterSetName = 'Days')]
        [ValidateRange(1, [Int32]::MaxValue)]
        [Int32]$MinDaysSinceLastLogon = 90,
        [Parameter(Mandatory = $true, ParameterSetName = 'CutoffDate')]
        [DateTime]$CutoffDate,
        [Parameter(Mandatory = $true, ParameterSetName = 'CutoffTimeSpan')]
        [DateTime]$CutoffTimeSpan,
        [Switch]$ExcludeLocalProfiles,
        [Switch]$CalculateProfileSize,
        [Switch]$PassThru,
        [Switch]$Force
    )

    if ($Force -and (-not $PSBoundParameters.ContainsKey('Confirm'))) {
        $ConfirmPreference = [System.Management.Automation.ConfirmImpact]::None
    }

    if ($PSCmdlet.ParameterSetName -eq 'Days') {
        [DateTime]$CutoffDate = [DateTime]::Now.AddDays(-$MinDaysSinceLastLogon)
    } elseif ($PSCmdlet.ParameterSetName -eq 'CutoffTimeSpan') {
        [DateTime]$CutoffDate = [DateTime]::Now.Add(-$CutoffTimeSpan)
    }

    [UserProfile[]]$userProfiles = Get-InactiveUserProfile -CutoffDate $CutoffDate -ExcludeLocalProfiles:(!!$ExcludeLocalProfiles)

    $PSCmdlet.WriteVerbose("[$($userProfiles.Count)] inactive profiles were found.")

    foreach ($userProfile in $userProfiles) {
        if ($CalculateProfileSize) {
            $userProfile.CalculateProfileSize()
        }

        # Write the object to the console so the user can determine if they want to delete it or not based on other properties.
        Write-Host -Object $(Out-String -InputObject $userProfile)
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