<#
.NOTES
    Author: Michael Hollingsworth
.LINK
    https://github.com/michael-hollingsworth/UserProfile
#>
function Remove-OutlookProfile {
    [CmdletBinding(DefaultParameterSetName = 'Name', SupportsShouldProcess = $true, ConfirmImpact = [System.Management.Automation.ConfirmImpact]::High)]
    param (
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, Position = 0, ParameterSetName = 'Name')]
        [ValidateNotNullOrEmpty()]
        [Alias('Name')]
        [System.Security.Principal.NTAccount[]]$Username,
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, ParameterSetName = 'Sid')]
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

    begin {
        if ($Force -and (-not $PSBoundParameters.ContainsKey('Confirm'))) {
            $ConfirmPreference = [System.Management.Automation.ConfirmImpact]::None
        }
    } process {
        # Pass filter parameters to Get-UserProfile
        [UserProfile[]]$userProfiles = if (($null -ne $Username) -or ($null -ne $Sid)) {
            [HashTable]$splat = $PSBoundParameters
            if ($splat.ContainsKey('PassThru')) {
                $splat.Remove('PassThru')
            }
            if ($splat.ContainsKey('Force')) {
                $splat.Remove('Force')
            }

            Get-UserProfile @splat
        } elseif ($PSCmdlet.ParameterSetName -ne 'InputObject') {
            Get-UserProfile -ExcludeLoadedProfiles -ExcludeSpecialprofiles -ExcludeLocalProfiles:(!!$ExcludeLocalProfiles)
        } else {
            $InputObject
        }

        foreach ($userProfile in $userProfiles) {
            # Loaded profiles can't be deleted
            if ($userProfile.IsLoaded) {
                $PSCmdlet.WriteWarning("Skipping user profile [$($userProfile.Username)] with SID [$($userProfile.Sid)] since it is currently loaded.")
                continue
            }

            [IO.FileInfo[]]$outlookProfile = Get-ChildItem -Path "$($userProfile.ProfilePath)\AppData\Local\Microsoft\Outlook" | & { process { if ($_.Extension -in @('.ost', '.nst')) { return $_ } } }

            if (-not $outlookProfile) {
                $PSCmdlet.WriteVerbose("Skipping user profile [$($userProfile.Username)] becuase an outlook profile doesn't exist.")
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
}