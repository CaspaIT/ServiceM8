<#
    ServiceM8.Engine
    Core engine for the ServiceM8 REST API wrapper.

    Responsibilities:
      - Loading client credentials from a .env file.
      - Running the OAuth 2.0 authorization_code flow and persisting tokens.
      - Injecting the bearer token, handling refresh, and making HTTP calls.
      - Walking cursor-based pagination.
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

# OAuth configuration. Redirect URI must match the one registered with the
# ServiceM8 Public Application.
$Script:RedirectUri = 'http://127.0.0.1:9177/oauth/callback'
$Script:AuthorizeUrl = 'https://go.servicem8.com/oauth/authorize'
$Script:AccessTokenUrl = 'https://go.servicem8.com/oauth/access_token'
$Script:ApiRoot = 'https://api.servicem8.com/api_1.0'

# Minimum skew before an access token is considered expired (seconds).
$Script:TokenRefreshBuffer = 60

# ---------------------------------------------------------------------------
# Config loading
# ---------------------------------------------------------------------------

function Import-Sm8Config {
    <#
    .SYNOPSIS
        Load ServiceM8 client credentials from a .env file.
    .DESCRIPTION
        Reads NAME=VALUE pairs from the .env file into module state. Called
        automatically by Connect-Sm8Client if no config has been loaded.
    .PARAMETER Path
        Path to the .env file. Defaults to ./ .env in the current directory.
    #>
    [CmdletBinding()]
    param(
        [string] $Path = (Join-Path (Get-Location) '.env')
    )

    if (-not (Test-Path $Path)) {
        throw "ServiceM8 config file not found at '$Path'. Copy .env.example to .env and fill in your client credentials."
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

    if (-not $config['SERVICE_M8_CLIENT_ID'] -or -not $config['SERVICE_M8_CLIENT_SECRET']) {
        throw "ServiceM8 config is missing SERVICE_M8_CLIENT_ID and/or SERVICE_M8_CLIENT_SECRET in '$Path'."
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
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            [Environment]::CurrentUserName, 'FullControl', 'Allow')
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
        'Authorization' = "Bearer $AccessToken"
        'Accept'        = 'application/json'
        'Content-Type'  = 'application/json'
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
    $err = [System.Management.Automation.ErrorRecord]::new(
        [System.Exception]::new($msg + " $uri"),
        'ServiceM8ApiError',
        [System.Management.Automation.ErrorCategory]::InvalidOperation,
        $null)
    if ($Inner) { $err.SetErrorRecord($Inner) }
    $PSCmdThrow = $null
    throw $err
}

# ---------------------------------------------------------------------------
# Authentication
# ---------------------------------------------------------------------------

function Connect-Sm8Client {
    <#
    .SYNOPSIS
        Authenticate against ServiceM8 using the OAuth 2.0 authorization_code flow.
    .DESCRIPTION
        Requires client credentials (loaded via Import-Sm8Config or from .env).
        Starts a local listener, opens the browser for user consent, exchanges the
        returned code for an access/refresh token pair, and stores the tokens.
    .PARAMETER Scopes
        Space-separated OAuth scopes, e.g. 'read_jobs read_customers manage_jobs'.
    .PARAMETER RedirectUri
        Override the redirect URI (must match the registered application URI).
    .PARAMETER Force
        Ignore any existing token and force a fresh authentication.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $Scopes,
        [string] $RedirectUri = $Script:RedirectUri,
        [switch] $Force
    )

    if ([string]::IsNullOrWhiteSpace($Scopes)) {
        throw "Scopes must be supplied, e.g. Connect-Sm8Client -Scopes 'read_jobs read_customers'."
    }

    if ($null -eq $Script:Sm8Config) { Import-Sm8Config }
    $config = $Script:Sm8Config

    if (-not $Force -and (Test-Path -LiteralPath $Script:TokenPath)) {
        Write-Verbose "Existing token cache found. Use -Force to re-authenticate."
        $existing = ConvertFrom-Sm8TokenFile
        if ($existing -and $existing.access_token) {
            return $existing
        }
    }

    if (-not $config.SERVICE_M8_CLIENT_ID -or -not $config.SERVICE_M8_CLIENT_SECRET) {
        throw "Client credentials missing. Run Import-Sm8Config or populate .env."
    }

    $listener = [System.Net.HttpListener]::new()
    $listener.Prefixes.Add($RedirectUri + '/')
    try {
        $listener.Start()
    } catch {
        throw "Could not start local listener on '$RedirectUri'. Run as administrator or choose another port. ($($_.Exception.Message))"
    }

    $state = [guid]::NewGuid().ToString('N')

    $params = [System.Web.HttpUtility]::UrlEncode(@{
        response_type = 'code'
        client_id     = $config.SERVICE_M8_CLIENT_ID
        scope         = $Scopes
        redirect_uri  = $RedirectUri
        state         = $state
    })

    $authorizeUrl = "$($Script:AuthorizeUrl)?response_type=code&client_id=$([System.Web.HttpUtility]::UrlEncode($config.SERVICE_M8_CLIENT_ID))&scope=$([System.Web.HttpUtility]::UrlEncode($Scopes))&redirect_uri=$([System.Web.HttpUtility]::UrlEncode($RedirectUri))&state=$state"

    Write-Verbose "Opening browser for consent."
    Start-Process $authorizeUrl

    Write-Verbose "Waiting for OAuth callback at $RedirectUri ..."
    $ctx = $listener.GetContext()
    $response = $ctx.Response
    $uri = $ctx.Request.Url

    # Echo back the returned state to detect tampering / mismatched requests.
    $qs = [System.Web.HttpUtility]::ParseQueryString($uri.Query)
    if ($qs['state'] -and $qs['state'] -ne $state) {
        $buffer = [Text.Encoding]::UTF8.GetBytes('Error: OAuth state mismatch.')
        $response.OutputStream.Write($buffer, 0, $buffer.Length)
        $response.Close()
        throw "OAuth state mismatch - request rejected."
    }

    if ($qs['error']) {
        $buffer = [Text.Encoding]::UTF8.GetBytes("OAuth error: $($qs['error'])")
        $response.OutputStream.Write($buffer, 0, $buffer.Length)
        $response.Close()
        throw "OAuth authorization rejected: $($qs['error'])"
    }
    if (-not $qs['code']) {
        $buffer = [Text.Encoding]::UTF8.GetBytes('No authorization code returned.')
        $response.OutputStream.Write($buffer, 0, $buffer.Length)
        $response.Close()
        throw "No authorization code returned by ServiceM8."
    }
    $code = $qs['code']

    $buffer = [Text.Encoding]::UTF8.GetBytes('Authentication complete. You can close this window and return to PowerShell.')
    $response.OutputStream.Write($buffer, 0, $buffer.Length)
    $response.Close()

    # Exchange the code for tokens.
    $body = [System.Web.HttpUtility]::UrlEncode(@{
        grant_type     = 'authorization_code'
        client_id      = $config.SERVICE_M8_CLIENT_ID
        client_secret  = $config.SERVICE_M8_CLIENT_SECRET
        code           = $code
        redirect_uri   = $RedirectUri
    })

    $token = $null
    try {
        $token = Invoke-RestMethod -Method Post -Uri $Script:AccessTokenUrl -ContentType 'application/x-www-form-urlencoded' -Body $body
    } catch {
        ConvertFrom-Sm8Error -StatusCode $_.Exception.Response.StatusCode.valueObj -ResponseBody $_.ErrorDetails.Message -Uri $Script:AccessTokenUrl -Inner $_.Record
    }

    if (-not $token.access_token) {
        throw "Token exchange did not return an access_token."
    }

    ConvertTo-Sm8TokenFile -Token $token
    Write-Verbose "Token stored at '$Script:TokenPath'."
    return $token
}

