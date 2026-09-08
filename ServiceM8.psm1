<#
    ServiceM8 module loader.

    Imports the engine and the typed cmdlets. Keeping them in separate files
    makes the module easier to extend as new resources are added.
#>

$script:ModuleRoot = $PSScriptRoot
$script:ModuleSrc = Join-Path $PSScriptRoot 'src'

# Import every engine/cmdlet module in src/.
Import-Module (Join-Path $script:ModuleSrc 'ServiceM8.Engine.psm1') -Force
Import-Module (Join-Path $script:ModuleSrc 'ServiceM8.Cmdlets.psm1') -Force
