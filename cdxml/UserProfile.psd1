@{
    ModuleVersion = '1.0.0'
    #FormatsToProcess = ''
    #TypesToProcess = 'UserProfile.types.ps1xml'
    NestedModules = 'UserProfile.cmdletDefinition.cdxml'
    GUID = '{B57C2C20-0009-448A-ACCF-E815B018B4DA}'
    Author = 'Michael Hollingsworth'
    PowerShellVersion = '3.0'
    CompatiblePSEditions = 'Desktop', 'Core'
    FunctionsToExport = @(
        'Get-UserProfile',
        'Remove-UserProfile',
        'Set-UserProfileOwner'
    )
}