# ---------------------------------------------------------------------------
# Token refresh
# ---------------------------------------------------------------------------

function Get-Sm8Token {
    <#
    .SYNOPSIS
        Return a valid access token, refreshing it if necessary.
    .DESCRIPTION
        Reads the cached token. If the access token is expired or about to expire,
        it is refreshed using the refresh token. Returns a PSCustomObject with
        access_token, refresh_token and expires_in.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $token = ConvertFrom-Sm8TokenFile
    if (-not $token -or -not $token.access_token) {
        throw "No token available. Run Connect-Sm8Client first."
    }

    $now = [datetime]::Now
    $expiresAt = $now.AddSeconds([int]$token.expires_in)
    if ($now + [timespan]::FromSeconds($Script:TokenRefreshBuffer) -ge $expiresAt) {
        if (-not $token.refresh_token) {
            throw "Access token expired and no refresh_token is available. Run Connect-Sm8Client -Force."
        }
        Write-Verbose "Refreshing expired access token."
        $body = [System.Web.HttpUtility]::UrlEncode(@{
            grant_type    = 'refresh_token'
            client_id     = $Script:Sm8Config.SERVICE_M8_CLIENT_ID
            client_secret = $Script:Sm8Config.SERVICE_M8_CLIENT_SECRET
            refresh_token = $token.refresh_token
        })
        try {
            $refreshed = Invoke-RestMethod -Method Post -Uri $Script:AccessTokenUrl -ContentType 'application/x-www-form-urlencoded' -Body $body
        } catch {
            ConvertFrom-Sm8Error -StatusCode $_.Exception.Response.StatusCode.valueObj -ResponseBody $_.ErrorDetails.Message -Uri $Script:AccessTokenUrl -Inner $_.Record
        }
        ConvertTo-Sm8TokenFile -Token $refreshed
        $token = $refreshed
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

    if ($Query -and $Query.Count -gt 0) {
        $qs = [System.Web.HttpUtility]::UrlEncode($Query)
        $uri = "$uri?$qs"
    }

    $headers = New-Sm8RequestHeaders -AccessToken $token.access_token

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
        if ($_.Exception.Response) {
            $status = [int]$_.Exception.Response.StatusCode.valueObj
            try {
                $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                $reader.BaseStream.Position = 0
                $respBody = $reader.ReadToEnd()
            } catch { $respBody = $null }
        }
        ConvertFrom-Sm8Error -StatusCode $status -ResponseBody $respBody -Uri $uri -Inner $_.Record
    }
}

