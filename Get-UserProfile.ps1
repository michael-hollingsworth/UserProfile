<#
.NOTES
    Author: Michael Hollingsworth
.LINK
    https://learn.microsoft.com/en-us/previous-versions/windows/desktop/userprofileprov/win32-userprofile
#>

enum UserProfileStatus {
    Undefined = 0  # The status of the profile is not set.
    Temporary = 1  # The profile is a temporary profile and will be deleted after the user logs off.
    Roaming = 2  # The profile is set to roaming. If this bit is not set, the profile is set to local.
    Mandatory = 4  # The profile is a mandatory profile.
    Corrupted = 8  # The profile is corrupted and is not in use. The user or administrator must fix the corruption to use the profile.
}

class UserProfile {
    [System.Security.Principal.NTAccount]$Username
    # I would like to use [System.Nullable<T>] for these but it looks like PowerShell doesn't like their use in classes.
    ## The following non-descriptive error is provided when these properties are of type [System.Nullable<T>]: ParentContainsErrorRecordException: An error occurred while creating the pipeline.
    [System.Security.Principal.SecurityIdentifier]$Sid
    [String]$ProfilePath
    [Int64]$ProfileSize
    [DateTime]$LastUseTime
    [UserProfileStatus]$Status
    [Boolean]$IsLoaded
    [Boolean]$IsLocal
    [Boolean]$IsSpecial
    [String]$ComputerName
    hidden [Microsoft.Management.Infrastructure.CimInstance]$_userProfile
    hidden [Boolean]$_isDeleted
    static hidden [System.Security.Principal.SecurityIdentifier]$_localComputerDomainSid = ([System.Security.Principal.SecurityIdentifier]((Get-CimInstance -Query "SELECT SID FROM Win32_UserAccount WHERE LocalAccount='TRUE'")[0].SID)).AccountDomainSid

    UserProfile() {
        $this.Username = $null
        $this.Sid = $null
        $this.ProfilePath = $null
        $this.ProfileSize = -1
        $this.LastUseTime = [DateTime]::MinValue
        # idk if this property even works anymore or if its just more legacy junk left in WMI.
        $this.Status = 0
        $this.IsLoaded = $false
        $this.IsLocal = $false
        $this.IsSpecial = $false
        $this.ComputerName = $null
        $this._userProfile = $null
        $this._isDeleted = $true
    }

    UserProfile([System.Security.Principal.NTAccount]$Username) {
        $this.Init($Username, $null, $false)
    }

    UserProfile([System.Security.Principal.NTAccount]$Username, [Boolean]$CalculateProfileSize) {
        $this.Init($Username, $null, $CalculateProfileSize)
    }

    UserProfile([System.Security.Principal.NTAccount]$Username, [String]$ComputerName) {
        $this.Init($Username, $ComputerName, $false)
    }

    UserProfile([System.Security.Principal.NTAccount]$Username, [String]$ComputerName, [Boolean]$CalculateProfileSize) {
        $this.Init($Username, $ComputerName, $CalculateProfileSize)
    }
    hidden Init([System.Security.Principal.NTAccount]$Username, [String]$ComputerName, [Boolean]$CalculateProfileSize) {
        try {
            [System.Security.Principal.SecurityIdentifier]$tmpSid = $Username.Translate([System.Security.Principal.SecurityIdentifier])
        } catch {
            throw $(
                [Exception]::new("The username [$Username] could not be translated to an SID.", $_)
            )
        }
        $this.Init($tmpSid, $ComputerName, $CalculateProfileSize)
    }

    UserProfile([System.Security.Principal.SecurityIdentifier]$Sid) {
        $this.Init($Sid, $null, $false)
    }

    UserProfile([System.Security.Principal.SecurityIdentifier]$Sid, [Boolean]$CalculateProfileSize) {
        $this.Init($Sid, $null, $CalculateProfileSize)
    }

    UserProfile([System.Security.Principal.SecurityIdentifier]$Sid, [String]$ComputerName) {
        $this.Init($Sid, $ComputerName, $false)
    }

    UserProfile([System.Security.Principal.SecurityIdentifier]$Sid, [String]$ComputerName, [Boolean]$CalculateProfileSize) {
        $this.Init($Sid, $ComputerName, $CalculateProfileSize)
    }
    hidden Init([System.Security.Principal.SecurityIdentifier]$Sid, [String]$ComputerName, [Boolean]$CalculateProfileSize) {
        [Microsoft.Management.Infrastructure.CimInstance]$userProfile = if ([String]::IsNullOrWhiteSpace($ComputerName) -or ($ComputerName -in ($env:ComputerName, '.'))) {
            Get-CimInstance -ClassName Win32_UserProfile -Filter "SID = `"$($Sid.Value)`"" -ErrorAction Stop
        } else {
            Get-CimInstance -ClassName Win32_UserProfile -Filter "SID = `"$($Sid.Value)`"" -ComputerName $ComputerName -ErrorAction Stop
        }

        if ($null -eq $userProfile) {
            return
        }

        $this.Init($userProfile, $CalculateProfileSize)
    }

    UserProfile([Microsoft.Management.Infrastructure.CimInstance]$UserProfile) {
        $this.Init($UserProfile, $false)
    }

