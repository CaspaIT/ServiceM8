# Prints the auth configuration used by the module, without emitting the
# secret itself. Run before Pester to sanity-check the environment.
$token = if ($null -ne $env:SERVICE_M8_TOKEN -and $env:SERVICE_M8_TOKEN -ne '') { 'yes' } else { '(unset)' }
Write-Host "SERVICE_M8_TOKEN : $token"