# ---------------------------------------------------------------------------
# Pagination
# ---------------------------------------------------------------------------

function Invoke-Sm8List {
    <#
    .SYNOPSIS
        Retrieve every record for a listable resource, following pagination.
    .DESCRIPTION
        ServiceM8 uses cursor-based pagination. This walks pages starting at
        cursor -1 until the X-Next-Cursor header is empty, returning all records.
    .PARAMETER Path
        Listable resource path, e.g. 'jobs' or 'companies'.
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
    $cursor = '-1'
    $page = 0

    do {
        $page++
        $pageQuery = [hashtable]::Synchronized(@{})
        if ($Query) { foreach ($k in $Query.Keys) { $pageQuery[$k] = $Query[$k] } }
        $pageQuery['_next-cursor'] = $cursor

        $result = Invoke-Sm8Request -Path $Path -Method GET -Query $pageQuery

        $records = $null
        if ($result -is [System.Collections.IDictionary]) {
            foreach ($key in $result.Keys) { $records = $result[$key]; break }
        } elseif ($result -is [array]) {
            $records = $result
        } else {
            $records = @($result)
        }

        if ($records) { $all.AddRange($records) }

        $cursor = if ($result -is [System.Collections.IDictionary] -and $result.ContainsKey('_next-cursor')) {
            $result['_next-cursor']
        } else {
            $null
        }
    } while ($cursor)

    if ($all.Count -eq 0) { return @() }
    if ($all.Count -eq 1) { return $all[0] }
    return ,$all.ToArray()
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
    Invoke-Sm8Request, Invoke-Sm8List, Get-Sm8ResourceRoot
