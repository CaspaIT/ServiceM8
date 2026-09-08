@{
    RootModule           = 'ServiceM8.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = 'b6f4a2e1-3c7d-4f8a-9b2e-1a5c6d7e8f90'
    Author               = 'Caspa IT'
    CompanyName          = 'Caspa'
    Copyright            = '(c) Caspa. All rights reserved.'
    Description          = 'PowerShell wrapper for the ServiceM8 REST API: OAuth authentication and typed resource cmdlets.'

    PowerShellVersion    = '7.0'

    FunctionsToExport    = @(
        # Engine
        'Import-Sm8Config',
        'Connect-Sm8Client',
        'Get-Sm8Token',
        'Invoke-Sm8Request',
        'Invoke-Sm8List',
        'Get-Sm8ResourceRoot',
        # Cmdlets
        'Get-Sm8Job', 'New-Sm8Job', 'Update-Sm8Job', 'Remove-Sm8Job',
        'Get-Sm8Company', 'New-Sm8Company',
        'Get-Sm8Client',
        'Get-Sm8Material', 'New-Sm8Material'
    )
    CmdletsToExport     = @()
    VariablesToExport   = @()
    AliasesToExport     = @()

    PrivateData          = @{
        PSData = @{
            Tags         = @('ServiceM8', 'API', 'OAuth', 'REST', 'FieldService')
            ProjectUri   = 'https://github.com/CaspaIT/ServiceM8'
            LicenseUri   = 'https://github.com/CaspaIT/ServiceM8/blob/main/LICENSE'
        }
    }
}
