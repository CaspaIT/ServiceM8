# ServiceM8

A PowerShell wrapper for the [ServiceM8 REST API](https://developer.servicem8.com/docs/rest-overview).

It handles OAuth 2.0 authentication and exposes ServiceM8 resources (jobs, companies, clients, materials, ...) as typed cmdlets.

## Requirements

- PowerShell 7.0 or later
- A registered ServiceM8 [Public Application](https://developer.servicem8.com/docs/authentication) (App ID + App Secret)

## Installation

```powershell
Import-Module ./ServiceM8.psd1 -Force
```

Or add it to your PowerShell profile.

## Configuration

1. Register a Public Application in the ServiceM8 Developer Directory to get an **App ID** and **App Secret**.
2. Set the application's redirect URI to `http://127.0.0.1:9177/oauth/callback`.
3. Create a local config file:

```powershell
Copy-Item .env.example .env
# then edit .env and fill in your client credentials
```

`.env` is gitignored — never commit it.

## Authentication

```powershell
Import-Sm8Config            # loads .env (done automatically on first use)

Connect-Sm8Client -Scopes 'read_jobs read_customers manage_jobs'
```

`Connect-Sm8Client` opens a browser for you to consent, starts a brief local
listener to capture the OAuth callback, exchanges the code for a token pair, and
stores the tokens in `~/.serviceM8.token.json` (gitignored). The access token is
refreshed automatically via the refresh token when it nears expiry.

Reuse an existing session with `Get-Sm8Token`.

## Usage

```powershell
# List every job (pagination handled automatically)
Get-Sm8Job -All

# Get a single job
Get-Sm8Job -Uuid '123e4567-c6e7-7d94-8a1f-2c225b01e65b'

# Create a job
New-Sm8Job -Body @{
    date          = '2026-09-09'
    company_name  = 'Acme Plumbing'
    job_description = 'Fix leak'
}

# List companies / clients / materials
Get-Sm8Company -All
Get-Sm8Client -All
Get-Sm8Material -All
```

### Generic request

For anything not covered by a typed cmdlet, drop down to the engine:

```powershell
# Single page
Invoke-Sm8Request -Path 'jobs' -Method GET

# All pages, following cursor-based pagination
Invoke-Sm8List -Path 'jobs'
```

### OAuth scopes

Each resource requires specific scopes (e.g. `read_jobs`, `manage_jobs`).
Request only the scopes your use case needs. See the ServiceM8 docs for the
full list: <https://developer.servicem8.com/reference/listjobs.md>.

## Module layout

```
ServiceM8/
├── ServiceM8.psd1            # module manifest
├── ServiceM8.psm1            # loader (dot-sources src/)
├── src/
│   ├── ServiceM8.Engine.psm1 # config, OAuth, token store, invoke, pagination
│   └── ServiceM8.Cmdlets.psm1# typed resource cmdlets
└── tests/
    └── ServiceM8.Tests.ps1   # Pester tests
```

## Testing

```powershell
Invoke-Pester -Path ./tests
```

The tests exercise module load, manifest validation, and exported commands
without making live API calls.

## Cleanup

Delete the local token cache:

```powershell
Remove-Item "$HOME/.serviceM8.token.json" -ErrorAction SilentlyContinue
```
