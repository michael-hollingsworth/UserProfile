<#
.NOTES
    Author: Michael Hollingsworth
.LINK
    https://learn.microsoft.com/en-us/previous-versions/windows/desktop/userprofileprov/win32-userprofile
#>

[Flags()]
enum UserProfileStatus {
    Corrupted = -1  # The profile is corrupted and is not in use. The user or administrator must fix the corruption to use the profile.
    Undefined = 0  # The status of the profile is not set.
    Temporary = 1  # The profile is a temporary profile and will be deleted after the user logs off.
    Roaming = 2  # The profile is set to roaming. If this bit is not set, the profile is set to local.
    Mandatory = 4  # The profile is a mandatory profile.
}

class UserProfile {
    [System.Security.Principal.NTAccount]$Username
    [System.Security.Principal.SecurityIdentifier]$Sid
    [String]$ProfilePath
    [Int64]$ProfileSize
    [Decimal]$ProfileSizeMB
    [DateTime]$LastUseTime
    [System.Nullable[DateTime]]$LastLoadTime
    [System.Nullable[DateTime]]$LastUnloadTime
    [System.Nullable[DateTime]]$LastProfileCleanupCheck
    [UserProfileStatus]$Status
    [Boolean]$IsLoaded
    [Boolean]$IsLocal
    [Boolean]$IsSpecial
    [String]$ComputerName
    hidden [Microsoft.Management.Infrastructure.CimInstance]$_userProfile
    hidden [Boolean]$_isDeleted
    static hidden [HashTable]$_localComputerDomainSidLookupTable = @{}

