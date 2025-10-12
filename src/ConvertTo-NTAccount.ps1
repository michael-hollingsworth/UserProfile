# Inspired by:
# - https://github.com/PSAppDeployToolkit/PSAppDeployToolkit/blob/bfbfa932560cac4043c44a3a33d74a581da708a7/src/PSADT/PSADT/AccountManagement/GroupPolicyAccountInfo.cs
# - https://github.com/PSAppDeployToolkit/PSAppDeployToolkit/blob/bfbfa932560cac4043c44a3a33d74a581da708a7/src/PSAppDeployToolkit/Public/ConvertTo-ADTNTAccountOrSID.ps1
class GroupPolicyAccountInfo {
    [System.Security.Principal.NTAccount]$Username
    [System.Security.Principal.SecurityIdentifier]$Sid

    GroupPolicyAccountInfo([System.Security.Principal.NTAccount]$Username, [System.Security.Principal.SecurityIdentifier]$Sid) {
        $this.Username = $Username
        $this.Sid = $Sid
    }

    static [GroupPolicyAccountInfo[]] GetGroupPolicyAccountInfo() {
        # Open the Group Policy Data Store and validate that it exists.
        [Microsoft.Win32.Registrykey]$gpDataStore = ([Microsoft.Win32.Registry]::LocalMachine).OpenSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\DataStore')
        if ($null -eq $gpDataStore) {
            return $null
        }

        [GroupPolicyAccountInfo[]]$accountInfoList = foreach ($sid in $gpDataStore.GetSubKeyNames()) {
            # Skip over anything that's not a proper SID.
            if (-not $sid.StartsWith('S-1-')) {
                continue
            }

            # Skip entries that don't exist.
            [Microsoft.Win32.Registrykey]$gpPrincipal = $gpDataStore.OpenSubKey($sid)
            if ($null -eq $gpPrincipal) {
                continue
            }

            # Process each index.
            foreach ($index in $gpPrincipal.GetSubKeyNames()) {
                [Microsoft.Win32.Registrykey]$principalInfo = $gpPrincipal.OpenSubKey($index)
                if (($gpUsername = $principalInfo.GetValue('szName', $null)) -and (-not [String]::IsNullOrWhiteSpace($gpUsername))) {
                    [GroupPolicyAccountInfo]::new($gpUsername, $sid)
                }
            }
        }

        return $accountInfoList
    }
}

function ConvertTo-NTAccount {
    [CmdletBinding()]
    [OutputType([System.Security.Principal.NTAccount])]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [Alias('SecurityIdentifier')]
        [System.Security.Principal.SecurityIdentifier]$Sid
    )

    begin {
        [GroupPolicyAccountInfo[]]$gpAccountInfo = [GroupPolicyAccountInfo]::GetGroupPolicyAccountInfo()
    } process {
        try {
            $Sid.Translate([System.Security.Principal.NTAccount])
        } catch {
            # If we don't have any GP info to fall back on, throw the original error
            if ($null -eq $gpAccountInfo -or $gpAccountInfo.Count -lt 1) {
                throw $_
            }

            # Identify GP account with matching SID and return it
            foreach ($account in $gpAccountInfo) {
                if ($account.Sid.Equals($Sid)) {
                    return ($account.Username)
                }
            }

            # If we don't have GP info with a matching SID, throw the original error
            throw $_
        }
    }
}

function ConvertTo-Sid {
    [CmdletBinding()]
    [OutputType([System.Security.Principal.SecurityIdentifier])]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [Alias('Username')]
        [System.Security.Principal.NTAccount]$NTAccount
    )

    begin {
        [GroupPolicyAccountInfo[]]$gpAccountInfo = [GroupPolicyAccountInfo]::GetGroupPolicyAccountInfo()
    } process {
        try {
            $NTAccount.Translate([System.Security.Principal.SecurityIdentifier])
        } catch {
            # If we don't have any GP info to fall back on, throw the original error
            if ($null -eq $gpAccountInfo -or $gpAccountInfo.Count -lt 1) {
                throw $_
            }

            # Identify GP account with matching username and return it
            foreach ($account in $gpAccountInfo) {
                if ($account.Username.Equals($NTAccount)) {
                    return ($account.Sid)
                }
            }

            # If we don't have GP info with a matching SID, throw the original error
            throw $_
        }
    }
}