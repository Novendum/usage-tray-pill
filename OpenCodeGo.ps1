$script:OpenCodeGoSnapshotMaxAgeHours = 6

function New-OpenCodeGoException {
    param(
        [Parameter(Mandatory = $true)] [string]$Code,
        [Parameter(Mandatory = $true)] [string]$Message
    )

    $exception = New-Object System.InvalidOperationException $Message
    $exception.Data["OpenCodeGoCode"] = $Code
    return $exception
}

function Get-OpenCodeGoExceptionCode {
    param([object]$ErrorRecord)

    if ($null -ne $ErrorRecord -and
        $null -ne $ErrorRecord.Exception -and
        $ErrorRecord.Exception.Data.Contains("OpenCodeGoCode")) {
        return [string]$ErrorRecord.Exception.Data["OpenCodeGoCode"]
    }
    return "network_error"
}

function ConvertTo-OpenCodeGoApiKey {
    param([Parameter(Mandatory = $true)] [string]$Value)

    $candidate = $Value.Trim()
    if ($Value -match '[\r\n]' -or $candidate -notmatch '^[\x21-\x7E]+$' -or $candidate.Length -gt 16384 -or $candidate.Contains(';')) {
        throw (New-OpenCodeGoException -Code "invalid_auth" -Message "Enter only the OpenCode Go API key, without a Bearer prefix or cookie header.")
    }
    return $candidate
}

function Protect-OpenCodeGoSecret {
    param([Parameter(Mandatory = $true)] [string]$PlainText)

    Add-Type -AssemblyName System.Security
    $plainBytes = [System.Text.Encoding]::UTF8.GetBytes($PlainText)
    $entropy = [System.Text.Encoding]::UTF8.GetBytes("UsageTrayPill/OpenCodeGo/v1")
    try {
        $protectedBytes = [System.Security.Cryptography.ProtectedData]::Protect(
            $plainBytes,
            $entropy,
            [System.Security.Cryptography.DataProtectionScope]::CurrentUser
        )
        return [Convert]::ToBase64String($protectedBytes)
    }
    finally {
        [Array]::Clear($plainBytes, 0, $plainBytes.Length)
        [Array]::Clear($entropy, 0, $entropy.Length)
    }
}

function Unprotect-OpenCodeGoSecret {
    param([Parameter(Mandatory = $true)] [string]$ProtectedText)

    Add-Type -AssemblyName System.Security
    try {
        $protectedBytes = [Convert]::FromBase64String($ProtectedText)
        $entropy = [System.Text.Encoding]::UTF8.GetBytes("UsageTrayPill/OpenCodeGo/v1")
        $plainBytes = [System.Security.Cryptography.ProtectedData]::Unprotect(
            $protectedBytes,
            $entropy,
            [System.Security.Cryptography.DataProtectionScope]::CurrentUser
        )
        try {
            return [System.Text.Encoding]::UTF8.GetString($plainBytes)
        }
        finally {
            [Array]::Clear($plainBytes, 0, $plainBytes.Length)
        }
    }
    catch {
        throw (New-OpenCodeGoException -Code "credential_unreadable" -Message "The stored OpenCode Go session could not be decrypted.")
    }
    finally {
        if ($null -ne $protectedBytes) { [Array]::Clear($protectedBytes, 0, $protectedBytes.Length) }
        if ($null -ne $entropy) { [Array]::Clear($entropy, 0, $entropy.Length) }
    }
}

function Write-OpenCodeGoJsonAtomically {
    param(
        [Parameter(Mandatory = $true)] [string]$Path,
        [Parameter(Mandatory = $true)] [object]$Value,
        [Parameter(Mandatory = $true)] [string]$MutexName
    )

    Ensure-DataDirectory
    $json = $Value | ConvertTo-Json -Depth 8
    $tempPath = "$Path.tmp-$PID"
    $backupPath = "$Path.replace-backup-$PID"
    $encoding = New-Object System.Text.UTF8Encoding($false)
    $mutex = New-Object System.Threading.Mutex($false, $MutexName)
    $hasLock = $false
    try {
        try { $hasLock = $mutex.WaitOne([TimeSpan]::FromSeconds(15)) }
        catch [System.Threading.AbandonedMutexException] { $hasLock = $true }
        if (-not $hasLock) { throw "Timed out while locking OpenCode Go data." }

        [System.IO.File]::WriteAllText($tempPath, $json, $encoding)
        if (Test-Path -LiteralPath $Path) {
            [System.IO.File]::Replace($tempPath, $Path, $backupPath, $true)
            Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
        }
        else {
            Move-Item -LiteralPath $tempPath -Destination $Path
        }
    }
    finally {
        Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
        if ($hasLock) {
            try { $mutex.ReleaseMutex() } catch {
            }
        }
        $mutex.Dispose()
    }
}

