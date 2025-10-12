<#
.EXAMPLE
    Get all user profiles on the system.
    Get-UserProfile
.EXAMPLE
    Get the user profile for the username of "mhollingsworth"
    Get-UserProfile -Username mhollingsworth
.EXAMPLE
    Get the user profiles for users that can be deleted
    Get-UserProfile -ExcludeLoadedProfile -ExcludeSpecialprofiles
.NOTES
    Author: Michael Hollingsworth
#>
function Get-UserProfile {
    [CmdletBinding(DefaultParameterSetName = 'Filter')]
    [OutputType([UserProfile[]])]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0, ParameterSetName = 'Name')]
        [ValidateNotNullOrEmpty()]
        [Alias('Name')]
        [System.Security.Principal.NTAccount[]]$Username,
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, ParameterSetName = 'Sid')]
        [System.Security.Principal.SecurityIdentifier[]]$Sid,
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String[]]$ComputerName,
        [Parameter(ParameterSetName = 'Filter')]
        [Switch]$ExcludeLoadedProfiles,
        [Parameter(ParameterSetName = 'Filter')]
        [Switch]$ExcludeLocalProfiles,
        [Parameter(ParameterSetName = 'Filter')]
        [Switch]$ExcludeSpecialProfiles,
        [Switch]$CalculateProfileSize
    )

    begin {
        if ($null -eq $ComputerName) {
            [String[]]$ComputerName = $env:ComputerName
        }
    } process {
        if ($null -ne $Username) {
            $identity = $Username
        } elseif ($null -ne $Sid) {
            $identity = $Sid
        }

        [UserProfile[]]$userProfiles = foreach ($computer in $ComputerName) {
            if ($null -ne $identity) {
                foreach ($id in $identity) {
                    [UserProfile]::new($id, $computer)
                }
            } else {
                [UserProfile]::Get($computer)
            }
        }

        if ($null -eq $userProfiles) {
            return
        }

        if ($PSCmdlet.ParameterSetName -ne 'Filter') {
            # Calculate profile size for each profile separately so we can send an object through the pipeline while waiting on the next one to process.
            if ($CalculateProfileSize) {
                foreach ($prof in $userProfiles) {
                    $prof.CalculateProfileSize()
                    $PSCmdlet.WriteObject($prof)
                }

                return
            }

            $PSCmdlet.WriteObject($userProfiles)
            return
        }

        foreach ($prof in $userProfiles) {
            if ($prof.IsLoaded -and $ExcludeLoadedProfiles) {
                $PSCmdlet.WriteVerbose("Skipping user profile [$($prof.Username)] because it is loaded.")
                continue
            }

            if ($prof.IsSpecial -and $ExcludeSpecialProfiles) {
                $PSCmdlet.WriteVerbose("Skipping user profile [$($prof.Username)] because it is a special profile.")
                continue
            }

            if ($prof.IsLocal -and $ExcludeLocalProfiles) {
                $PSCmdlet.WriteVerbose("Skipping user profile [$($prof.Username)] because it is a local profile.")
                continue
            }

            if ($CalculateProfileSize) {
                $prof.CalculateProfileSize()
            }
            $PSCmdlet.WriteObject($prof)
        }
    }
}