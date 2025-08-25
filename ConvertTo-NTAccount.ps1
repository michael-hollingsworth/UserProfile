# Taken directly from:
# - https://github.com/PSAppDeployToolkit/PSAppDeployToolkit/blob/bfbfa932560cac4043c44a3a33d74a581da708a7/src/PSADT/PSADT/AccountManagement/GroupPolicyAccountInfo.cs
# - https://github.com/PSAppDeployToolkit/PSAppDeployToolkit/blob/bfbfa932560cac4043c44a3a33d74a581da708a7/src/PSAppDeployToolkit/Public/ConvertTo-ADTNTAccountOrSID.ps1
class GroupPolicyAccountInfo {
    [System.Security.Principal.NTAccount]$Username
    [System.Security.Principal.SecurityIdentifier]$Sid
    hidden static [String]$_groupPolicyDataStorePath = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\DataStore'

    GroupPolicyAccountInfo([System.Security.Principal.NTAccount]$Username, [System.Security.Principal.SecurityIdentifier]$Sid) {
        $this.Username = $Username
        $this.Sid = $Sid
    }

    static [GroupPolicyAccountInfo[]] Get() {
        [System.Collections.Generic.List[GroupPolicyAccountInfo]]$accountInfoList = [System.Collections.Generic.List[GroupPolicyAccountInfo]]::new()

        # Confirm we have a Group Policy Data Store to work with.
        [Microsoft.Win32.Registrykey]$gpDataStore = ([Microsoft.Win32.Registry]::LocalMachine).OpenSubKey([GroupPolicyAccountInfo]::_groupPolicyDataStorePath)
        if ($null -eq $gpDataStore) {
            return $accountInfoList
        }

        # Create list to hold the account information and process each found SID, returning the accumulated results.
        foreach ($sid in $gpDataStore.GetSubKeyNames()) {
            # Skip over anything that's not a proper SID.
            if (-not $sid.StartsWith('S-1-')) {
                continue
            }

            # Skip over the entry if there's no indices.
            [Microsoft.Win32.Registrykey]$gpPrincipal = ([Microsoft.Win32.Registry]::LocalMachine).OpenSubKey("$([GroupPolicyAccountInfo]::_groupPolicyDataStorePath)\$sid")
            if ($null -eq $gpPrincipal) {
                continue
            }

            # Process each found index.
            foreach ($index in $gpPrincipal.GetSubKeyNames()) {
                [Microsoft.Win32.Registrykey]$info = ([Microsoft.Win32.Registry]::LocalMachine).OpenSubKey("$([GroupPolicyAccountInfo]::_groupPolicyDataStorePath)\$sid\$index")
                if (($gpUsername = $info.GetValue('szName', $null)) -and (-not [String]::IsNullOrWhiteSpace($gpUsername))) {
                    $accountInfoList.Add([GroupPolicyAccountInfo]::new($gpUsername, $sid))
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
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [System.Security.Principal.SecurityIdentifier]$Sid
    )

    try {
        $Sid.Translate([System.Security.Principal.NTAccount])
    } catch {
        if (-not ([System.Security.Principal.NTAccount]$ntAccount = [GroupPolicyAccountInfo]::Get() | & { if ($_.Sid.Equals($Sid)) { return $_.Username } } | Select-Object -First 1)) {
            throw
        }

        return $ntAccount
    }
}

function ConvertTo-Sid {
    [CmdletBinding()]
    [OutputType([System.Security.Principal.SecurityIdentifier])]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [Alias('Username')]
        [System.Security.Principal.NTAccount]$NTAccount
    )

    try {
        $NTAccount.Translate([System.Security.Principal.SecurityIdentifier])
    } catch {
        if (-not ([System.Security.Principal.SecurityIdentifier]$sid = [GroupPolicyAccountInfo]::Get() | & { if ($_.Username.Equals($NTAccount)) { return $_.Sid } } | Select-Object -First 1)) {
            throw
        }

        return $sid
    }
}