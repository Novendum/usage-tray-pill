$sourceRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'
$ErrorActionPreference = 'Stop'
. (Join-Path $sourceRoot 'OpenCodeGo.ps1')
function Assert-Api { param([bool]$Condition, [string]$Message) if (-not $Condition) { throw $Message } }
function Assert-ApiError {
    param([scriptblock]$Action, [string]$Code)
    $actual = ''
    try { & $Action | Out-Null } catch { $actual = Get-OpenCodeGoExceptionCode $_ }
    Assert-Api ($actual -eq $Code) "Expected $Code, got $actual"
}
function Format-DateForStorage { param($Date) $Date.ToString('o') }
function Get-DateOrNull { param([string]$Value) try { if ($Value) { [datetime]::Parse($Value) } } catch { $null } }
function As-Array { param($Value) @($Value) }

$reset = [DateTimeOffset]::UtcNow.AddHours(1).ToString('o')
$fixture = @{ usage = @{
    rolling = @{ percent = 12.25; status = 'ok'; resetsAt = $reset }
    weekly = @{ percent = 100; status = 'rate-limited'; resetsAt = $reset }
    monthly = @{ percent = 0; status = 'ok'; resetsAt = $reset }
} } | ConvertTo-Json -Depth 5
$items = @(ConvertFrom-OpenCodeGoUsageResponse $fixture)
Assert-Api ($items.Count -eq 3 -and $items[0].key -eq 'five_hour' -and $items[1].key -eq 'seven_day') 'All canonical windows must be mapped.'
Assert-Api ($items[0].remainingPercent -eq 87.75 -and $items[1].remainingPercent -eq 0 -and $items[2].remainingPercent -eq 100) 'Usage must preserve fractional percentages and boundary values.'
Assert-Api ($items[1].status -eq 'rate-limited' -and [DateTimeOffset]::Parse($items[0].resetsAt) -eq [DateTimeOffset]::Parse($reset)) 'Preserve provider status and absolute reset time.'
Assert-ApiError { ConvertFrom-OpenCodeGoUsageResponse '{"usage":{}}' } 'parse_error'
Assert-ApiError { ConvertFrom-OpenCodeGoUsageResponse '<html>login</html>' } 'parse_error'
foreach ($invalid in @(-1, 101, 'NaN', $null, $true)) {
    $bad = $fixture | ConvertFrom-Json
    $bad.usage.rolling.percent = $invalid
    Assert-ApiError { ConvertFrom-OpenCodeGoUsageResponse $bad } 'parse_error'
}
$bad = $fixture | ConvertFrom-Json
$bad.usage.rolling.resetsAt = 'not-a-date'
Assert-ApiError { ConvertFrom-OpenCodeGoUsageResponse $bad } 'parse_error'
Assert-ApiError { ConvertTo-OpenCodeGoApiKey "fake`r`nInjected: bad" } 'invalid_auth'
Assert-ApiError { ConvertTo-OpenCodeGoApiKey 'Bearer fake-key' } 'invalid_auth'

# Credentials are synthetic and remain in memory; no provider or credential file is opened.
$protected = Protect-OpenCodeGoSecret 'synthetic-go-api-key'
$credential = ConvertFrom-OpenCodeGoStoredCredential ([pscustomobject]@{version=2;protectedApiKey=$protected})
Assert-Api ($credential.apiKey -eq 'synthetic-go-api-key' -and $protected -ne $credential.apiKey) 'DPAPI v2 key round trip failed.'
function Unprotect-OpenCodeGoSecret { throw 'Legacy credentials must never be decrypted.' }
Assert-ApiError { ConvertFrom-OpenCodeGoStoredCredential ([pscustomobject]@{version=1;protectedAuthCookie='not-decryptable'}) } 'api_key_required'

foreach ($pair in @(@(401,'auth_expired'),@(403,'subscription_required'),@(429,'rate_limited'),@(302,'server_error'),@(503,'server_error'))) {
    $errorObject = New-OpenCodeGoHttpException -StatusCode $pair[0] -RetryAfter '90'
    Assert-Api ($errorObject.Data['OpenCodeGoCode'] -eq $pair[1]) "Wrong HTTP mapping: $($pair[0])"
}
Assert-Api ((New-OpenCodeGoHttpException 429 '90').Data['retryAfterSeconds'] -eq 90) 'Retry-After seconds lost.'
Assert-Api ((ConvertTo-OpenCodeGoRetryAfterSeconds '999999') -eq 86400) 'Retry-After must be bounded.'
Assert-Api ((ConvertTo-OpenCodeGoRetryAfterSeconds 'NaN') -eq 0) 'Invalid Retry-After must be ignored.'
$now = [DateTimeOffset]::Parse('2026-01-01T00:00:00Z')
Assert-Api ((ConvertTo-OpenCodeGoRetryAfterSeconds 'Thu, 01 Jan 2026 00:01:30 GMT' $now) -eq 90) 'HTTP date Retry-After failed.'
$stream = New-Object IO.MemoryStream (,[Text.Encoding]::UTF8.GetBytes('eight888'))
try { Assert-ApiError { Read-OpenCodeGoLimitedUtf8Stream $stream -MaximumBytes 7 } 'response_too_large' } finally { $stream.Dispose() }

# In-memory snapshot and transport doubles exercise the actual collector without requests or writes.
$script:snapshot = [pscustomobject]@{lastSuccessAt=(Get-Date).ToString('o');items=$items;credentialRevision=(Get-UtpCredentialRevision 'opencodego')}
function Read-OpenCodeGoUsageSnapshotRaw { $script:snapshot }
function Write-OpenCodeGoUsageSnapshot { param($Usage) $script:snapshot = $Usage }
$successTime = $script:snapshot.lastSuccessAt
Set-OpenCodeGoFailureSnapshot -Code 'rate_limited' -Message 'Wait' -RetryAfterSeconds 90
Assert-Api ($script:snapshot.available -and $script:snapshot.stale -and $script:snapshot.retryAfterSeconds -eq 90) 'Transient failure must preserve stale values and retry delay.'
Set-OpenCodeGoFailureSnapshot -Code 'auth_expired' -Message 'Reconnect'
Assert-Api (-not $script:snapshot.available -and $script:snapshot.items.Count -eq 0 -and $script:snapshot.lastSuccessAt -eq $successTime) 'Auth failure must hide values while retaining last success time.'
function Get-OpenCodeGoCredentials { [pscustomobject]@{apiKey='synthetic-key'} }
function Invoke-OpenCodeGoUsageRequest { param($ApiKey) $fixture }
$script:State = [pscustomobject]@{settings=[pscustomobject]@{openCodeGoEnabled=$true}}
$script:OpenCodeGoUsagePollInProgress = $false
Assert-Api (Update-OpenCodeGoUsage) 'Collector success failed.'
Assert-Api ($script:snapshot.source -eq 'opencode-go-api' -and $script:snapshot.items[0].remainingPercent -eq 87.75) 'Collector lost canonical API data.'
function Invoke-OpenCodeGoUsageRequest { throw (New-OpenCodeGoHttpException 429 '123') }
Assert-Api (-not (Update-OpenCodeGoUsage)) 'Collector must return false after rate limiting.'
Assert-Api ($script:snapshot.retryAfterSeconds -eq 123 -and $script:snapshot.stale) 'Collector must preserve Retry-After.'
'OpenCode Go API regression checks passed (offline, no credential files).'
