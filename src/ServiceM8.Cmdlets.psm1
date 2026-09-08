<#
    ServiceM8.Cmdlets
    Typed cmdlets over the ServiceM8 engine.

    Each cmdlet is a thin wrapper around Invoke-Sm8Request / Invoke-Sm8List,
    giving friendly parameter names and pipeline support for a common resource.
#>

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# Jobs
# ---------------------------------------------------------------------------

function Get-Sm8Job {
    <#
    .SYNOPSIS
        List or retrieve ServiceM8 jobs.
    .DESCRIPTION
        With -All, returns every job (following pagination). Without -All, returns
        the first page. Use -Uuid to retrieve a single job.
    .EXAMPLE
        Get-Sm8Job -All
    .EXAMPLE
        Get-Sm8Job -Uuid '123e4567-c6e7-7d94-8a1f-2c225b01e65b'
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject[]])]
    param(
        [string] $Uuid,
        [string] $Query,
        [switch] $All
    )

    if ($Uuid) {
        return Invoke-Sm8Request -Path "job/$Uuid.json"
    }
    if ($All) {
        return Invoke-Sm8List -Path 'jobs' -Query @{ _query = $Query }
    }
    return Invoke-Sm8Request -Path 'jobs' -Query @{ _query = $Query }
}

function New-Sm8Job {
    <#
    .SYNOPSIS
        Create a new ServiceM8 job.
    .EXAMPLE
        New-Sm8Job -Body @{ date = '2026-09-09'; company_name = 'Acme' }
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [object] $Body
    )

    return Invoke-Sm8Request -Path 'job' -Method POST -Body $Body
}

function Update-Sm8Job {
    <#
    .SYNOPSIS
        Update an existing ServiceM8 job.
    .EXAMPLE
        Update-Sm8Job -Uuid '123e4567-...' -Body @{ date = '2026-09-10' }
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string] $Uuid,
        [Parameter(Mandatory)] [object] $Body
    )

    return Invoke-Sm8Request -Path "job/$Uuid" -Method POST -Body $Body
}

function Remove-Sm8Job {
    <#
    .SYNOPSIS
        Delete (deactivate) a ServiceM8 job.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='Medium')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)] [string] $Uuid
    )
    process {
        if ($Confirm -and -not $WhatIf) { }
        return Invoke-Sm8Request -Path "job/$Uuid" -Method DELETE
    }
}

# ---------------------------------------------------------------------------
# Companies
# ---------------------------------------------------------------------------

function Get-Sm8Company {
    <#
    .SYNOPSIS
        List or retrieve ServiceM8 companies.
    .EXAMPLE
        Get-Sm8Company -All
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject[]])]
    param(
        [string] $Uuid,
        [switch] $All
    )

    if ($Uuid) {
        return Invoke-Sm8Request -Path "company/$Uuid.json"
    }
    if ($All) {
        return Invoke-Sm8List -Path 'companies'
    }
    return Invoke-Sm8Request -Path 'companies'
}

function New-Sm8Company {
    <#
    .SYNOPSIS
        Create a new ServiceM8 company.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [object] $Body
    )
    return Invoke-Sm8Request -Path 'company' -Method POST -Body $Body
}

# ---------------------------------------------------------------------------
# Clients (customers)
# ---------------------------------------------------------------------------

function Get-Sm8Client {
    <#
    .SYNOPSIS
        List or retrieve ServiceM8 clients (customers).
    .EXAMPLE
        Get-Sm8Client -All
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject[]])]
    param(
        [string] $Uuid,
        [switch] $All
    )

    if ($Uuid) {
        return Invoke-Sm8Request -Path "client/$Uuid.json"
    }
    if ($All) {
        return Invoke-Sm8List -Path 'clients'
    }
    return Invoke-Sm8Request -Path 'clients'
}

# ---------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------

function Get-Sm8Material {
    <#
    .SYNOPSIS
        List or retrieve ServiceM8 materials.
    .EXAMPLE
        Get-Sm8Material -All
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject[]])]
    param(
        [string] $Uuid,
        [switch] $All
    )

    if ($Uuid) {
        return Invoke-Sm8Request -Path "material/$Uuid.json"
    }
    if ($All) {
        return Invoke-Sm8List -Path 'materials'
    }
    return Invoke-Sm8Request -Path 'materials'
}

function New-Sm8Material {
    <#
    .SYNOPSIS
        Create a new ServiceM8 material.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [object] $Body
    )
    return Invoke-Sm8Request -Path 'material' -Method POST -Body $Body
}

Export-ModuleMember -Function Get-Sm8Job, New-Sm8Job, Update-Sm8Job, Remove-Sm8Job,
    Get-Sm8Company, New-Sm8Company, Get-Sm8Client, Get-Sm8Material, New-Sm8Material
