function Remove-InactiveOutlookProfile {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = [System.Management.Automation.ConfirmImpact]::High)]
    param (
        [Parameter(Position = 0, ParameterSetName = 'Days')]
        [ValidateRange(1, [Int32]::MaxValue)]
        [Int32]$MinDaysSinceLastLogon = 90,
        [Parameter(Mandatory = $true, ParameterSetName = 'CutoffDate')]
        [DateTime]$CutoffDate,
        [Parameter(Mandatory = $true, ParameterSetName = 'CutoffTimeSpan')]
        [DateTime]$CutoffTimeSpan,
        [Switch]$ExcludeLocalProfiles,
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
        [IO.FileInfo[]]$outlookProfile = Get-ChildItem -Path "$($userProfile.ProfilePath)\AppData\Local\Microsoft\Outlook" | Where-Object Extension -in @('.ost', '*.nst')

        if (-not $outlookProfile) {
            continue
        }

        if (-not $PSCmdlet.ShouldProcess($userProfile.Username)) {
            continue
        }

        $PSCmdlet.WriteVerbose("Removing outlook profile for [$($userProfile.Username)].")
        $outlookProfile | Remove-Item -Force -ErrorAction Continue

        if ($PassThru) {
            $PSCmdlet.WriteObject($userProfile)
        }
    }
}