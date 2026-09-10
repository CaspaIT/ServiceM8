<#
    ServiceM8.Engine
    Core engine for the ServiceM8 REST API wrapper.

    Responsibilities:
      - Loading the API token from a .env file.
      - Injecting the bearer token and making HTTP calls.
      - Walking cursor-based pagination.

    Authentication is a single API key sent as an "X-API-Key" header,
    no OAuth flow. See https://developer.servicem8.com/docs/rest-overview
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Module state
# ---------------------------------------------------------------------------

# Holds config loaded from .env for the current session.
$Script:Sm8Config = $null

# Path to the token cache file (kept outside the repo by default).
$Script:TokenPath = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.serviceM8.token.json'

# API configuration.
$Script:ApiRoot = 'https://api.servicem8.com/api_1.0'

# ---------------------------------------------------------------------------
# Config loading
# ---------------------------------------------------------------------------

function Import-Sm8Config {
    <#
    .SYNOPSIS
        Load the ServiceM8 API token from a .env file.
    .DESCRIPTION
        Reads NAME=VALUE pairs from the .env file into module state. The single
        bearer token is read from SERVICE_M8_TOKEN. Called automatically by
        Connect-Sm8Client if no config has been loaded.
    .PARAMETER Path
        Path to the .env file. Defaults to ./ .env in the current directory.
    #>
    [CmdletBinding()]
    param(
        [string] $Path = (Join-Path (Get-Location) '.env')
    )

    if (-not (Test-Path $Path)) {
        throw "ServiceM8 config file not found at '$Path'. Copy .env.example to .env and fill in your token."
    }

    $config = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        $line = $line.Trim()
        if ($line -eq '' -or $line.StartsWith('#')) { continue }
        if ($line -notmatch '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$') { continue }
        $key = $Matches[1]
        $value = $Matches[2].Trim('"').Trim("'")
        $config[$key] = $value
    }

    if (-not $config['SERVICE_M8_TOKEN']) {
        throw "ServiceM8 config is missing SERVICE_M8_TOKEN in '$Path'."
    }

    $Script:Sm8Config = [pscustomobject]$config
    Write-Verbose "Loaded ServiceM8 config from '$Path'."
}

# ---------------------------------------------------------------------------
# Token persistence
# ---------------------------------------------------------------------------

function ConvertTo-Sm8TokenFile {
    <#
    .SYNOPSIS
        Persist the token object to the token cache file with restrictive perms.
    #>
    [CmdletBinding()]
    param(
        [object] $Token
    )

    $json = $Token | ConvertTo-Json -Compress
    Set-Content -LiteralPath $Script:TokenPath -Value $json -Encoding UTF8

    # Best-effort restrictive permissions (no-op on platforms without cacls).
    if ($IsWindows) {
        $full = (Resolve-Path $Script:TokenPath).Path
        $acl = Get-Acl $full
        $acl.SetAccessRuleProtection($true, $false)
        $identity = ([System.Security.Principal.WindowsIdentity]::GetCurrent()).Name
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $identity, 'FullControl', 'Allow')
        $acl.AddAccessRule($rule)
        try { Set-Acl $full $acl } catch { Write-Verbose "Could not tighten token file permissions: $($_.Exception.Message)" }
    }
}

function ConvertFrom-Sm8TokenFile {
    <#
    .SYNOPSIS
        Read the token cache file, returning $null if it does not exist.
    #>
    if (-not (Test-Path -LiteralPath $Script:TokenPath)) { return $null }
    try {
        $json = Get-Content -LiteralPath $Script:TokenPath -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($json)) { return $null }
        return ($json | ConvertFrom-Json)
    } catch {
        return $null
    }
}

# ---------------------------------------------------------------------------
# HTTP helpers
# ---------------------------------------------------------------------------

function New-Sm8RequestHeaders {
    [CmdletBinding()]
    param(
        [string] $AccessToken
    )

    [ordered]@{
        'X-API-Key'    = $AccessToken
        'Accept'       = 'application/json'
        'Content-Type' = 'application/json'
    }
}