function Save-OpenCodeGoCredentials {
    param([Parameter(Mandatory = $true)] [string]$ApiKey)
    $normalizedApiKey = ConvertTo-OpenCodeGoApiKey $ApiKey
    $credential = [pscustomobject]@{
        version = 2
        protectedApiKey = Protect-OpenCodeGoSecret $normalizedApiKey
        savedAt = Format-DateForStorage (Get-Date)
    }
    Write-OpenCodeGoJsonAtomically -Path $script:OpenCodeGoCredentialPath -Value $credential -MutexName "UsageTrayPillOpenCodeGoCredentialsWrite"
}

function ConvertFrom-OpenCodeGoStoredCredential {
    param([Parameter(Mandatory = $true)] [object]$Stored)
    if ($Stored.version -ne 2) {
        throw (New-OpenCodeGoException -Code "api_key_required" -Message "OpenCode Go now requires an API key. Set up OpenCode Go again; your previous session has been preserved.")
    }
    return [pscustomobject]@{
        apiKey = ConvertTo-OpenCodeGoApiKey (Unprotect-OpenCodeGoSecret ([string]$Stored.protectedApiKey))
        source = "dpapi"
    }
}

function Get-OpenCodeGoCredentials {
    $environmentApiKey = [string]$env:OPENCODE_GO_API_KEY
    if (-not [string]::IsNullOrWhiteSpace($environmentApiKey)) {
        return [pscustomobject]@{
            apiKey = ConvertTo-OpenCodeGoApiKey $environmentApiKey
            source = "environment"
        }
    }

    if (-not (Test-Path -LiteralPath $script:OpenCodeGoCredentialPath)) {
        return $null
    }

    try {
        $stored = Get-Content -LiteralPath $script:OpenCodeGoCredentialPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        return ConvertFrom-OpenCodeGoStoredCredential $stored
    }
    catch {
        if ((Get-OpenCodeGoExceptionCode $_) -ne "network_error") { throw }
        throw (New-OpenCodeGoException -Code "credential_unreadable" -Message "The stored OpenCode Go session is corrupted.")
    }
}

function ConvertFrom-OpenCodeGoUsageResponse {
    param([Parameter(Mandatory = $true)] [object]$Response)
    if ($Response -is [string]) {
        try { $Response = $Response | ConvertFrom-Json -ErrorAction Stop }
        catch { throw (New-OpenCodeGoException -Code 'parse_error' -Message 'OpenCode Go returned invalid JSON.') }
    }
    $items = @()
    foreach ($definition in @(
        @{ Name = 'rolling'; Key = 'five_hour'; Label = '5h' },
        @{ Name = 'weekly'; Key = 'seven_day'; Label = 'weekly' },
        @{ Name = 'monthly'; Key = 'monthly'; Label = 'monthly' }
    )) {
        $window = $Response.usage.($definition.Name)
        # Require all three windows; a partial response must not imply missing limits are available.
        $used = 0.0
        $reset = [DateTimeOffset]::MinValue
        if ($null -eq $window -or $null -eq $window.percent -or $window.percent -is [bool] -or
            -not [double]::TryParse([string]$window.percent, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$used) -or
            [double]::IsNaN($used) -or [double]::IsInfinity($used) -or $used -lt 0 -or $used -gt 100 -or
            $window.status -notin @('ok', 'rate-limited') -or
            -not [DateTimeOffset]::TryParse([string]$window.resetsAt, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$reset)) {
            throw (New-OpenCodeGoException -Code 'parse_error' -Message 'OpenCode Go returned an incomplete or invalid quota window.')
        }
        $items += [pscustomobject]@{
            key = $definition.Key
            label = $definition.Label
            usedPercent = $used
            remainingPercent = 100.0 - $used
            status = [string]$window.status
            resetsAt = $reset.ToString('o')
        }
    }
    return @($items)
}

