$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'ExternalUsageAdapters.ps1')
function Check([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Resolve-UtpAntigravityCli {return 'fixture-agy.exe'}
function Resolve-UtpClaudeUsageCli {return 'fixture-claude.exe'}
$script:Calls=@()
function Invoke-UtpExternalUsageCommand {
    param($FilePath,$Arguments,$MaximumBytes,$EnvironmentOverrides,[switch]$ClaudeUsageControl)
    $script:Calls+=[pscustomobject]@{File=$FilePath;Environment=$EnvironmentOverrides}
    if($Arguments -contains '--version'){
        return [pscustomobject]@{ExitCode=0;Output=$(if($FilePath -eq 'fixture-agy.exe'){'1.2.14'}else{'2.1.286'})}
    }
    if($ClaudeUsageControl){throw 'missing_usage_response'}
    [pscustomobject]@{ExitCode=0;Output='{"status":"SUCCESS","num_turns":0,"usage":{"input_tokens":0,"output_tokens":0},"conversation_id":"","command":{"type":"usage","data":{"groups":[{"name":"Gemini","buckets":[{"id":"gemini-5h","window":"5h","remaining_fraction":0.5,"reset_time":"2099-01-01T10:00:00Z"}]}]}}}'}
}
$original=$env:AGY_CLI_DISABLE_AUTO_UPDATE
try {
    $env:AGY_CLI_DISABLE_AUTO_UPDATE='false'
    $result=Get-UtpAntigravityCliUsage
    Check $result.available 'Updater suppression must preserve quota-only collection'
    Check ($script:Calls.Count -eq 2) 'Version and quota reads must both be performed'
    foreach($call in $script:Calls){Check ($null -ne $call.Environment -and $call.Environment['AGY_CLI_DISABLE_AUTO_UPDATE'] -ceq 'true') 'Every UTP AGY read must disable its background updater using literal true'}
    Check ($env:AGY_CLI_DISABLE_AUTO_UPDATE -ceq 'false') 'AGY overrides must never change the caller environment'
    $script:Calls=@()
    [void](Get-UtpClaudeControlUsage)
    foreach($call in $script:Calls){Check ($null -eq $call.Environment) 'The AGY flag must not be applied to Claude reads'}
    Write-Output 'AGY per-read updater suppression tests OK'
} finally {$env:AGY_CLI_DISABLE_AUTO_UPDATE=$original}