    UserProfile() {
        $this.Username = $null
        $this.Sid = $null
        $this.ProfilePath = $null
        $this.ProfileSize = -1
        $this.ProfileSizeMB = [Decimal]::MinusOne
        $this.LastUseTime = [DateTime]::MinValue
        $this.LastLoadTime = $null
        $this.LastUnloadTime = $null
        $this.LastProfileCleanupCheck = $null
        # idk if this property even works anymore or if its just more legacy junk left in WMI.
        $this.Status = [UserProfileStatus]::Undefined
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
        [System.Security.Principal.SecurityIdentifier]$tmpSid = ConvertTo-Sid -NTAccount $Username
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
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.ArgumentException]::new('CIM instance must be of the class [Win32_UserProfile].'),
                'NotWin32UserProfile',
                [System.Management.Automation.ErrorCategory]::InvalidType,
                $UserProfile
            )
        }

        $this.Sid = $UserProfile.SID
        $this.Username = try {
            ConvertTo-NTAccount -Sid $this.Sid
        } catch {
            # Fall back to using the profile path to determine username
            if ([String]::IsNullOrWhiteSpace($UserProfile.LocalPath)) {
                throw $_
            }
            $UserProfile.LocalPath.Split('\')[-1]
        }
        $this.ProfilePath = $UserProfile.LocalPath
        $this.ProfileSize = if ([String]::IsNullOrWhiteSpace($this.ProfilePath) -or (-not (Test-Path -LiteralPath $this.ProfilePath -ErrorAction Ignore))) { 0 } else { -1 }
        $this.ProfileSizeMB = if ($this.ProfileSize -eq 0) { [Decimal]::Zero } else { [Decimal]::MinusOne }
        $this.LastUseTime = if ($null -ne $UserProfile.LastUseTime) { $UserProfile.LastUseTime } else { [DateTime]::MinValue }

        # https://learn.microsoft.com/en-us/troubleshoot/windows-server/support-tools/scripts-retrieve-profile-age-delete-aged-copies
        $reg = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$($userProfile.SID)" -Name ('LocalProfileLoadTimeLow', 'LocalProfileLoadTimeHigh', 'LocalProfileUnLoadTimeLow', 'LocalProfileUnLoadTimeHigh', 'LocalProfileCleanupCheckTimeLow', 'LocalProfileCleanupCheckTimeHigh') -ErrorAction Ignore
        if (-not ($null -eq ($reg.LocalProfileUnloadTimeLow) -or ($null -eq $reg.LocalProfileLoadTimeHigh))) {
            $highTime = [UInt64]$reg.LocalProfileLoadTimeHigh -shl 32
            $this.LastLoadTime = [DateTime]::FromFileTime($highTime -bor [UInt64]$reg.LocalProfileLoadTimeLow)
        }

        if (-not ($null -eq ($reg.LocalProfileUnLoadTimeLow) -or ($null -eq $reg.LocalProfileUnLoadTimeHigh))) {
            $highTime = [UInt64]$reg.LocalProfileUnLoadTimeHigh -shl 32
            $this.LastUnloadTime = [DateTime]::FromFileTime($highTime -bor [UInt64]$reg.LocalProfileUnLoadTimeLow)
        }

        if (-not ($null -eq ($reg.LocalProfileCleanupCheckTimeLow) -or ($null -eq $reg.LocalProfileCleanupCheckTimeHigh))) {
            $highTime = [UInt64]$reg.LocalProfileCleanupCheckTimeHigh -shl 32
            $this.LastProfileCleanupCheck = [DateTime]::FromFileTime($highTime -bor [UInt64]$reg.LocalProfileCleanupCheckTimeLow)
        }

        $this.Status = if (($null -eq $UserProfile.Status) -or ($userProfile.Status -eq -1)) {
            Write-Warning -Message "The user profile [$($this.Username)] is most likely corrupted due to it having the Status value of [$($UserProfile.Status)]."
            [UserProfileStatus]::Corrupted
        } else {
            [UserProfileStatus]$UserProfile.Status
        }
        $this.IsLoaded = $UserProfile.Loaded
        [String]$compName = if ([String]::IsNullOrWhiteSpace($UserProfile.PSComputerName)) { $env:ComputerName } else { $UserProfile.PSComputerName }

        if (-not [UserProfile]::_localComputerDomainSidLookupTable.ContainsKey($compName)) {
            [UserProfile]::_localComputerDomainSidLookupTable.Add($compName, ([System.Security.Principal.SecurityIdentifier]((Get-CimInstance -Query "SELECT SID FROM Win32_UserAccount WHERE LocalAccount='TRUE'" -ComputerName $UserProfile.PSComputerName)[0].SID)).AccountDomainSid)
        }
        $this.IsLocal = (($null -eq $this.Sid.AccountDomainSid -or ($this.Sid.AccountDomainSid -eq ([UserProfile]::_localComputerDomainSidLookupTable[$compName]))))
        $this.IsSpecial = $UserProfile.Special
        $this.ComputerName = $UserProfile.PSComputerName
        $this._userProfile = $UserProfile
        $this._isDeleted = $false

        if ($CalculateProfileSize) {
            $this.CalculateProfileSize()
        }
    }

    [Void] CalculateProfileSize() {
        if ([String]::IsNullOrWhiteSpace($this.ProfilePath) -or (-not (Test-Path -LiteralPath $this.ProfilePath -ErrorAction Ignore))) {
            $this.ProfileSize = 0
            $this.ProfileSizeMB = [Decimal]::Zero
            return
        }

        #TODO: improve the speed of this using C#/PInvoke
        $this.ProfileSize = (Get-ChildItem -LiteralPath $this.ProfilePath -Recurse -Force -ErrorAction Ignore | Measure-Object -Property Length -Sum).Sum
        $this.ProfileSizeMB = [Math]::Round(($this.ProfileSize / 1MB), 2)
        return
    }

    [Void] Delete() {
        # While not 100% accurate, this is faster than running Get-CimInstance every time.
        if ($this._isDeleted -or ($null -eq $this._userProfile)) {
            return
        }

        if ($this.IsLoaded) {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.InvalidOperationException]::new('Loaded profiles cannot be deleted.'),
                'DeleteLoadedProfile',
                [System.Management.Automation.ErrorCategory]::InvalidOperation,
                $null
            )
        }

        # https://learn.microsoft.com/en-us/previous-versions/windows/desktop/userprofileprov/win32-userprofile
        ## "Whether the user profile is owned by a special system service. True if the user profile is owned by a system service; otherwise false."
        if ($this.IsSpecial) {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.InvalidOperationException]::new('Special profiles cannot be deleted.'),
                'DeleteSpecialProfile',
                [System.Management.Automation.ErrorCategory]::InvalidOperation,
                $null
            )
        }

        # Validate the the CIM instance still exists before attempting to delete it.
        try {
            $null = Get-CimInstance -InputObject $this._userProfile -ErrorAction Stop
        } catch [Microsoft.Management.Infrastructure.CimException] {
            if ($_.CateogryInfo.Cateogry -eq [System.Management.Automation.ErrorCategory]::ObjectNotFound) {
                $this._isDeleted = $true
                return
            }

            throw $_
        } catch {
            throw $_
        }

        Remove-CimInstance -InputObject $this._userProfile -ErrorAction Stop
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

    static [UserProfile[]] Get() {
        return ([UserProfile]::Get($null, $false))
    }

    static [UserProfile[]] Get([Boolean]$CalculateProfileSize) {
        return ([UserProfile]::Get($null, $CalculateProfileSize))
    }

    static [UserProfile[]] Get([String]$ComputerName) {
        return ([UserProfile]::Get($ComputerName, $false))
    }

    static [UserProfile[]] Get([String]$ComputerName, [Boolean]$CalculateProfileSize) {
        [Microsoft.Management.Infrastructure.CimInstance[]]$profs = if ([String]::IsNullOrWhiteSpace($ComputerName) -or ($ComputerName -in ($env:ComputerName, '.'))) {
            Get-CimInstance -ClassName Win32_UserProfile -ErrorAction Stop
        } else {
            Get-CimInstance -ClassName Win32_UserProfile -ComputerName $ComputerName -ErrorAction Stop
        }

        return $(foreach ($prof in $profs) {
            try {
                [UserProfile]::new($prof, $CalculateProfileSize)
            } catch {
                # Write-Error doesn't work in class methods:
                ## https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_classes_methods
                ## https://github.com/powershell/powershell/issues/5331
                <# if ($_.FullyQualifiedErrorId -eq 'nullToEnumInvalidCast') {
                    [System.Management.Automation.ErrorRecord]$err = [System.Management.Automation.ErrorRecord]::new(
                        [System.Management.Automation.RuntimeException]::new("The user profile '$($prof.SID)' is corrupted.", $_.Exception, $_),
                        'CorruptedUserProfile',
                        [System.Management.Automation.ErrorCategory]::InvalidData,
                        $prof
                    )
                    $err.CategoryInfo.Activity = '[UserProfile]::new()'
                    $err.CategoryInfo.Reason = 'The user profile is corrupted'
                    $err.CategoryInfo.TargetName = $prof.SID
                    [System.Management.Automation.ErrorDetails]$errorDetails = [System.Management.Automation.ErrorDetails]::new($_.Exception.Message)
                    $errorDetails.RecommendedAction = "Remove the user profile using the 'Clean-UserProfile' function."
                    $err.ErrorDetails = $errorDetails
                    Write-Error -ErrorRecord $err
                    continue
                } #>

                throw $_
            }
        })
    }
}