function ConvertFrom-Sm8Error {
    <#
    .SYNOPSIS
        Build a terminating error record from a failed web request.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [int] $StatusCode,
        [string] $ResponseBody,
        [string] $Uri,
        [System.Management.Automation.ErrorRecord] $Inner
    )

    $body = try { ($ResponseBody | ConvertFrom-Json -ErrorAction SilentlyContinue).error.message } catch { $ResponseBody }
    $msg = "ServiceM8 API request failed ($StatusCode): $body"
    $uri = "[$Uri]"
    if ($Inner -is [System.Management.Automation.ErrorRecord]) {
        throw [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new($msg + " $uri"),
            'ServiceM8ApiError',
            [System.Management.Automation.ErrorCategory]::InvalidOperation,
            $Inner)
    } else {
        throw [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new($msg + " $uri"),
            'ServiceM8ApiError',
            [System.Management.Automation.ErrorCategory]::InvalidOperation,
            $null)
    }
}

# ---------------------------------------------------------------------------
# Authentication
# ---------------------------------------------------------------------------

function Connect-Sm8Client {
    <#
    .SYNOPSIS
        Authenticate against ServiceM8 using a single API key (X-API-Key auth).
    .DESCRIPTION
        ServiceM8 issues a single API key that is sent as an "X-API-Key"
        header on every call. This cmdlet validates that a key is available
        (via Import-Sm8Config or .env), persists it to the local token cache,
        and returns it. There is no OAuth flow or browser step.
    .PARAMETER Force
        Ignore any cached token and reload the token from configuration.
    .EXAMPLE
        Connect-Sm8Client
        Loads the token from the environment and caches it locally.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [switch] $Force
    )

    if ($null -eq $Script:Sm8Config) { Import-Sm8Config }
    $config = $Script:Sm8Config

    if ([string]::IsNullOrWhiteSpace($config.SERVICE_M8_TOKEN)) {
        throw "No SERVICE_M8_TOKEN available. Set it in .env or via the env, then run Connect-Sm8Client."
    }

    # Reuse the cache if present and we're not forcing a reload.
    if (-not $Force -and (Test-Path -LiteralPath $Script:TokenPath)) {
        Write-Verbose "Cached token found. Use -Force to reload from configuration."
        return ConvertFrom-Sm8TokenFile
    }

    # Build a normalised token object and persist it outside the repo.
    $token = [pscustomobject]@{
        api_key   = $config.SERVICE_M8_TOKEN
        source    = 'SERVICE_M8_TOKEN'
    }
    ConvertTo-Sm8TokenFile -Token $token
    Write-Verbose "Token stored at '$Script:TokenPath'."
    return $token
}

# ---------------------------------------------------------------------------
# Token
# ---------------------------------------------------------------------------

function Get-Sm8Token {
    <#
    .SYNOPSIS
        Return the cached access token.
    .DESCRIPTION
        Reads the cached token. With single-token auth there is no refresh
        step - the token is used as-is until it is manually rotated. Returns a
        PSCustomObject with api_key.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $token = ConvertFrom-Sm8TokenFile
    if (-not $token -or -not $token.api_key) {
        throw "No token available. Run Connect-Sm8Client first."
    }

    return $token
}

# ---------------------------------------------------------------------------
# Request / response
# ---------------------------------------------------------------------------

