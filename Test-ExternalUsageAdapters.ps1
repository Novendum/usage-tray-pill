$ErrorActionPreference = 'Stop'
$adapter = Join-Path $PSScriptRoot 'ExternalUsageAdapters.ps1'
if (-not (Test-Path -LiteralPath $adapter)) { throw 'External usage adapter is missing.' }
. $adapter

function Assert-ExternalTest([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Assert-ExternalRejected([scriptblock]$Action, [string]$Message) {
    $rejected = $false
    try { & $Action | Out-Null } catch { $rejected = $true }
    Assert-ExternalTest $rejected $Message
}

# Synthetic values in the externally observed command.data.groups[].buckets[]
# contract; this is NOT a captured local provider response.
$fixture = @'
{"status":"SUCCESS","num_turns":0,"conversation_id":"","usage":{"input_tokens":0,"output_tokens":0,"total_tokens":0},"command":{"data":{"groups":[{"name":"Gemini Models","buckets":[{"id":"gemini-5h","window":"5h","remaining_fraction":0.9378,"reset_time":"2099-01-01T10:00:00Z"},{"id":"gemini-weekly","window":"weekly","remaining_fraction":0,"reset_time":"2099-01-07T10:00:00Z"}]},{"name":"Claude and GPT models","buckets":[{"id":"3p-weekly","window":"weekly","remaining_fraction":null,"reset_time":"2099-01-07T10:00:00Z"}]}],"email":"must-not-escape@example.test","token":"must-not-escape"}}}
'@
$result = ConvertFrom-UtpAntigravityUsageJson -Json $fixture
Assert-ExternalTest ($result.available -and $result.items.Count -eq 3) 'Quota buckets must remain separate, including an unavailable bucket.'
Assert-ExternalTest ([Math]::Abs($result.items[0].remainingPercent - 93.78) -lt 0.00001) 'Quota precision must be preserved.'
Assert-ExternalTest ($result.items[1].remainingPercent -eq 0) 'An exhausted bucket must remain zero.'
Assert-ExternalTest ($null -eq $result.items[2].remainingPercent) 'A disabled/missing fraction must stay unknown.'
Assert-ExternalTest (($result | ConvertTo-Json -Depth 8) -notmatch 'must-not-escape') 'Only normalized quota fields may be returned.'
Assert-ExternalTest ($result.lastSuccessAt -eq $result.lastCheckedAt) 'Successful observation must have a success timestamp.'

Assert-ExternalRejected { ConvertFrom-UtpAntigravityUsageJson -Json ($fixture.Replace('"num_turns":0','"num_turns":1')) } 'A model-turn response must be rejected.'
Assert-ExternalRejected { ConvertFrom-UtpAntigravityUsageJson -Json ($fixture.Replace('"input_tokens":0','"input_tokens":3')) } 'Token-consuming output must be rejected.'
Assert-ExternalRejected { ConvertFrom-UtpAntigravityUsageJson -Json ($fixture.Replace('"conversation_id":""','"conversation_id":"new-session"')) } 'A new conversation must be rejected.'
Assert-ExternalRejected { ConvertFrom-UtpAntigravityUsageJson -Json ($fixture.Replace('0.9378','1.2')) } 'Out-of-range fractions must not be clamped into plausible usage.'
Assert-ExternalRejected { ConvertFrom-UtpAntigravityUsageJson -Json ($fixture.Replace('0.9378','"0.9378"')) } 'String fractions must not silently become numeric observations.'
Assert-ExternalRejected { ConvertFrom-UtpAntigravityUsageJson -Json ($fixture.Replace('2099-01-01T10:00:00Z','bad-date')) } 'Malformed reset dates must be rejected.'
Assert-ExternalRejected { ConvertFrom-UtpAntigravityUsageJson -Json '{}' } 'Unknown response contracts must be rejected.'
Assert-ExternalRejected { ConvertFrom-UtpAntigravityUsageJson -Json '[]' } 'A JSON array is not a usage response.'
Assert-ExternalRejected { ConvertFrom-UtpAntigravityUsageJson -Json ('x' * 1048577) } 'Oversized responses must be rejected before parsing.'
$expired = ConvertFrom-UtpAntigravityUsageJson -Json ($fixture.Replace('2099-01-01T10:00:00Z','2000-01-01T10:00:00Z'))
Assert-ExternalTest ($null -eq $expired.items[0].remainingPercent) 'Expired quota must not be displayed as current.'

$originalResolver = ${function:Resolve-UtpAntigravityCli}
try {
    function Resolve-UtpAntigravityCli { return '' }
    $missing = Get-UtpAntigravityCliUsage
    Assert-ExternalTest (-not $missing.available -and $missing.errorCode -eq 'setup_required' -and $missing.items.Count -eq 0) 'A missing CLI must report setup required.'
    $script:AntigravityUsagePath = 'synthetic-antigravity-usage.json'
    function Write-OpenCodeGoJsonAtomically { param($Path,$Value,$MutexName) $script:CapturedExternalWrite = @{Path=$Path;Value=$Value;MutexName=$MutexName} }
    Assert-ExternalTest (-not (Update-AntigravityCliUsage)) 'Missing CLI refresh must return false.'
    Assert-ExternalTest ($script:CapturedExternalWrite.Path -eq $script:AntigravityUsagePath -and $script:CapturedExternalWrite.Value.errorCode -eq 'setup_required') 'The collector wrapper must save the explicit unavailable snapshot.'
} finally { ${function:Resolve-UtpAntigravityCli} = $originalResolver }

$claudeFixture = '{"session":{"total_cost_usd":0,"model_usage":{}},"subscription_type":"max","rate_limits_available":true,"rate_limits":{"five_hour":{"utilization":12.345,"resets_at":"2099-01-01T10:00:00Z"},"seven_day":{"utilization":100,"resets_at":"2099-01-07T10:00:00Z"}},"behaviors":null}'
$claude = ConvertFrom-UtpClaudeControlUsageJson -Json $claudeFixture
Assert-ExternalTest ($claude.available -and $claude.items.Count -eq 2) 'Claude control windows must be normalized.'
Assert-ExternalTest ([Math]::Abs($claude.items[0].remainingPercent - 87.655) -lt 0.00001) 'Claude utilization uses percentages, not fractions.'
$noReset = ConvertFrom-UtpClaudeControlUsageJson -Json ($claudeFixture.Replace('"2099-01-01T10:00:00Z"','null').Replace('12.345','0'))
Assert-ExternalTest ($noReset.items[0].remainingPercent -eq 100 -and $noReset.items[0].resetsAt -eq '') 'A valid unused Claude window can have no reset date yet'
$noContext = ConvertFrom-UtpClaudeControlUsageJson -Json '{"session":{"total_cost_usd":0,"model_usage":{}},"rate_limits_available":false,"rate_limits":null,"behaviors":null}'
Assert-ExternalTest ($noContext.errorCode -eq 'unsupported_auth_context' -and -not $noContext.available) 'Missing plan context must not claim no subscription or report success.'
Assert-ExternalRejected { ConvertFrom-UtpClaudeControlUsageJson -Json ($claudeFixture.Replace('12.345','101')) } 'Invalid Claude utilization must be rejected.'
Assert-ExternalRejected { ConvertFrom-UtpClaudeControlUsageJson -Json ($claudeFixture.Replace('"behaviors":null','"behaviors":{}')) } 'Unexpected transcript scan output must be rejected.'
Assert-ExternalRejected { ConvertFrom-UtpClaudeControlUsageJson -Json ($claudeFixture.Replace('"total_cost_usd":0','"total_cost_usd":0.001')) } 'Unexpected Claude session costs must be rejected.'

# Child processes below are local synthetic PowerShell fixtures, never providers.
$powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$commandResult = Invoke-UtpExternalUsageCommand -FilePath $powershell -Arguments @('-NoProfile','-Command',"[Console]::Error.Write(('e' * 32768)); [Console]::Out.Write('two words')")
Assert-ExternalTest ($commandResult.ExitCode -eq 0 -and $commandResult.Output -eq 'two words') 'The process runner must quote arguments and drain stderr without deadlock.'
Assert-ExternalRejected { Invoke-UtpExternalUsageCommand -FilePath $powershell -Arguments @('-NoProfile','-Command',"[Console]::Out.Write(('x' * 8192))") -MaximumBytes 64 } 'Output must be bounded while streaming.'
Assert-ExternalRejected { Invoke-UtpExternalUsageCommand -FilePath $powershell -Arguments @('-NoProfile','-Command','Start-Sleep -Seconds 5') -TimeoutMilliseconds 150 } 'Timed out owned child processes must be stopped.'

$controlFixture = @'
$first = [Console]::ReadLine() | ConvertFrom-Json
if ($first.type -ne 'control_request' -or $first.request.subtype -ne 'initialize') { exit 8 }
[Console]::WriteLine('{"type":"control_response","response":{"request_id":"utp-init","subtype":"success","response":{}}}')
$second = [Console]::ReadLine() | ConvertFrom-Json
if ($second.type -ne 'control_request' -or $second.request.subtype -ne 'get_usage' -or -not $second.request.skip_behaviors) { exit 9 }
[Console]::WriteLine('{"type":"control_response","response":{"request_id":"utp-usage","subtype":"success","response":{"session":{"total_cost_usd":0,"model_usage":{}},"rate_limits_available":false,"rate_limits":null,"behaviors":null}}}')
Start-Sleep -Seconds 5
'@
$control = Invoke-UtpExternalUsageCommand -FilePath $powershell -Arguments @('-NoProfile','-Command',$controlFixture) -ClaudeUsageControl
$controlData = $control.Output | ConvertFrom-Json
Assert-ExternalTest ($control.ExitCode -eq 0 -and $controlData.rate_limits_available -eq $false) 'Control protocol must initialize, request usage with transcript scan disabled, then stop its owned process.'
$activityFixture = '[Console]::WriteLine(''{"type":"assistant","message":{}}''); Start-Sleep -Seconds 5'
Assert-ExternalRejected { Invoke-UtpExternalUsageCommand -FilePath $powershell -Arguments @('-NoProfile','-Command',$activityFixture) -ClaudeUsageControl } 'Unexpected model activity must stop the owned process.'

Write-Host 'External usage adapter tests passed (fixtures only; no provider calls).'
