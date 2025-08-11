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
    [Boolean]$IsSpecial
    hidden [Microsoft.Management.Infrastructure.CimInstance]$_userProfile
    hidden [Boolean]$_isDeleted = $false

    UserProfile() {
        $this.Username = $null
        $this.Sid = $null
        $this.ProfilePath = $null
        $this.ProfileSize = -1
        $this.LastUseTime = [DateTime]::new(0)
        # idk if this property even works anymore or if its just more legacy junk left in WMI.
        $this.Status = 0
        $this.IsLoaded = $false
        $this.IsSpecial = $false
        $this._userProfile = $null
        $this._isDeleted = $false
    }

    UserProfile([System.Security.Principal.NTAccount]$Username) {
        try {
            [System.Security.Principal.SecurityIdentifier]$tmpSid = $Username.Translate([System.Security.Principal.SecurityIdentifier])
        } catch {
            throw $(
                [Exception]::new("The username [$Username] could not be translated to an SID.", $_)
            )
        }
        $this.Init($tmpSid)
    }

    UserProfile([System.Security.Principal.NTAccount]$Username, [Boolean]$CalculateProfileSize) {
        try {
            [System.Security.Principal.SecurityIdentifier]$tmpSid = $Username.Translate([System.Security.Principal.SecurityIdentifier])
        } catch {
            throw $(
                [Exception]::new("The username [$Username] could not be translated to an SID.", $_)
            )
        }
        $this.Init($tmpSid, $CalculateProfileSize)
    }

    UserProfile([System.Security.Principal.SecurityIdentifier]$Sid) {
        $this.Init($Sid)
    }
    hidden Init([System.Security.Principal.SecurityIdentifier]$Sid) {
        $this.Init((Get-CimInstance -ClassName Win32_UserProfile -Filter "SID = `"$($Sid.Value)`""))
    }

    UserProfile([System.Security.Principal.SecurityIdentifier]$Sid, [Boolean]$CalculateProfileSize) {
        $this.Init($Sid, $CalculateProfileSize)
    }
    hidden Init([System.Security.Principal.SecurityIdentifier]$Sid, [Boolean]$CalculateProfileSize) {
        $this.Init((Get-CimInstance -ClassName Win32_UserProfile -Filter "SID = `"$($Sid.Value)`""), $CalculateProfileSize)
    }

    UserProfile([Microsoft.Management.Infrastructure.CimInstance]$UserProfile) {
        $this.Init($UserProfile)
    }
    hidden Init([Microsoft.Management.Infrastructure.CimInstance]$UserProfile) {
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
        $this.ProfileSize = -1
        $this.LastUseTime = $UserProfile.LastUseTime
        $this.Status = [UserProfileStatus]$UserProfile.Status
        $this.IsLoaded = $UserProfile.Loaded
        $this.IsSpecial = $UserProfile.Special
        $this._userProfile = $UserProfile
        $this._isDeleted = $false

        if ($CalculateProfileSize) {
            $this.CalculateProfileSize()
        }
    }

    [Void] CalculateProfileSize() {
        if ([String]::IsNullOrWhiteSpace($this.ProfilePath)) {
            return
        }

        if (-not (Test-Path -LiteralPath $this.ProfilePath)) {
            $this.ProfileSize = 0
            return
        }

        #TODO: improve the speed of this using C#/PInvoke
        $this.ProfileSize = (Get-ChildItem -LiteralPath $this.ProfilePath -Recurse -Force -ErrorAction Ignore | Measure-Object -Property Length -Sum).Sum
        return
    }

    [Void] Delete() {
        # While not 100% accurate, this is faster than running Get-CimInstance every time.
        if ($this._isDeleted) {
            return
        }

        if ($this.IsLoaded) {
            throw "Loaded profiles cannot be deleted."
        }

        # https://learn.microsoft.com/en-us/previous-versions/windows/desktop/userprofileprov/win32-userprofile
        ## "Whether the user profile is owned by a special system service. True if the user profile is owned by a system service; otherwise false."
        if ($this.IsSpecial) {
            throw "Special profiles cannot be deleted."
        }


        #TODO: Validate the the CIM instance still exists
        ## Verify that calling `Get-CimInstance -InputObject $this._userProfile` returns nothing or errors out when the profile has already been deleted
        ## This will also ensure that an error isn't generated when trying to use the Delete() method on an instance that was instantiated using the new() method rather than one of its overloads.

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
        return ($this.Sid.Value)
        #return "$($this.Username.Value);$($this.Sid.Value)"
        #return "$($this.Username.Value);$($this.Sid.Value);$($this.ProfilePath)"
    }

    static [UserProfile[]] GetUserProfiles() {
        [Microsoft.Management.Infrastructure.CimInstance[]]$profs = Get-CimInstance -ClassName Win32_UserProfile

        return $(foreach ($prof in $profs) {
            [UserProfile]::new($prof)
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
        #[String[]]$ComputerName,
        [Switch]$ExcludeLodedProfiles,
        [Switch]$ExcludeSpecialProfiles,
        [Switch]$CalculateProfileSize
    )

    #TODO: add support for retrieving profiles from remote computers.

    if ($PSCmdlet.ParameterSetName -eq 'Name') {
        if ($null -eq $UserName) {
            [UserProfile[]]$profs = [UserProfile]::GetUserProfiles()
            if ($ExcludeLodedProfiles) {
                [UserProfile[]]$profs = $profs | Where-Object { $_.IsLoaded -ne $true }
            }

            if ($ExcludeSpecialProfiles) {
                [UserProfile[]]$profs = $profs | Where-Object { $_.IsSpecial -ne $true }
            }

            if ($CalculateProfileSize) {
                foreach ($prof in $profs) {
                    $prof.CalculateProfileSize()
                    $PSCmdlet.WriteObject($prof)
                }

                return
            }

            $PSCmdlet.WriteObject($profs)
            return
        }

        [String[]]$where = foreach ($name in $UserName) {
            #TODO: Validate that this is faster than calling the UserProfile constructor for each individual username/SID
            ## I would prefer to rely on the constructors for everything but I'm concerned that performing multiple WMI queries is WAY slower than using a single query
            [System.Security.Principal.NTAccount]$nt = [System.Security.Principal.NTAccount]::new($name)
            try {
                [System.Security.Principal.SecurityIdentifier]$sid = $nt.Translate([System.Security.Principal.SecurityIdentifier])
            } catch {
                continue
            }

            "SID = `"$($sid.Value)`""
        }
        [String]$filter = $where -join ' OR '
    } elseif ($PSCmdlet.ParameterSetName -eq 'Sid') {
        [String]$filter = $(foreach ($id in $Sid) { "SID = `"$($id.Value)`"" }) -join ' OR '
    }

    if ([String]::IsNullOrWhiteSpace($filter)) {
        return
    }

    [Microsoft.Management.Infrastructure.CimInstance[]]$cim = Get-CimInstance -ClassName Win32_UserProfile -Filter $filter -ErrorAction Stop

    if ($ExcludeLodedProfiles) {
        [Microsoft.Management.Infrastructure.CimInstance[]]$cim = $cim | Where-Object { $_.IsLoaded -ne $true }
    }

    if ($ExcludeSpecialProfiles) {
        [Microsoft.Management.Infrastructure.CimInstance[]]$cim = $cim | Where-Object { $_.IsSpecial -ne $true }
    }

    foreach ($instance in $cim) {
        [UserProfile]::new($instance, (!!$CalculateProfileSize))
    }
}