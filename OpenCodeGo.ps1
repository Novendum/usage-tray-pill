$script:OpenCodeGoDashboardOrigin = "https://opencode.ai"
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

function ConvertTo-OpenCodeGoWorkspaceId {
    param([Parameter(Mandatory = $true)] [string]$Value)

    $candidate = $Value.Trim()
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        throw (New-OpenCodeGoException -Code "invalid_workspace" -Message "Enter an OpenCode Go workspace ID or dashboard URL.")
    }

    $urlMatch = [regex]::Match($candidate, '(?i)(?:https?://opencode\.ai)?/workspace/(?<id>wrk_[A-Za-z0-9_-]+)(?:/go)?(?:[/?#].*)?$')
    if ($urlMatch.Success) {
        $candidate = $urlMatch.Groups["id"].Value
    }

    if ($candidate -notmatch '^wrk_[A-Za-z0-9_-]+$') {
        throw (New-OpenCodeGoException -Code "invalid_workspace" -Message "The workspace ID must start with wrk_.")
    }
    return $candidate
}

function ConvertTo-OpenCodeGoAuthCookie {
    param([Parameter(Mandatory = $true)] [string]$Value)

    if ($Value -match '[\r\n]') {
        throw (New-OpenCodeGoException -Code "invalid_auth" -Message "The auth cookie contains invalid characters.")
    }

    $candidate = $Value.Trim()
    if ($candidate -match '(?i)(?:^|;\s*)auth=(?<value>[^;]+)') {
        $candidate = $Matches["value"].Trim()
    }
    elseif ($candidate -match '^[A-Za-z][A-Za-z0-9_-]*=') {
        throw (New-OpenCodeGoException -Code "invalid_auth" -Message "Use the value of the cookie named auth.")
    }

    if ([string]::IsNullOrWhiteSpace($candidate) -or $candidate.Length -gt 16384 -or $candidate.Contains(";")) {
        throw (New-OpenCodeGoException -Code "invalid_auth" -Message "The OpenCode Go auth cookie is invalid.")
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
    param(
        [Parameter(Mandatory = $true)] [string]$WorkspaceId,
        [Parameter(Mandatory = $true)] [string]$AuthCookie
    )

    $normalizedWorkspaceId = ConvertTo-OpenCodeGoWorkspaceId $WorkspaceId
    $normalizedAuthCookie = ConvertTo-OpenCodeGoAuthCookie $AuthCookie
    $credential = [pscustomobject]@{
        version = 1
        workspaceId = $normalizedWorkspaceId
        protectedAuthCookie = Protect-OpenCodeGoSecret $normalizedAuthCookie
        savedAt = Format-DateForStorage (Get-Date)
    }
    Write-OpenCodeGoJsonAtomically -Path $script:OpenCodeGoCredentialPath -Value $credential -MutexName "UsageTrayPillOpenCodeGoCredentialsWrite"
}

function Remove-OpenCodeGoCredentials {
    Remove-Item -LiteralPath $script:OpenCodeGoCredentialPath -Force -ErrorAction SilentlyContinue
}

function Get-OpenCodeGoCredentials {
    $environmentWorkspace = [string]$env:OPENCODE_GO_WORKSPACE_ID
    $environmentAuth = [string]$env:OPENCODE_GO_AUTH_COOKIE
    if (-not [string]::IsNullOrWhiteSpace($environmentWorkspace) -or -not [string]::IsNullOrWhiteSpace($environmentAuth)) {
        if ([string]::IsNullOrWhiteSpace($environmentWorkspace) -or [string]::IsNullOrWhiteSpace($environmentAuth)) {
            throw (New-OpenCodeGoException -Code "incomplete_environment" -Message "Both OpenCode Go environment variables are required.")
        }
        return [pscustomobject]@{
            workspaceId = ConvertTo-OpenCodeGoWorkspaceId $environmentWorkspace
            authCookie = ConvertTo-OpenCodeGoAuthCookie $environmentAuth
            source = "environment"
        }
    }

    if (-not (Test-Path -LiteralPath $script:OpenCodeGoCredentialPath)) {
        return $null
    }

    try {
        $stored = Get-Content -LiteralPath $script:OpenCodeGoCredentialPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        return [pscustomobject]@{
            workspaceId = ConvertTo-OpenCodeGoWorkspaceId ([string]$stored.workspaceId)
            authCookie = ConvertTo-OpenCodeGoAuthCookie (Unprotect-OpenCodeGoSecret ([string]$stored.protectedAuthCookie))
            source = "dpapi"
        }
    }
    catch {
        if ((Get-OpenCodeGoExceptionCode $_) -ne "network_error") { throw }
        throw (New-OpenCodeGoException -Code "credential_unreadable" -Message "The stored OpenCode Go session is corrupted.")
    }
}

function Get-OpenCodeGoDashboardUrl {
    param([string]$WorkspaceId)

    if ([string]::IsNullOrWhiteSpace($WorkspaceId)) {
        return $script:OpenCodeGoDashboardOrigin
    }
    $normalizedWorkspaceId = ConvertTo-OpenCodeGoWorkspaceId $WorkspaceId
    return "$($script:OpenCodeGoDashboardOrigin)/workspace/$normalizedWorkspaceId/go"
}

function Get-OpenCodeGoObjectText {
    param(
        [Parameter(Mandatory = $true)] [string]$Text,
        [Parameter(Mandatory = $true)] [string]$Key
    )

    $escapedKey = [regex]::Escape($Key)
    $keyMatches = [regex]::Matches($Text, "(?is)(?:`"|')?$escapedKey(?:`"|')?\s*:")
    foreach ($match in $keyMatches) {
        $searchStart = $match.Index + $match.Length
        $objectStart = $Text.IndexOf("{", $searchStart)
        if ($objectStart -lt 0 -or ($objectStart - $searchStart) -gt 200) { continue }

        $depth = 0
        for ($index = $objectStart; $index -lt $Text.Length; $index++) {
            if ($Text[$index] -eq "{") { $depth++ }
            elseif ($Text[$index] -eq "}") {
                $depth--
                if ($depth -eq 0) {
                    $candidate = $Text.Substring($objectStart, ($index - $objectStart + 1))
                    if ($candidate -match '(?i)usagePercent') { return $candidate }
                    break
                }
            }
            if (($index - $objectStart) -gt 4096) { break }
        }
    }
    return $null
}

function ConvertFrom-OpenCodeGoDashboardHtml {
    param([Parameter(Mandatory = $true)] [string]$Html)

    if ([string]::IsNullOrWhiteSpace($Html)) {
        throw (New-OpenCodeGoException -Code "parse_error" -Message "OpenCode Go returned an empty dashboard.")
    }

    $normalized = [System.Net.WebUtility]::HtmlDecode($Html)
    $normalized = [regex]::Replace($normalized, '\\+u0022', '"', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $normalized = [regex]::Replace($normalized, '\\+"', '"')

    $definitions = @(
        [pscustomobject]@{ Key = "rollingUsage"; LimitKey = "five_hour"; Label = "5h" },
        [pscustomobject]@{ Key = "weeklyUsage"; LimitKey = "seven_day"; Label = "weekly" },
        [pscustomobject]@{ Key = "monthlyUsage"; LimitKey = "monthly"; Label = "monthly" }
    )
    $items = @()
    foreach ($definition in $definitions) {
        $objectText = Get-OpenCodeGoObjectText -Text $normalized -Key $definition.Key
        if ([string]::IsNullOrWhiteSpace($objectText)) { continue }

        $usageMatch = [regex]::Match($objectText, '(?is)(?:"|''|\\")?usagePercent(?:"|''|\\")?\s*:\s*(?<value>-?\d+(?:\.\d+)?)')
        $resetMatch = [regex]::Match($objectText, '(?is)(?:"|''|\\")?resetInSec(?:"|''|\\")?\s*:\s*(?<value>\d+(?:\.\d+)?)')
        if (-not $usageMatch.Success) { continue }

        $usagePercent = [double]::Parse($usageMatch.Groups["value"].Value, [System.Globalization.CultureInfo]::InvariantCulture)
        $usagePercent = [Math]::Min(100.0, [Math]::Max(0.0, $usagePercent))
        $remainingPercent = [int][Math]::Round(100.0 - $usagePercent, 0, [MidpointRounding]::AwayFromZero)
        $resetsAt = ""
        if ($resetMatch.Success) {
            $resetSeconds = [double]::Parse($resetMatch.Groups["value"].Value, [System.Globalization.CultureInfo]::InvariantCulture)
            $resetsAt = Format-DateForStorage ((Get-Date).AddSeconds([Math]::Max(0, $resetSeconds)))
        }

        $items += [pscustomobject]@{
            key = $definition.LimitKey
            label = $definition.Label
            usedPercent = $usagePercent
            remainingPercent = $remainingPercent
            resetsAt = $resetsAt
        }
    }

    if ($items.Count -eq 0) {
        throw (New-OpenCodeGoException -Code "parse_error" -Message "The OpenCode Go quotas could not be recognized in the dashboard.")
    }
    return @($items)
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
                throw (New-OpenCodeGoException -Code "response_too_large" -Message "The OpenCode Go dashboard is unexpectedly large.")
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
        throw (New-OpenCodeGoException -Code "response_too_large" -Message "The OpenCode Go dashboard is unexpectedly large.")
    }

    $stream = $Response.GetResponseStream()
    try {
        return Read-OpenCodeGoLimitedUtf8Stream -Stream $stream -MaximumBytes $MaximumBytes
    }
    finally {
        $stream.Dispose()
    }
}

function Invoke-OpenCodeGoDashboardRequest {
    param(
        [Parameter(Mandatory = $true)] [string]$WorkspaceId,
        [Parameter(Mandatory = $true)] [string]$AuthCookie
    )

    $url = Get-OpenCodeGoDashboardUrl $WorkspaceId
    $request = [System.Net.HttpWebRequest]::Create($url)
    $request.Method = "GET"
    $request.Accept = "text/html,application/xhtml+xml"
    $request.UserAgent = "UsageTrayPill/1.0"
    $request.AllowAutoRedirect = $false
    $request.Timeout = 12000
    $request.ReadWriteTimeout = 12000
    $request.KeepAlive = $false
    $request.CookieContainer = New-Object System.Net.CookieContainer
    $cookie = New-Object System.Net.Cookie("auth", (ConvertTo-OpenCodeGoAuthCookie $AuthCookie), "/", "opencode.ai")
    $cookie.Secure = $true
    $request.CookieContainer.Add($cookie)

    $response = $null
    try {
        $response = [System.Net.HttpWebResponse]$request.GetResponse()
        $statusCode = [int]$response.StatusCode
        if ($statusCode -ge 300 -and $statusCode -lt 400) {
            throw (New-OpenCodeGoException -Code "auth_expired" -Message "The OpenCode Go session has expired.")
        }
        if ($statusCode -ne 200) {
            throw (New-OpenCodeGoException -Code "server_error" -Message "OpenCode Go returned an unexpected status.")
        }
        if ($response.ContentLength -gt 4194304) {
            throw (New-OpenCodeGoException -Code "response_too_large" -Message "The OpenCode Go dashboard is unexpectedly large.")
        }

        return Read-OpenCodeGoResponseText -Response $response -MaximumBytes 4194304
    }
    catch [System.Net.WebException] {
        $webResponse = $_.Exception.Response
        if ($null -ne $webResponse) {
            $statusCode = [int]$webResponse.StatusCode
            $webResponse.Dispose()
            if ($statusCode -in @(401, 403)) {
                throw (New-OpenCodeGoException -Code "auth_expired" -Message "The OpenCode Go session has expired.")
            }
            if ($statusCode -eq 429) {
                throw (New-OpenCodeGoException -Code "rate_limited" -Message "OpenCode Go asks you to try again later.")
            }
            if ($statusCode -ge 500) {
                throw (New-OpenCodeGoException -Code "server_error" -Message "OpenCode Go is temporarily unavailable.")
            }
        }
        throw (New-OpenCodeGoException -Code "network_error" -Message "The OpenCode Go dashboard is unreachable.")
    }
    finally {
        if ($null -ne $response) { $response.Dispose() }
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
    if ($null -eq $lastSuccess -or ((Get-Date) - $lastSuccess).TotalHours -gt $script:OpenCodeGoSnapshotMaxAgeHours) {
        $copy.available = $false
        foreach ($item in @($copy.items)) { $item.remainingPercent = $null }
    }
    return $copy
}

function Set-OpenCodeGoFailureSnapshot {
    param(
        [Parameter(Mandatory = $true)] [string]$Code,
        [Parameter(Mandatory = $true)] [string]$Message
    )

    $previous = Read-OpenCodeGoUsageSnapshotRaw
    $preserveCodes = @("network_error", "rate_limited", "server_error", "parse_error", "response_too_large")
    $items = @()
    $lastSuccessAt = ""
    if ($Code -in $preserveCodes -and $null -ne $previous) {
        $lastSuccess = Get-DateOrNull ([string]$previous.lastSuccessAt)
        if ($null -ne $lastSuccess -and ((Get-Date) - $lastSuccess).TotalHours -le $script:OpenCodeGoSnapshotMaxAgeHours) {
            $items = @(As-Array $previous.items)
            $lastSuccessAt = [string]$previous.lastSuccessAt
        }
    }

    Write-OpenCodeGoUsageSnapshot ([pscustomobject]@{
        version = 1
        source = "opencode-go-dashboard"
        available = ($items.Count -gt 0)
        stale = ($items.Count -gt 0)
        lastCheckedAt = Format-DateForStorage (Get-Date)
        lastSuccessAt = $lastSuccessAt
        lastError = $Code
        lastErrorMessage = $Message
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

        $html = Invoke-OpenCodeGoDashboardRequest -WorkspaceId $credentials.workspaceId -AuthCookie $credentials.authCookie
        $items = ConvertFrom-OpenCodeGoDashboardHtml $html
        $now = Format-DateForStorage (Get-Date)
        Write-OpenCodeGoUsageSnapshot ([pscustomobject]@{
            version = 1
            source = "opencode-go-dashboard"
            available = $true
            stale = $false
            lastCheckedAt = $now
            lastSuccessAt = $now
            lastError = ""
            lastErrorMessage = ""
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
        Set-OpenCodeGoFailureSnapshot -Code $code -Message $message
        return $false
    }
    finally {
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
    if ([bool]$usage.available) { return "dashboard" }
    switch ([string]$usage.lastError) {
        "setup_required" { return "set up" }
        "auth_expired" { return "session expired" }
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
    $form.ClientSize = New-Object System.Drawing.Size 570, 297

    $intro = New-Object System.Windows.Forms.Label
    $intro.Location = New-Object System.Drawing.Point 18, 16
    $intro.Size = New-Object System.Drawing.Size 530, 54
    $intro.Text = "Experimental: reads usage from the OpenCode Go dashboard. This format may change. The session is encrypted for your Windows account only."
    $form.Controls.Add($intro)

    $workspaceLabel = New-Object System.Windows.Forms.Label
    $workspaceLabel.Location = New-Object System.Drawing.Point 18, 84
    $workspaceLabel.Size = New-Object System.Drawing.Size 150, 20
    $workspaceLabel.Text = "Workspace ID or URL"
    $form.Controls.Add($workspaceLabel)

    $workspaceBox = New-Object System.Windows.Forms.TextBox
    $workspaceBox.Location = New-Object System.Drawing.Point 18, 106
    $workspaceBox.Size = New-Object System.Drawing.Size 530, 24
    if ($null -ne $existing) { $workspaceBox.Text = [string]$existing.workspaceId }
    $form.Controls.Add($workspaceBox)

    $authLabel = New-Object System.Windows.Forms.Label
    $authLabel.Location = New-Object System.Drawing.Point 18, 142
    $authLabel.Size = New-Object System.Drawing.Size 250, 20
    $authLabel.Text = "Cookie value named auth"
    $form.Controls.Add($authLabel)

    $authBox = New-Object System.Windows.Forms.TextBox
    $authBox.Location = New-Object System.Drawing.Point 18, 164
    $authBox.Size = New-Object System.Drawing.Size 530, 24
    $authBox.UseSystemPasswordChar = $true
    $form.Controls.Add($authBox)

    $hint = New-Object System.Windows.Forms.Label
    $hint.Location = New-Object System.Drawing.Point 18, 193
    $hint.Size = New-Object System.Drawing.Size 530, 34
    $hint.Text = if ($null -ne $existing) {
        "Leave the cookie blank to keep the stored session. Environment variables take precedence."
    } else {
        "Open the dashboard, sign in, and use DevTools > Application > Cookies to copy only the value of auth."
    }
    $form.Controls.Add($hint)

    $dashboardButton = New-Object System.Windows.Forms.Button
    $dashboardButton.Location = New-Object System.Drawing.Point 18, 244
    $dashboardButton.Size = New-Object System.Drawing.Size 125, 30
    $dashboardButton.Text = "Open dashboard"
    $dashboardButton.Add_Click({
        $workspace = $workspaceBox.Text.Trim()
        try { Start-Process (Get-OpenCodeGoDashboardUrl $workspace) }
        catch { Start-Process $script:OpenCodeGoDashboardOrigin }
    })
    $form.Controls.Add($dashboardButton)

    $removeButton = New-Object System.Windows.Forms.Button
    $removeButton.Location = New-Object System.Drawing.Point 153, 244
    $removeButton.Size = New-Object System.Drawing.Size 120, 30
    $removeButton.Text = "Disable"
    $removeButton.Enabled = ($null -ne $existing -or [bool]$script:State.settings.openCodeGoEnabled)
    $removeButton.Add_Click({
        Remove-OpenCodeGoCredentials
        Remove-Item -LiteralPath $script:OpenCodeGoUsagePath -Force -ErrorAction SilentlyContinue
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
    $cancelButton.Location = New-Object System.Drawing.Point 374, 244
    $cancelButton.Size = New-Object System.Drawing.Size 80, 30
    $cancelButton.Text = "Cancel"
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($cancelButton)

    $saveButton = New-Object System.Windows.Forms.Button
    $saveButton.Location = New-Object System.Drawing.Point 464, 244
    $saveButton.Size = New-Object System.Drawing.Size 84, 30
    $saveButton.Text = "Save"
    $saveButton.Add_Click({
        try {
            $workspaceId = ConvertTo-OpenCodeGoWorkspaceId $workspaceBox.Text
            $authCookie = $authBox.Text
            if ([string]::IsNullOrWhiteSpace($authCookie)) {
                if ($null -eq $existing) {
                    throw (New-OpenCodeGoException -Code "invalid_auth" -Message "Enter the auth cookie.")
                }
                if ([string]$existing.source -eq "environment") {
                    $script:State.settings.openCodeGoEnabled = $true
                    Save-State
                    $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
                    $form.Close()
                    return
                }
                $authCookie = [string]$existing.authCookie
            }
            Save-OpenCodeGoCredentials -WorkspaceId $workspaceId -AuthCookie $authCookie
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

    $result = $form.ShowDialog()
    $form.Dispose()
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