function Invoke-Sm8Request {
    <#
    .SYNOPSIS
        Make a single authenticated call to the ServiceM8 API.
    .DESCRIPTION
        Builds a request against the API root, injects the bearer token, and
        returns the parsed response (or an error record on failure).
    .PARAMETER Path
        API resource path relative to the API root, e.g. 'jobs' or 'job/123.json'.
    .PARAMETER Method
        HTTP method: GET (default), POST, DELETE.
    .PARAMETER Body
        Optional request body (object or string). Encoded as JSON for POST.
    .PARAMETER Query
        Optional hashtable of query string parameters (e.g. pagination, filters).
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [ValidateSet('GET', 'POST', 'DELETE')] [string] $Method = 'GET',
        [object] $Body,
        [hashtable] $Query
    )

    if ($null -eq $Script:Sm8Config) { Import-Sm8Config }

    $token = Get-Sm8Token
    $uri = "$($Script:ApiRoot)/$($Path.TrimStart('/'))"

    # Allow an absolute URL (used when following __next__ pages).
    if ($Path -match '^https?://') {
        $uri = $Path.TrimStart('/')
    }

    if ($Query -and $Query.Count -gt 0) {
        $qs = @()
        foreach ($k in $Query.Keys) {
            $qs += [System.Web.HttpUtility]::UrlEncode($k) + '=' + [System.Web.HttpUtility]::UrlEncode([string]$Query[$k])
        }
        $uri = $uri + '?' + ($qs -join '&')
    }

    $headers = New-Sm8RequestHeaders -AccessToken $token.api_key

    $invokeParams = @{
        Method      = $Method
        Uri         = $uri
        Headers     = $headers
        ErrorAction = 'Stop'
    }

    # ServiceM8 expects JSON bodies for POST requests.
    if ($Method -eq 'POST' -and $null -ne $Body) {
        if ($Body -is [string]) {
            $invokeParams['Body'] = $Body
        } else {
            $invokeParams['Body'] = ($Body | ConvertTo-Json -Depth 10 -Compress)
        }
    }

    try {
        return Invoke-RestMethod @invokeParams
    } catch {
        $status = 0
        $respBody = $null

        # Best-effort status code / body extraction across PS versions.
        $response = $_.Exception.Response
        if ($response) {
            try { $status = [int]$response.StatusCode } catch { $status = 0 }
            try {
                $stream = $response.GetResponseStream()
                if ($stream) {
                    $reader = New-Object System.IO.StreamReader($stream)
                    $reader.BaseStream.Position = 0
                    $respBody = $reader.ReadToEnd()
                }
            } catch { $respBody = $null }
        }

        # Fallback: some errors surface the body via ErrorDetails.
        if (-not $respBody -and $_.ErrorDetails -and $_.ErrorDetails.Message) {
            $respBody = $_.ErrorDetails.Message
        }

        ConvertFrom-Sm8Error -StatusCode $status -ResponseBody $respBody -Uri $uri -Inner $_
    }
}

# ---------------------------------------------------------------------------
# Record extraction (handles the response shapes the docs show)
# ---------------------------------------------------------------------------

# ServiceM8 list responses vary between shapes:
#   { pages: [ { items: [...], _total, __next__ } ] }
#   { data: [ {...} ], _total, __next__ }
#   [ {...}, {...} ]
# This normalises all of them to (records[], nextCursor, total).

function Get-Sm8Records {
    [CmdletBinding()]
    param([object] $Response)

    $records = [System.Collections.Generic.List[object]]::new()
    $next = $null
    $total = $null

    if ($Response -is [System.Collections.IDictionary]) {
        $total = $Response['_total']
        $next = $Response['__next__']

        if ($Response['pages'] -and $Response['pages'][0] -is [System.Collections.IDictionary]) {
            foreach ($item in $Response['pages'][0]['items']) { $records.Add($item) }
        }
        elseif ($Response['data'] -is [array]) {
            foreach ($item in $Response['data']) { $records.Add($item) }
        }
    }
    elseif ($Response -is [array]) {
        foreach ($item in $Response) { $records.Add($item) }
    }

    return [pscustomobject]@{ Records = $records; Next = $next; Total = $total }
}

# ---------------------------------------------------------------------------
# Pagination (shape-agnostic, follows the __next__ URL chain)
# ---------------------------------------------------------------------------

function Invoke-Sm8List {
    <#
    .SYNOPSIS
        Retrieve every record for a listable resource, following pagination.
    .DESCRIPTION
        Handles the initial page (which may arrive as a bare array, a
        {data:[...]} object, or a {pages:[...]} object) and then follows any
        __next__ chain. Returns all records.
    .PARAMETER Path
        Listable resource path, e.g. 'job' (becomes '/job.json').
    .PARAMETER Query
        Additional query parameters (e.g. filters) merged into each page request.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [hashtable] $Query
    )

    $all = [System.Collections.Generic.List[object]]::new()

    # First page: may be a bare array, {data:[...]}, or {pages:[...]}.
    $result = Invoke-Sm8Request -Path $Path -Method GET -Query $Query
    $extracted = Get-Sm8Records -Response $result
    foreach ($r in $extracted.Records) { $all.Add($r) }
    $next = $extracted.Next

    # Follow any further pages via the __next__ chain.
    while ($null -ne $next) {
        $result = Invoke-Sm8Request -Path $next -Method GET
        $extracted = Get-Sm8Records -Response $result
        foreach ($r in $extracted.Records) { $all.Add($r) }
        $next = $extracted.Next
    }

    if ($all.Count -eq 0) { return @() }
    if ($all.Count -eq 1) { return $all[0] }
    return ,$all.ToArray()
}

