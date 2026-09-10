BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'ServiceM8.psd1'
    $ModulePath = (Resolve-Path $ModulePath).Path
    Import-Module $ModulePath -Force
}

Describe 'Module structure' {
    It 'imports without error' {
        { Import-Module $ModulePath -Force -ErrorAction Stop } | Should -Not -Throw
    }

    It 'passes Test-ModuleManifest' {
        { Test-ModuleManifest -Path $ModulePath } | Should -Not -Throw
    }

    It 'exports the engine functions' {
        $expected = 'Import-Sm8Config', 'Connect-Sm8Client', 'Get-Sm8Token',
            'Invoke-Sm8Request', 'Invoke-Sm8List', 'Get-Sm8ResourceRoot'
        foreach ($name in $expected) {
            Get-Command -Name $name -Module ServiceM8 -ErrorAction SilentlyContinue |
                Should -Not -BeNullOrEmpty
        }
    }

    It 'exports the typed cmdlets' {
        $expected = 'Get-Sm8Job', 'New-Sm8Job', 'Update-Sm8Job', 'Remove-Sm8Job',
            'Get-Sm8Company', 'New-Sm8Company', 'Get-Sm8Client',
            'Get-Sm8Material', 'New-Sm8Material'
        foreach ($name in $expected) {
            Get-Command -Name $name -Module ServiceM8 -ErrorAction SilentlyContinue |
                Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Connect-Sm8Client' {
    It 'throws when no token is available' {
        # Temporarily move .env aside so config has no token to load, then
        # restore it regardless of the outcome.
        $envPath = Join-Path (Get-Location) '.env'
        $backup = $envPath + '.pester-backup'
        $moved = $false
        if (Test-Path -LiteralPath $envPath) {
            Move-Item -LiteralPath $envPath -Destination $backup -Force
            $moved = $true
        }
        try {
            { Connect-Sm8Client } | Should -Throw
        } finally {
            if ($moved) {
                Move-Item -LiteralPath $backup -Destination $envPath -Force
            }
        }
    }
}
