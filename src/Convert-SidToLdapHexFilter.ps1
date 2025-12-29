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