function ConvertTo-OpenCodeGoRetryAfterSeconds {
    param([string]$Value, [DateTimeOffset]$Now = [DateTimeOffset]::UtcNow)
    $seconds = 0.0
    if (-not [double]::TryParse($Value, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$seconds)) {
        $date = [DateTimeOffset]::MinValue
        if (-not [DateTimeOffset]::TryParse($Value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$date)) { return 0 }
        $seconds = ($date - $Now).TotalSeconds
    }
    if ([double]::IsNaN($seconds) -or [double]::IsInfinity($seconds)) { return 0 }
    return [int][Math]::Ceiling([Math]::Min(86400, [Math]::Max(0, $seconds)))
}

function New-OpenCodeGoHttpException {
    param([int]$StatusCode, [string]$RetryAfter = '')
    $code = 'server_error'
    $message = 'OpenCode Go returned an unexpected response.'
    switch ($StatusCode) {
        401 { $code = 'auth_expired'; $message = 'The OpenCode Go API key was rejected. Update it in Set up OpenCode Go.' }
        403 { $code = 'subscription_required'; $message = 'This API key does not have an OpenCode Go subscription.' }
        429 { $code = 'rate_limited'; $message = 'OpenCode Go asks you to try again later.' }
    }
    $exception = New-OpenCodeGoException -Code $code -Message $message
    if ($StatusCode -eq 429) { $exception.Data['retryAfterSeconds'] = ConvertTo-OpenCodeGoRetryAfterSeconds $RetryAfter }
    return $exception
}
function Read-OpenCodeGoLimitedUtf8Stream {
    param(
        [Parameter(Mandatory = $true)] [System.IO.Stream]$Stream,
        [int]$MaximumBytes = 4194304
    )

    $memory = New-Object System.IO.MemoryStream
    $buffer = New-Object byte[] 8192
    $totalBytes = 0
    try {
        while (($read = $Stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $totalBytes += $read
            if ($totalBytes -gt $MaximumBytes) {
                throw (New-OpenCodeGoException -Code "response_too_large" -Message "The OpenCode Go usage response is unexpectedly large.")
            }
            $memory.Write($buffer, 0, $read)
        }
        return [System.Text.Encoding]::UTF8.GetString($memory.ToArray())
    }
    finally {
        [Array]::Clear($buffer, 0, $buffer.Length)
        $memory.Dispose()
    }
}

function Read-OpenCodeGoResponseText {
    param(
        [Parameter(Mandatory = $true)] [System.Net.HttpWebResponse]$Response,
        [int]$MaximumBytes = 4194304
    )

    if ($Response.ContentLength -gt $MaximumBytes) {
        throw (New-OpenCodeGoException -Code "response_too_large" -Message "The OpenCode Go usage response is unexpectedly large.")
    }

    $stream = $Response.GetResponseStream()
    try {
        return Read-OpenCodeGoLimitedUtf8Stream -Stream $stream -MaximumBytes $MaximumBytes
    }
    finally {
        $stream.Dispose()
    }
}

function Invoke-OpenCodeGoUsageRequest {
    param([Parameter(Mandatory = $true)] [string]$ApiKey)
    $request = [System.Net.HttpWebRequest]::Create('https://opencode.ai/zen/go/v1/usage')
    $request.Method = 'GET'
    $request.Accept = 'application/json'
    $request.UserAgent = 'UsageTrayPill/1.0'
    $request.AllowAutoRedirect = $false
    $request.Timeout = 12000
    $request.ReadWriteTimeout = 12000
    $request.KeepAlive = $false
    $request.Headers['Authorization'] = 'Bearer ' + (ConvertTo-OpenCodeGoApiKey $ApiKey)
    $response = $null
    $deadline=New-Object UtpRequestDeadline $request,15000
    try {
        $response = [System.Net.HttpWebResponse]$request.GetResponse()
        if ([int]$response.StatusCode -ne 200) {
            throw (New-OpenCodeGoHttpException -StatusCode ([int]$response.StatusCode) -RetryAfter $response.Headers['Retry-After'])
        }
        return Read-OpenCodeGoResponseText -Response $response -MaximumBytes 4194304
    }
    catch [System.Net.WebException] {
        $webResponse = $_.Exception.Response
        if ($null -ne $webResponse) {
            try { $errorToThrow = New-OpenCodeGoHttpException -StatusCode ([int]$webResponse.StatusCode) -RetryAfter $webResponse.Headers['Retry-After'] }
            finally { $webResponse.Dispose() }
            throw $errorToThrow
        }
        throw (New-OpenCodeGoException -Code 'network_error' -Message 'The OpenCode Go usage API is unreachable.')
    }
    finally {
        if ($null -ne $response) { $response.Dispose() }
        $deadline.Dispose()
        $request.Abort()
    }
}
function Write-OpenCodeGoUsageSnapshot {
    param([Parameter(Mandatory = $true)] [object]$Usage)

    Write-OpenCodeGoJsonAtomically -Path $script:OpenCodeGoUsagePath -Value $Usage -MutexName "UsageTrayPillOpenCodeGoUsageWrite"
}

function Read-OpenCodeGoUsageSnapshotRaw {
    if (-not (Test-Path -LiteralPath $script:OpenCodeGoUsagePath)) { return $null }
    try {
        return Get-Content -LiteralPath $script:OpenCodeGoUsagePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch { return $null }
}

function Get-OpenCodeGoUsageSnapshot {
    $usage = Read-OpenCodeGoUsageSnapshotRaw
    if ($null -eq $usage) { return $null }

    $copy = $usage | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $lastSuccess = Get-DateOrNull ([string]$copy.lastSuccessAt)
    if ($null -eq $lastSuccess -or $lastSuccess -gt (Get-Date).AddMinutes(1) -or ((Get-Date) - $lastSuccess).TotalHours -gt $script:OpenCodeGoSnapshotMaxAgeHours) {
        $copy.available = $false
        foreach ($item in @($copy.items)) { $item.remainingPercent = $null }
    }
    if ($null -ne $lastSuccess -and ((Get-Date) - $lastSuccess).TotalMinutes -gt 5) { $copy.stale = $true }
    foreach ($item in @($copy.items)) {
        $reset = Get-DateOrNull ([string]$item.resetsAt)
        if ($null -ne $reset -and $reset -le (Get-Date)) { $item.remainingPercent = $null }
    }
    return $copy
}

function Set-OpenCodeGoFailureSnapshot {
    param(
        [Parameter(Mandatory = $true)] [string]$Code,
        [Parameter(Mandatory = $true)] [string]$Message,
        [int]$RetryAfterSeconds = 0
    )

    $previous = Read-OpenCodeGoUsageSnapshotRaw
    $preserveCodes = @("network_error", "rate_limited", "server_error", "parse_error", "response_too_large")
    $items = @()
    $lastSuccessAt = if ($null -ne $previous) { [string]$previous.lastSuccessAt } else { "" }
    if ($Code -in $preserveCodes -and $null -ne $previous) {
        $lastSuccess = Get-DateOrNull ([string]$previous.lastSuccessAt)
        if ($null -ne $lastSuccess -and $lastSuccess -le (Get-Date).AddMinutes(1) -and ((Get-Date) - $lastSuccess).TotalHours -le $script:OpenCodeGoSnapshotMaxAgeHours) {
            $items = @(As-Array $previous.items)
            $lastSuccessAt = [string]$previous.lastSuccessAt
        }
    }

    Write-OpenCodeGoUsageSnapshot ([pscustomobject]@{
        version = 1
        source = "opencode-go-api"
        available = ($items.Count -gt 0)
        stale = ($items.Count -gt 0)
        lastCheckedAt = Format-DateForStorage (Get-Date)
        lastSuccessAt = $lastSuccessAt
        lastError = $Code
        lastErrorMessage = $Message
        retryAfterSeconds = [Math]::Min(86400, [Math]::Max(0, $RetryAfterSeconds))
        items = @($items)
    })
}

function Update-OpenCodeGoUsage {
    if ($script:OpenCodeGoUsagePollInProgress) { return $false }
    if ($null -eq $script:State -or -not [bool]$script:State.settings.openCodeGoEnabled) { return $false }

    $pollMutex = New-Object System.Threading.Mutex($false, "UsageTrayPillOpenCodeGoPoll")
    $hasPollLock = $false
    $script:OpenCodeGoUsagePollInProgress = $true
    try {
        try { $hasPollLock = $pollMutex.WaitOne(0) }
        catch [System.Threading.AbandonedMutexException] { $hasPollLock = $true }
        if (-not $hasPollLock) { return $false }

        $credentials = Get-OpenCodeGoCredentials
        if ($null -eq $credentials) {
            throw (New-OpenCodeGoException -Code "setup_required" -Message "OpenCode Go has not been set up.")
        }

        $response = Invoke-OpenCodeGoUsageRequest -ApiKey $credentials.apiKey
        $items = ConvertFrom-OpenCodeGoUsageResponse $response
        $now = Format-DateForStorage (Get-Date)
        Write-OpenCodeGoUsageSnapshot ([pscustomobject]@{
            version = 1
            source = "opencode-go-api"
            available = $true
            stale = $false
            lastCheckedAt = $now
            lastSuccessAt = $now
            lastError = ""
            lastErrorMessage = ""
            retryAfterSeconds = 0
            items = @($items)
        })
        return $true
    }
    catch {
        $code = Get-OpenCodeGoExceptionCode $_
        $message = if ($null -ne $_.Exception -and -not [string]::IsNullOrWhiteSpace([string]$_.Exception.Message)) {
            [string]$_.Exception.Message
        } else {
            "OpenCode Go could not be refreshed."
        }
        $retryAfterSeconds = 0
        if ($_.Exception.Data.Contains('retryAfterSeconds')) { $retryAfterSeconds = [int]$_.Exception.Data['retryAfterSeconds'] }
        Set-OpenCodeGoFailureSnapshot -Code $code -Message $message -RetryAfterSeconds $retryAfterSeconds
        return $false
    }
    finally {
        $credentials = $null
        $script:OpenCodeGoUsagePollInProgress = $false
        if ($hasPollLock) {
            try { $pollMutex.ReleaseMutex() } catch {
            }
        }
        $pollMutex.Dispose()
    }
}

function Get-OpenCodeGoStatusText {
    $usage = Get-OpenCodeGoUsageSnapshot
    if ($null -eq $usage) { return "not configured" }
    if ([bool]$usage.stale -and [bool]$usage.available) { return "cache" }
    if ([bool]$usage.available) { return "usage API" }
    switch ([string]$usage.lastError) {
        "setup_required" { return "set up" }
        "api_key_required" { return "API key required" }
        "auth_expired" { return "update API key" }
        "subscription_required" { return "Go subscription required" }
        "rate_limited" { return "try again later" }
        default { return "error" }
    }
}

function Get-OpenCodeAppPath {
    try {
        $runningPath = Get-Process -Name "OpenCode" -ErrorAction SilentlyContinue |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_.Path) } |
            Select-Object -First 1 -ExpandProperty Path
        if (-not [string]::IsNullOrWhiteSpace([string]$runningPath)) { return $runningPath }
    }
    catch {
    }

    foreach ($candidate in @(
        (Join-Path $env:LOCALAPPDATA "opencode\OpenCode.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\opencode\OpenCode.exe")
    )) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    return $null
}