    UserProfile([Microsoft.Management.Infrastructure.CimInstance]$UserProfile, [Boolean]$CalculateProfileSize) {
        $this.Init($UserProfile, $CalculateProfileSize)
    }
    hidden Init([Microsoft.Management.Infrastructure.CimInstance]$UserProfile, [Boolean]$CalculateProfileSize) {
        if ($UserProfile.CimClass.CimClassName -ne 'Win32_UserProfile') {
            throw 'CIM instance must be of the class [Win32_UserProfile].'
        }

        $this.Sid = $UserProfile.SID
        $this.Username = $this.Sid.Translate([System.Security.Principal.NTAccount]).Value
        $this.ProfilePath = $UserProfile.LocalPath
        $this.ProfileSize = if ([String]::IsNullOrWhiteSpace($this.ProfilePath) -or (-not (Test-Path -LiteralPath $this.ProfilePath -ErrorAction Ignore))) { 0 } else { -1 }
        $this.LastUseTime = if ($null -ne $UserProfile.LastUseTime) { $UserProfile.LastUseTime } else { [DateTime]::MinValue }
        $this.Status = [UserProfileStatus]$UserProfile.Status
        $this.IsLoaded = $UserProfile.Loaded
        $this.IsLocal = (($null -eq $this.Sid.AccountDomainSid) -or ($this.Sid.AccountDomainSid -eq [UserProfile]::_localComputerDomainSid))
        $this.IsSpecial = $UserProfile.Special
        $this.ComputerName = $userProfile.PSComputerName
        $this._userProfile = $UserProfile
        $this._isDeleted = $false

        if ($CalculateProfileSize) {
            $this.CalculateProfileSize()
        }
    }

    [Void] CalculateProfileSize() {
        if ([String]::IsNullOrWhiteSpace($this.ProfilePath) -or (-not (Test-Path -LiteralPath $this.ProfilePath -ErrorAction Ignore))) {
            $this.ProfileSize = 0
            return
        }

        #TODO: improve the speed of this using C#/PInvoke
        $this.ProfileSize = (Get-ChildItem -LiteralPath $this.ProfilePath -Recurse -Force -ErrorAction Ignore | Measure-Object -Property Length -Sum).Sum
        return
    }

    [Void] Delete() {
        # While not 100% accurate, this is faster than running Get-CimInstance every time.
        if ($this._isDeleted -or ($null -eq $this._userProfile)) {
            return
        }

        if ($this.IsLoaded) {
            throw 'Loaded profiles cannot be deleted.'
        }

        # https://learn.microsoft.com/en-us/previous-versions/windows/desktop/userprofileprov/win32-userprofile
        ## "Whether the user profile is owned by a special system service. True if the user profile is owned by a system service; otherwise false."
        if ($this.IsSpecial) {
            throw 'Special profiles cannot be deleted.'
        }

        # Validate the the CIM instance still exists before attempting to delete it.
        try {
            $null = Get-CimInstance -InputObject $this._userProfile -ErrorAction Stop
        } catch <# [ObjectNotFoundException] #> {
            $this._isDeleted = $true
            return
        }

        try {
            Remove-CimInstance -InputObject $this._userProfile -ErrorAction Stop
        } catch {
            throw $_
        }
        $this._isDeleted = $true

        # Update profile size if it was previously calculated
        if ($this.ProfileSize -ne -1) {
            $this.CalculateProfileSize()
        }
        return
    }

    # Return the SID since it can be used to recreate the object and it should be the most uniquely identifiable.
    [String] ToString() {
        return $this.Sid.Value
        #return "$($this.Username.Value);$($this.Sid.Value)"
        #return "$($this.Username.Value);$($this.Sid.Value);$($this.ProfilePath)"
    }

    static [UserProfile[]] GetUserProfiles() {
        return ([UserProfile]::GetUserProfiles($null, $false))
    }

    static [UserProfile[]] GetUserProfiles([Boolean]$CalculateProfileSize) {
        return ([UserProfile]::GetUserProfiles($null, $CalculateProfileSize))
    }

    static [UserProfile[]] GetUserProfiles([String]$ComputerName) {
        return ([UserProfile]::GetUserProfiles($ComputerName, $false))
    }

    static [UserProfile[]] GetUserProfiles([String]$ComputerName, [Boolean]$CalculateProfileSize) {
        [Microsoft.Management.Infrastructure.CimInstance[]]$profs = if ([String]::IsNullOrWhiteSpace($ComputerName) -or ($ComputerName -in ($env:ComputerName, '.'))) {
            Get-CimInstance -ClassName Win32_UserProfile -ErrorAction Stop
        } else {
            Get-CimInstance -ClassName Win32_UserProfile -ComputerName $ComputerName -ErrorAction Stop
        }

        return $(foreach ($prof in $profs) {
            [UserProfile]::new($prof, $CalculateProfileSize)
        })
    }
}

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
    [CmdletBinding(DefaultParameterSetName = 'Name')]
    [OutputType([UserProfile[]])]
    param (
        [Parameter(Mandatory = $false, Position = 0, ParameterSetName = 'Name')]
        [Alias('Name')]
        [System.Security.Principal.NTAccount[]]$Username,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = 'Sid')]
        [System.Security.Principal.SecurityIdentifier[]]$Sid,
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String[]]$ComputerName,
        [Parameter(ParameterSetName = 'Filter')]
        [Switch]$ExcludeLodedProfiles,
        [Parameter(ParameterSetName = 'Filter')]
        [Switch]$ExcludeLocalProfiles,
        [Parameter(ParameterSetName = 'Filter')]
        [Switch]$ExcludeSpecialProfiles,
        [Switch]$CalculateProfileSize
    )

    begin {
        if ($null -ne $Username) {
            $identity = $Username
        } elseif ($null -ne $Sid) {
            $identity = $Sid
        }

        if ($null -eq $ComputerName) {
            [String[]]$ComputerName = @('.')
        }
    } process {
        [UserProfile[]]$userProfiles = foreach ($computer in $ComputerName) {
            if ($null -ne $identity) {
                foreach ($id in $identity) {
                    [UserProfile]::new($id, $computer)
                }
            } else {
                [UserProfile]::GetUserProfiles($computer)
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
            if ($prof.IsLoaded -and $ExcludeLodedProfiles) {
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