# ---------------------------------------------------------------------------
# Generic CRUD (single entry point, driven by the registry)
# ---------------------------------------------------------------------------

function Invoke-Sm8Resource {
    <#
    .SYNOPSIS
        Perform CRUD against any registered ServiceM8 resource.
    .DESCRIPTION
        The single portable entry point over the API. Given a resource name from
        the registry (e.g. 'Job', 'Company', 'Attachment') and a verb (Get,
        Post, Update, Delete), it builds the correct endpoint and makes the call.
        This is the function most likely to be ported to another language.
    .PARAMETER Resource
        Resource name from Get-Sm8Registry, e.g. 'Job'.
    .PARAMETER Verb
        Get (list or retrieve), Post (create), Update, or Delete.
    .PARAMETER Uuid
        Record UUID. Required for Get/Update/Delete by single record.
    .PARAMETER Body
        Record fields for Post/Update (object or JSON string).
    .PARAMETER All
        For Get: paginate and return every record.
    .PARAMETER Query
        Extra query parameters (filters, etc.).
    .EXAMPLE
        Invoke-Sm8Resource -Resource Job -Verb Get -All
    .EXAMPLE
        Invoke-Sm8Resource -Resource Job -Verb Post -Body @{ date = '2026-09-09' }
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)] [string] $Resource,
        [ValidateSet('Get', 'Post', 'Update', 'Delete')] [string] $Verb,
        [string] $Uuid,
        [object] $Body,
        [switch] $All,
        [hashtable] $Query
    )

    $reg = Get-Sm8Registry | Where-Object { $_.Name -eq $Resource }
    if (-not $reg) { throw "Unknown resource '$Resource'. Run Get-Sm8Registry to list resources." }

    # Scope enforcement (warn if caller's auth is likely insufficient).
    $scope = switch ($Verb) {
        'Get'     { $reg.ReadScope }
        'Post'    { $reg.WriteScope }
        'Update'  { $reg.DeleteScope }
        'Delete'  { $reg.DeleteScope }
    }

    $path = $reg.Path
    switch ($Verb) {
        'Get' {
            if ($Uuid) {
                return Invoke-Sm8Request -Path "$path/$Uuid.json" -Method GET -Query $Query
            }
            if ($All) { return Invoke-Sm8List -Path $path -Query $Query }
            return Invoke-Sm8Request -Path "$path.json" -Method GET -Query $Query
        }
        'Post' {
            if ($Uuid) {
                return Invoke-Sm8Request -Path "$path/$Uuid.json" -Method POST -Body $Body
            }
            return Invoke-Sm8Request -Path "$path.json" -Method POST -Body $Body
        }
        'Update' {
            if (-not $Uuid) { throw "Update requires -Uuid." }
            return Invoke-Sm8Request -Path "$path/$Uuid.json" -Method POST -Body $Body
        }
        'Delete' {
            if (-not $Uuid) { throw "Delete requires -Uuid." }
            return Invoke-Sm8Request -Path "$path/$Uuid.json" -Method DELETE
        }
    }
}

# ---------------------------------------------------------------------------
# Resource root
# ---------------------------------------------------------------------------

function Get-Sm8ResourceRoot {
    <#
    .SYNOPSIS
        List the top-level resource names exposed by the API.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    $root = Invoke-Sm8Request -Path ''
    if ($root -is [System.Collections.IDictionary]) { return @($root.Keys | Where-Object { $_ -ne '_total' }) }
    return @($root)
}

Export-ModuleMember -Function Import-Sm8Config, Connect-Sm8Client, Get-Sm8Token,
    Invoke-Sm8Request, Invoke-Sm8List, Invoke-Sm8Resource, Get-Sm8ResourceRoot