function Show-OpenCodeGoSetupDialog {
    $existing = $null
    try { $existing = Get-OpenCodeGoCredentials } catch {
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Set up OpenCode Go"
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ClientSize = New-Object System.Drawing.Size 570, 240

    $intro = New-Object System.Windows.Forms.Label
    $intro.Location = New-Object System.Drawing.Point 18, 16
    $intro.Size = New-Object System.Drawing.Size 530, 54
    $intro.Text = "Reads Go limits from the OpenCode usage API. Your key is encrypted for your Windows account. It can also authorize model use, so keep it private."
    $form.Controls.Add($intro)

    $authLabel = New-Object System.Windows.Forms.Label
    $authLabel.Location = New-Object System.Drawing.Point 18, 78
    $authLabel.Size = New-Object System.Drawing.Size 250, 20
    $authLabel.Text = "OpenCode Go API key"
    $form.Controls.Add($authLabel)

    $authBox = New-Object System.Windows.Forms.TextBox
    $authBox.Location = New-Object System.Drawing.Point 18, 100
    $authBox.Size = New-Object System.Drawing.Size 530, 24
    $authBox.UseSystemPasswordChar = $true
    $form.Controls.Add($authBox)

    $hint = New-Object System.Windows.Forms.Label
    $hint.Location = New-Object System.Drawing.Point 18, 134
    $hint.Size = New-Object System.Drawing.Size 530, 34
    $hint.Text = if ($null -ne $existing) {
        "Leave blank to keep your key. OPENCODE_GO_API_KEY takes precedence over a saved key."
    } else {
        "Copy your Go API key from the OpenCode console. Your previous session stays saved until you replace it."
    }
    $form.Controls.Add($hint)

    $dashboardButton = New-Object System.Windows.Forms.Button
    $dashboardButton.Location = New-Object System.Drawing.Point 18, 192
    $dashboardButton.Size = New-Object System.Drawing.Size 125, 30
    $dashboardButton.Text = "Open console"
    $dashboardButton.Add_Click({
        Start-Process 'https://opencode.ai/console'
    })
    $form.Controls.Add($dashboardButton)

    $removeButton = New-Object System.Windows.Forms.Button
    $removeButton.Location = New-Object System.Drawing.Point 153, 192
    $removeButton.Size = New-Object System.Drawing.Size 120, 30
    $removeButton.Text = "Disable"
    $removeButton.Enabled = ($null -ne $existing -or [bool]$script:State.settings.openCodeGoEnabled)
    $removeButton.Add_Click({
        Stop-OpenCodeGoUsageRefresh
        $script:State.settings.openCodeGoEnabled = $false
        if ([string]$script:State.settings.taskbarBadgeDefaultSource -eq "opencodego") {
            $script:State.settings.taskbarBadgeDefaultSource = "codex"
        }
        Save-State
        $form.DialogResult = [System.Windows.Forms.DialogResult]::Abort
        $form.Close()
    })
    $form.Controls.Add($removeButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Location = New-Object System.Drawing.Point 374, 192
    $cancelButton.Size = New-Object System.Drawing.Size 80, 30
    $cancelButton.Text = "Cancel"
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($cancelButton)

    $saveButton = New-Object System.Windows.Forms.Button
    $saveButton.Location = New-Object System.Drawing.Point 464, 192
    $saveButton.Size = New-Object System.Drawing.Size 84, 30
    $saveButton.Text = "Save"
    $saveButton.Add_Click({
        try {
            $apiKey = $authBox.Text
            if ([string]::IsNullOrWhiteSpace($apiKey)) {
                if ($null -eq $existing) {
                    throw (New-OpenCodeGoException -Code "api_key_required" -Message "Enter your OpenCode Go API key.")
                }
            } else {
                Save-OpenCodeGoCredentials -ApiKey $apiKey
            }
            $script:State.settings.openCodeGoEnabled = $true
            Save-State
            $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $form.Close()
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show(
                $_.Exception.Message,
                $script:AppName,
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null
        }
    })
    $form.Controls.Add($saveButton)
    $form.AcceptButton = $saveButton
    $form.CancelButton = $cancelButton

    try { $result = $form.ShowDialog() }
    finally { $authBox.Clear(); $existing = $null; $form.Dispose() }
    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        Start-OpenCodeGoUsageRefresh
        Refresh-Tray
        Refresh-TaskbarBadge
        if ($null -ne $script:RefreshMainWindow) { & $script:RefreshMainWindow }
        return $true
    }
    if ($result -eq [System.Windows.Forms.DialogResult]::Abort) {
        Refresh-Tray
        Refresh-TaskbarBadge
        if ($null -ne $script:RefreshMainWindow) { & $script:RefreshMainWindow }
    }
    return $false
}
