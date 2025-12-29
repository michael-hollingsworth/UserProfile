<#
.SYNOPSIS
    Converts an SID to an escape hexadecimal format, for use in LDAP filters
.PARAMETER Sid
    The SID(s) to convert to hexadecimal strings
.EXAMPLE
    Convert-SidToLdapHexFilter -Sid 'S-1-5-80-3139157870-2983391045-3678747466-658725712-1809340420'
.NOTES
    Author: Michael Hollingsworth
#>
function Convert-SidToLdapHexFilter {
    [CmdletBinding()]
    [OutputType([String])]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [System.Security.Principal.SecurityIdentifier[]]$Sid
    )

    process {
        foreach ($id in $Sid) {
            [Byte[]]$byteArray = [Byte[]]::new($id.BinaryLength)
            $id.GetBinaryForm($byteArray, 0)

            $PSCmdlet.WriteObject($([String]::Join('', $(foreach ($byte in $byteArray) {
                [String]::Format('\{0:X2}', $byte)
            }))))
        }
    }
}