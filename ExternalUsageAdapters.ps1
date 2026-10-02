# External quota adapters. Dot-sourcing this file performs no provider requests.
# AGY invocation: https://antigravity.google/docs/changelog/ (CLI 1.1.11).
# Observed JSON contract, not a Google-published schema:
# https://signoz.io/docs/antigravity-cli-monitoring/
# https://github.com/mmayasaurus/heddle-dashboard/blob/main/docs/USAGE_TAP.md
# Claude control contract: official @anthropic-ai/claude-agent-sdk 0.3.287 sdk.d.ts.

function New-UtpExternalUsageFailure {
    param([string]$Source, [string]$Code, [string]$Message)
    [pscustomobject]@{
        source = $Source; lastCheckedAt = [DateTimeOffset]::UtcNow.ToString('o')
        lastSuccessAt = ''; lastError = $Message; errorCode = $Code
        available = $false; items = @()
    }
}

function ConvertTo-UtpNativeArgument {
    param([AllowEmptyString()][string]$Value)
    # Windows CommandLineToArgvW/CRT quoting, including empty arguments.
    '"' + ([regex]::Replace([regex]::Replace($Value, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1')) + '"'
}

function Start-UtpUsageProcess {
    param([Parameter(Mandatory = $true)][System.Diagnostics.Process]$Process)
    # .NET Framework creates an auto-flushing stdin writer during Start().
    # Suppress its UTF-8 BOM without changing the console codepage. All JSONL
    # provider starts share this lock, including starts that need no override.
    [System.Threading.Monitor]::Enter([System.Diagnostics.Process])
    $changedEncoding = $false
    try {
        $inputEncoding = [Console]::InputEncoding
        if ($inputEncoding.CodePage -eq 65001 -and $inputEncoding.GetPreamble().Length -gt 0) {
            [Console]::InputEncoding = New-Object System.Text.UTF8Encoding $false
            $changedEncoding = $true
        }
        return $Process.Start()
    } finally {
        try { if ($changedEncoding) { [Console]::InputEncoding = $inputEncoding } }
        finally { [System.Threading.Monitor]::Exit([System.Diagnostics.Process]) }
    }
}

function Invoke-UtpExternalUsageCommand {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @(),
        [ValidateRange(100,30000)][int]$TimeoutMilliseconds = 30000,
        [ValidateRange(1,1048576)][int]$MaximumBytes = 1048576,
        [switch]$ClaudeUsageControl
    )
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo.FileName = $FilePath
    $process.StartInfo.Arguments = (($Arguments | ForEach-Object { ConvertTo-UtpNativeArgument $_ }) -join ' ')
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.CreateNoWindow = $true
    $process.StartInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $process.StartInfo.RedirectStandardInput = $true
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    $process.StartInfo.WorkingDirectory = [System.IO.Path]::GetTempPath()
    $memory = New-Object System.IO.MemoryStream
    $stdoutBuffer = New-Object byte[] 4096
    $stderrBuffer = New-Object byte[] 4096
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $seenBytes = 0
    $initialized = $false
    $usageComplete = $false
    $lineOffset = 0
    try {
        if (-not (Start-UtpUsageProcess -Process $process)) { throw 'process_failed' }
        if ($ClaudeUsageControl) {
            $process.StandardInput.WriteLine('{"type":"control_request","request_id":"utp-init","request":{"subtype":"initialize","hooks":{},"sdkMcpServers":[]}}')
            $process.StandardInput.Flush()
        } else { $process.StandardInput.Close() }
        $stdoutRead = $process.StandardOutput.BaseStream.ReadAsync($stdoutBuffer,0,$stdoutBuffer.Length)
        $stderrRead = $process.StandardError.BaseStream.ReadAsync($stderrBuffer,0,$stderrBuffer.Length)
        $stdoutDone = $false
        $stderrDone = $false
        while (-not ($stdoutDone -and $stderrDone -and $process.HasExited)) {
            if ($watch.ElapsedMilliseconds -ge $TimeoutMilliseconds) { throw 'timeout' }
            if (-not $stderrDone -and $stderrRead.IsCompleted) {
                $count = $stderrRead.GetAwaiter().GetResult()
                if ($count -eq 0) { $stderrDone = $true }
                else {
                    # Drain diagnostics without retaining or returning their contents.
                    $diagnostic = [System.Text.Encoding]::UTF8.GetString($stderrBuffer,0,$count)
                    if ($diagnostic -match '(?i)(authentication required|not logged in|not signed in|please (log|sign) in|open.*browser.*(auth|login)|https://[^\s]*(oauth|authorize))') { throw 'auth_required' }
                    $diagnostic = $null
                    [Array]::Clear($stderrBuffer,0,$stderrBuffer.Length)
                    $stderrRead = $process.StandardError.BaseStream.ReadAsync($stderrBuffer,0,$stderrBuffer.Length)
                }
            }
            if (-not $stdoutDone -and $stdoutRead.IsCompleted) {
                $count = $stdoutRead.GetAwaiter().GetResult()
                if ($count -eq 0) { $stdoutDone = $true }
                else {
                    $seenBytes += $count
                    if ($seenBytes -gt $MaximumBytes) { throw 'response_too_large' }
                    $memory.Write($stdoutBuffer,0,$count)
                    if ($ClaudeUsageControl) {
                        $text = [System.Text.Encoding]::UTF8.GetString($memory.ToArray())
                        $newline = $text.IndexOf("`n",$lineOffset)
                        while ($newline -ge 0) {
                            $line = $text.Substring($lineOffset,$newline-$lineOffset).Trim()
                            $lineOffset = $newline + 1
                            if ($line.Length -gt 0) {
                                $event = $line | ConvertFrom-Json -ErrorAction Stop
                                if ($event.type -in @('user','assistant','result','stream_event')) { throw 'unexpected_model_activity' }
                                if ($event.type -eq 'control_request') { throw 'interaction_required' }
                                if ($event.type -eq 'control_response') {
                                    $reply = $event.response
                                    if ($reply.request_id -eq 'utp-init') {
                                        if ($reply.subtype -ne 'success' -or $initialized) { throw 'initialization_failed' }
                                        $initialized = $true
                                        $process.StandardInput.WriteLine('{"type":"control_request","request_id":"utp-usage","request":{"subtype":"get_usage","skip_behaviors":true}}')
                                        $process.StandardInput.Flush()
                                    } elseif ($reply.request_id -eq 'utp-usage') {
                                        if (-not $initialized -or $reply.subtype -ne 'success') { throw 'usage_request_failed' }
                                        $usageComplete = $true
                                        # No user message is ever written. The response is already complete.
                                        return [pscustomobject]@{ ExitCode = 0; Output = ($reply.response | ConvertTo-Json -Depth 30 -Compress) }
                                    }
                                }
                            }
                            $newline = $text.IndexOf("`n",$lineOffset)
                        }
                    }
                    $stdoutRead = $process.StandardOutput.BaseStream.ReadAsync($stdoutBuffer,0,$stdoutBuffer.Length)
                }
            }
            Start-Sleep -Milliseconds 10
        }
        if ($ClaudeUsageControl -and -not $usageComplete) { throw 'missing_usage_response' }
        [pscustomobject]@{ ExitCode = $process.ExitCode; Output = [System.Text.Encoding]::UTF8.GetString($memory.ToArray()) }
    } finally {
        try { if (-not $process.HasExited) { $process.Kill(); [void]$process.WaitForExit(1000) } } catch { }
        $process.Dispose()
        $memory.Dispose()
        [Array]::Clear($stdoutBuffer,0,$stdoutBuffer.Length)
        [Array]::Clear($stderrBuffer,0,$stderrBuffer.Length)
    }
}

function Resolve-UtpAntigravityCli {
    $known = Join-Path $env:LOCALAPPDATA 'agy\bin\agy.exe'
    if (Test-Path -LiteralPath $known -PathType Leaf) { return $known }
    foreach ($command in @(Get-Command agy.exe -All -CommandType Application -ErrorAction SilentlyContinue)) {
        if ([System.IO.Path]::GetExtension($command.Source) -eq '.exe' -and (Test-Path -LiteralPath $command.Source -PathType Leaf)) { return [string]$command.Source }
    }
    return ''
}

function ConvertFrom-UtpAntigravityUsageJson {
    param([Parameter(Mandatory = $true)][string]$Json)
    if ([System.Text.Encoding]::UTF8.GetByteCount($Json) -gt 1048576) { throw 'response_too_large' }
    $payload = $Json | ConvertFrom-Json -ErrorAction Stop
    if ($payload -isnot [pscustomobject] -or $payload.status -cne 'SUCCESS' -or
        $null -eq $payload.num_turns -or $payload.num_turns -ne 0 -or
        -not [string]::IsNullOrEmpty([string]$payload.conversation_id) -or
        $null -eq $payload.command.data.groups) { throw 'unsupported_response' }
    foreach ($property in @($payload.usage.PSObject.Properties)) {
        if ($property.Name -match 'tokens$' -and $null -ne $property.Value -and $property.Value -ne 0) { throw 'unexpected_model_activity' }
    }
    $now = [DateTimeOffset]::UtcNow
    $items = @()
    $keys = @{}
    foreach ($group in @($payload.command.data.groups)) {
        if ($null -eq $group.buckets) { throw 'unsupported_response' }
        foreach ($bucket in @($group.buckets)) {
            $key = [string]$bucket.id
            if ($key -notmatch '^[a-zA-Z0-9_-]{1,80}$' -or $keys.ContainsKey($key) -or $bucket.window -notin @('5h','weekly')) { throw 'unsupported_response' }
            $keys[$key] = $true
            $fraction = $bucket.remaining_fraction
            if ($null -ne $fraction -and ($fraction -is [string] -or $fraction -is [bool] -or
                -not ($fraction -is [ValueType]) -or [double]::IsNaN([double]$fraction) -or
                [double]::IsInfinity([double]$fraction) -or [double]$fraction -lt 0 -or [double]$fraction -gt 1)) { throw 'invalid_fraction' }
            $reset = [DateTimeOffset]::MinValue
            if ([string]$bucket.reset_time -notmatch '(Z|[+-]\d\d:\d\d)$' -or
                -not [DateTimeOffset]::TryParse([string]$bucket.reset_time,[System.Globalization.CultureInfo]::InvariantCulture,[System.Globalization.DateTimeStyles]::None,[ref]$reset)) { throw 'invalid_reset' }
            $family = if ($key -match '^gemini-') { 'Gemini' } elseif ($key -match '^3p-') { 'Other' } else { $key }
            $items += [pscustomobject]@{
                key = $key; family = $family; label = "$family $($bucket.window)"
                remainingPercent = $(if ($null -ne $fraction -and $reset -gt $now) { [double]$fraction * 100.0 } else { $null })
                resetsAt = $reset.ToUniversalTime().ToString('o')
            }
        }
    }
    if ($items.Count -eq 0) { throw 'no_quotas' }
    [pscustomobject]@{
        source = 'antigravity-cli'; lastCheckedAt = $now.ToString('o'); lastSuccessAt = $now.ToString('o')
        lastError = ''; errorCode = ''; available = @($items | Where-Object { $null -ne $_.remainingPercent }).Count -gt 0
        items = @($items)
    }
}

function Get-UtpAntigravityCliUsage {
    $path = Resolve-UtpAntigravityCli
    if ([string]::IsNullOrEmpty($path)) { return New-UtpExternalUsageFailure 'antigravity-cli' 'setup_required' 'Install Antigravity CLI and sign in before enabling usage collection.' }
    try {
        $versionResult = Invoke-UtpExternalUsageCommand -FilePath $path -Arguments @('--version') -MaximumBytes 16384
        $match = [regex]::Match($versionResult.Output,'(?m)\b(\d+\.\d+\.\d+)\b')
        if ($versionResult.ExitCode -ne 0 -or -not $match.Success -or [version]$match.Groups[1].Value -lt [version]'1.1.11') {
            return New-UtpExternalUsageFailure 'antigravity-cli' 'setup_required' 'Antigravity CLI 1.1.11 or newer is required for quota-only commands.'
        }
        $result = Invoke-UtpExternalUsageCommand -FilePath $path -Arguments @('-p','/usage','--output-format','json')
        if ($result.ExitCode -ne 0) { return New-UtpExternalUsageFailure 'antigravity-cli' 'provider_error' 'Antigravity CLI could not provide usage. Check its sign-in separately.' }
        ConvertFrom-UtpAntigravityUsageJson -Json $result.Output
    } catch {
        $code = if ($_.Exception.Message -in @('timeout','response_too_large','auth_required','unexpected_model_activity')) { $_.Exception.Message } else { 'unsupported_response' }
        New-UtpExternalUsageFailure 'antigravity-cli' $code 'Antigravity usage is unavailable; no percentage was inferred.'
    }
}

function Update-AntigravityCliUsage {
    # Collector integration; the shared atomic writer owns directory creation.
    $snapshot = Get-UtpAntigravityCliUsage
    Write-OpenCodeGoJsonAtomically -Path $script:AntigravityUsagePath -Value $snapshot -MutexName 'UsageTrayPillAntigravityUsageWrite'
    return [bool]$snapshot.available
}

function Resolve-UtpClaudeUsageCli {
    $packages = Join-Path $env:LOCALAPPDATA 'Packages'
    $roots = @(Join-Path $env:APPDATA 'Claude\claude-code')
    foreach ($package in @(Get-ChildItem -LiteralPath $packages -Directory -Filter 'Claude_*' -ErrorAction SilentlyContinue)) {
        $roots += Join-Path $package.FullName 'LocalCache\Roaming\Claude\claude-code'
    }
    $candidates = @()
    foreach ($root in $roots) {
        foreach ($directory in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
            $version = $null
            if (-not [version]::TryParse($directory.Name,[ref]$version)) { continue }
            $paths = @(Join-Path $directory.FullName 'claude.exe')
            foreach ($build in @(Get-ChildItem -LiteralPath $directory.FullName -Directory -ErrorAction SilentlyContinue)) { $paths += Join-Path $build.FullName 'claude.exe' }
            foreach ($path in $paths) {
                if (Test-Path -LiteralPath $path -PathType Leaf) { $candidates += [pscustomobject]@{Version=$version;Path=$path} }
            }
        }
    }
    $newest = $candidates | Sort-Object Version -Descending | Select-Object -First 1
    if ($null -ne $newest) { return [string]$newest.Path }
    foreach ($command in @(Get-Command claude.exe -All -CommandType Application -ErrorAction SilentlyContinue)) {
        if (Test-Path -LiteralPath $command.Source -PathType Leaf) { return [string]$command.Source }
    }
    return ''
}

function ConvertFrom-UtpClaudeControlUsageJson {
    param([Parameter(Mandatory = $true)][string]$Json)
    if ([System.Text.Encoding]::UTF8.GetByteCount($Json) -gt 1048576) { throw 'response_too_large' }
    $payload = $Json | ConvertFrom-Json -ErrorAction Stop
    if ($payload -isnot [pscustomobject]) { throw 'unsupported_response' }
    if (($null -ne $payload.session.total_cost_usd -and $payload.session.total_cost_usd -ne 0) -or
        ($null -ne $payload.session.model_usage -and @($payload.session.model_usage.PSObject.Properties).Count -gt 0)) { throw 'unexpected_model_activity' }
    if ($null -ne $payload.behaviors) { throw 'unexpected_transcript_activity' }
    if ($payload.rate_limits_available -isnot [bool] -or $null -eq $payload.session.total_cost_usd) { throw 'unsupported_response' }
    if (-not $payload.rate_limits_available) {
        return New-UtpExternalUsageFailure 'claude-code-control' 'unsupported_auth_context' 'This isolated Claude CLI session does not expose plan limits. The account context is not verified.'
    }
    if ($null -eq $payload.rate_limits) { throw 'unsupported_response' }
    $now = [DateTimeOffset]::UtcNow
    $items = @()
    foreach ($key in @('five_hour','seven_day')) {
        $window = $payload.rate_limits.$key
        if ($null -eq $window) { continue }
        $used = $window.utilization
        if ($null -ne $used -and ($used -is [string] -or $used -is [bool] -or
            -not ($used -is [ValueType]) -or [double]::IsNaN([double]$used) -or
            [double]::IsInfinity([double]$used) -or [double]$used -lt 0 -or [double]$used -gt 100)) { throw 'invalid_utilization' }
        $reset = [DateTimeOffset]::MinValue
        if ($null -ne $window.resets_at -and ([string]$window.resets_at -notmatch '(Z|[+-]\d\d:\d\d)$' -or
            -not [DateTimeOffset]::TryParse([string]$window.resets_at,[System.Globalization.CultureInfo]::InvariantCulture,[System.Globalization.DateTimeStyles]::None,[ref]$reset))) { throw 'invalid_reset' }
        $items += [pscustomobject]@{
            key=$key; label=$(if ($key -eq 'five_hour') { '5h' } else { 'weekly' })
            remainingPercent=$(if ($null -ne $used -and ($null -eq $window.resets_at -or $reset -gt $now)) { 100.0 - [double]$used } else { $null })
            resetsAt=$(if($null -ne $window.resets_at){$reset.ToUniversalTime().ToString('o')}else{''})
        }
    }
    if ($items.Count -eq 0) { throw 'no_quotas' }
    [pscustomobject]@{
        source='claude-code-control';lastCheckedAt=$now.ToString('o');lastSuccessAt=$now.ToString('o')
        lastError='';errorCode='';available=@($items | Where-Object { $null -ne $_.remainingPercent }).Count -gt 0;items=@($items)
    }
}

function Get-UtpClaudeControlUsage {
    # Explicit opt-in source, off by default. Verified after sign-in on CLI 2.1.286:
    # quota windows available, zero user messages/model cost, and behaviors=null.
    $path = Resolve-UtpClaudeUsageCli
    if ([string]::IsNullOrEmpty($path)) { return New-UtpExternalUsageFailure 'claude-code-control' 'setup_required' 'A recent Claude Code CLI is required for the experimental usage diagnostic.' }
    try {
        $versionResult = Invoke-UtpExternalUsageCommand -FilePath $path -Arguments @('--version') -MaximumBytes 16384
        $match = [regex]::Match($versionResult.Output,'(?m)\b(\d+\.\d+\.\d+)\b')
        if ($versionResult.ExitCode -ne 0 -or -not $match.Success -or [version]$match.Groups[1].Value -lt [version]'2.1.286') {
            return New-UtpExternalUsageFailure 'claude-code-control' 'setup_required' 'Claude Code 2.1.286 or newer is required for this experimental diagnostic.'
        }
        $result = Invoke-UtpExternalUsageCommand -FilePath $path -Arguments @('-p','--input-format','stream-json','--output-format','stream-json','--verbose','--no-session-persistence','--safe-mode','--setting-sources','','--strict-mcp-config','--mcp-config','{"mcpServers":{}}','--tools','') -ClaudeUsageControl
        ConvertFrom-UtpClaudeControlUsageJson -Json $result.Output
    } catch {
        $code = if ($_.Exception.Message -in @('timeout','response_too_large','auth_required','unexpected_model_activity','unexpected_transcript_activity','interaction_required','initialization_failed','usage_request_failed','missing_usage_response')) { $_.Exception.Message } else { 'usage_response_unavailable' }
        New-UtpExternalUsageFailure 'claude-code-control' $code 'The experimental Claude usage diagnostic did not provide verified plan limits.'
    }
}

function Update-ClaudeControlUsage {
    $snapshot=Get-UtpClaudeControlUsage
    Write-OpenCodeGoJsonAtomically -Path $script:ClaudeControlUsagePath -Value $snapshot -MutexName 'UsageTrayPillClaudeControlUsageWrite'
    return [bool]$snapshot.available
}
