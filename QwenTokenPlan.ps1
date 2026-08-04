$script:QwenDashboardOrigin = "https://home.qwencloud.com"
$script:QwenGatewayOrigin = "https://cs-data.qwencloud.com"
$script:QwenSnapshotMaxAgeHours = 6

function New-QwenException {
    param(
        [Parameter(Mandatory = $true)] [string]$Code,
        [Parameter(Mandatory = $true)] [string]$Message
    )

    $exception = New-Object System.InvalidOperationException $Message
    $exception.Data["QwenCode"] = $Code
    return $exception
}

function Get-QwenExceptionCode {
    param([object]$ErrorRecord)

    if ($null -ne $ErrorRecord -and
        $null -ne $ErrorRecord.Exception -and
        $ErrorRecord.Exception.Data.Contains("QwenCode")) {
        return [string]$ErrorRecord.Exception.Data["QwenCode"]
    }
    return "network_error"
}

function ConvertTo-QwenCookieHeader {
    param([Parameter(Mandatory = $true)] [string]$Value)

    if ($Value -match '[\r\n]') {
        throw (New-QwenException -Code "invalid_cookie" -Message "The Qwen cookie header contains invalid characters.")
    }

    $candidate = $Value.Trim()
    if ($candidate -match '^(?i)Cookie\s*:\s*(?<value>.+)$') {
        $candidate = $Matches["value"].Trim()
    }
    if ([string]::IsNullOrWhiteSpace($candidate) -or $candidate.Length -gt 32768) {
        throw (New-QwenException -Code "invalid_cookie" -Message "The Qwen cookie header is empty or too long.")
    }

    $normalized = @()
    foreach ($segment in $candidate.Split(";")) {
        $part = $segment.Trim()
        if ([string]::IsNullOrWhiteSpace($part)) { continue }

        $separator = $part.IndexOf("=")
        if ($separator -le 0) {
            throw (New-QwenException -Code "invalid_cookie" -Message "Use the complete Cookie request header from QwenCloud.")
        }

        $name = $part.Substring(0, $separator).Trim()
        $cookieValue = $part.Substring($separator + 1).Trim()
        if ($name -notmatch '^[!#$%&''*+\-.^_`|~0-9A-Za-z]+$' -or $cookieValue.Contains(";")) {
            throw (New-QwenException -Code "invalid_cookie" -Message "The Qwen cookie header contains an invalid cookie.")
        }
        $normalized += "$name=$cookieValue"
    }

    if ($normalized.Count -eq 0 -or ($normalized -join "; ") -notmatch '(?i)(?:^|;\s*)login_[A-Za-z0-9_-]+=') {
        throw (New-QwenException -Code "invalid_cookie" -Message "The QwenCloud login cookie is missing. Copy the Cookie request header after signing in.")
    }
    return ($normalized -join "; ")
}

function Protect-QwenSecret {
    param([Parameter(Mandatory = $true)] [string]$PlainText)

    Add-Type -AssemblyName System.Security
    $plainBytes = [System.Text.Encoding]::UTF8.GetBytes($PlainText)
    $entropy = [System.Text.Encoding]::UTF8.GetBytes("UsageTrayPill/QwenTokenPlan/v1")
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

function Unprotect-QwenSecret {
    param([Parameter(Mandatory = $true)] [string]$ProtectedText)

    Add-Type -AssemblyName System.Security
    try {
        $protectedBytes = [Convert]::FromBase64String($ProtectedText)
        $entropy = [System.Text.Encoding]::UTF8.GetBytes("UsageTrayPill/QwenTokenPlan/v1")
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
        throw (New-QwenException -Code "credential_unreadable" -Message "The stored QwenCloud session could not be decrypted.")
    }
    finally {
        if ($null -ne $protectedBytes) { [Array]::Clear($protectedBytes, 0, $protectedBytes.Length) }
        if ($null -ne $entropy) { [Array]::Clear($entropy, 0, $entropy.Length) }
    }
}

function Write-QwenJsonAtomically {
    param(
        [Parameter(Mandatory = $true)] [string]$Path,
        [Parameter(Mandatory = $true)] [object]$Value,
        [Parameter(Mandatory = $true)] [string]$MutexName
    )

    Ensure-DataDirectory
    $json = $Value | ConvertTo-Json -Depth 10
    $tempPath = "$Path.tmp-$PID"
    $backupPath = "$Path.replace-backup-$PID"
    $encoding = New-Object System.Text.UTF8Encoding($false)
    $mutex = New-Object System.Threading.Mutex($false, $MutexName)
    $hasLock = $false
    try {
        try { $hasLock = $mutex.WaitOne([TimeSpan]::FromSeconds(15)) }
        catch [System.Threading.AbandonedMutexException] { $hasLock = $true }
        if (-not $hasLock) { throw "Timed out while locking Qwen data." }

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

function Save-QwenCredentials {
    param([Parameter(Mandatory = $true)] [string]$CookieHeader)

    $normalizedCookieHeader = ConvertTo-QwenCookieHeader $CookieHeader
    $credential = [pscustomobject]@{
        version = 1
        protectedCookieHeader = Protect-QwenSecret $normalizedCookieHeader
        savedAt = Format-DateForStorage (Get-Date)
    }
    Write-QwenJsonAtomically -Path $script:QwenCredentialPath -Value $credential -MutexName "UsageTrayPillQwenCredentialsWrite"
}

function Remove-QwenCredentials {
    Remove-Item -LiteralPath $script:QwenCredentialPath -Force -ErrorAction SilentlyContinue
}

function Get-QwenCredentials {
    $environmentCookie = [string]$env:QWEN_TOKEN_PLAN_COOKIE
    if (-not [string]::IsNullOrWhiteSpace($environmentCookie)) {
        return [pscustomobject]@{
            cookieHeader = ConvertTo-QwenCookieHeader $environmentCookie
            source = "environment"
        }
    }

    if (-not (Test-Path -LiteralPath $script:QwenCredentialPath)) {
        return $null
    }

    try {
        $stored = Get-Content -LiteralPath $script:QwenCredentialPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        return [pscustomobject]@{
            cookieHeader = ConvertTo-QwenCookieHeader (Unprotect-QwenSecret ([string]$stored.protectedCookieHeader))
            source = "dpapi"
        }
    }
    catch {
        if ((Get-QwenExceptionCode $_) -ne "network_error") { throw }
        throw (New-QwenException -Code "credential_unreadable" -Message "The stored QwenCloud session is corrupted.")
    }
}

function New-QwenCookieContainer {
    param([Parameter(Mandatory = $true)] [string]$CookieHeader)

    $normalized = ConvertTo-QwenCookieHeader $CookieHeader
    $container = New-Object System.Net.CookieContainer
    foreach ($origin in @($script:QwenDashboardOrigin, $script:QwenGatewayOrigin)) {
        $uri = [Uri]$origin
        foreach ($part in $normalized.Split(";")) {
            $segment = $part.Trim()
            $separator = $segment.IndexOf("=")
            $name = $segment.Substring(0, $separator).Trim()
            $value = $segment.Substring($separator + 1).Trim()
            $cookie = New-Object System.Net.Cookie($name, $value, "/", $uri.Host)
            $cookie.Secure = $true
            $container.Add($uri, $cookie)
        }
    }
    return $container
}

function Read-QwenLimitedUtf8Stream {
    param(
        [Parameter(Mandatory = $true)] [System.IO.Stream]$Stream,
        [int]$MaximumBytes = 2097152
    )

    $memory = New-Object System.IO.MemoryStream
    $buffer = New-Object byte[] 8192
    $totalBytes = 0
    try {
        while (($read = $Stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $totalBytes += $read
            if ($totalBytes -gt $MaximumBytes) {
                throw (New-QwenException -Code "response_too_large" -Message "QwenCloud returned an unexpectedly large response.")
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

function Read-QwenResponseText {
    param(
        [Parameter(Mandatory = $true)] [System.Net.HttpWebResponse]$Response,
        [int]$MaximumBytes = 2097152
    )

    if ($Response.ContentLength -gt $MaximumBytes) {
        throw (New-QwenException -Code "response_too_large" -Message "QwenCloud returned an unexpectedly large response.")
    }

    $stream = $Response.GetResponseStream()
    try {
        return Read-QwenLimitedUtf8Stream -Stream $stream -MaximumBytes $MaximumBytes
    }
    finally {
        $stream.Dispose()
    }
}

function Invoke-QwenJsonRequest {
    param(
        [Parameter(Mandatory = $true)] [string]$Url,
        [Parameter(Mandatory = $true)] [System.Net.CookieContainer]$CookieContainer,
        [ValidateSet("GET", "POST")] [string]$Method = "GET",
        [string]$FormBody = ""
    )

    $uri = [Uri]$Url
    if ($uri.Scheme -ne "https" -or $uri.Host -notin @("home.qwencloud.com", "cs-data.qwencloud.com")) {
        throw (New-QwenException -Code "invalid_endpoint" -Message "UTP rejected an unknown QwenCloud address.")
    }

    $request = [System.Net.HttpWebRequest]::Create($uri)
    $request.Method = $Method
    $request.Accept = "application/json"
    $request.UserAgent = "UsageTrayPill/1.0"
    $request.AllowAutoRedirect = $false
    $request.Timeout = 12000
    $request.ReadWriteTimeout = 12000
    $request.KeepAlive = $false
    $request.CookieContainer = $CookieContainer
    if ($uri.Host -eq "cs-data.qwencloud.com") {
        $request.Referer = "$($script:QwenDashboardOrigin)/billing/subscription/token-plan-individual"
        $request.Headers["Origin"] = $script:QwenDashboardOrigin
    }

    if ($Method -eq "POST") {
        $request.ContentType = "application/x-www-form-urlencoded; charset=UTF-8"
        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($FormBody)
        $request.ContentLength = $bodyBytes.Length
        $stream = $request.GetRequestStream()
        try { $stream.Write($bodyBytes, 0, $bodyBytes.Length) }
        finally {
            $stream.Dispose()
            [Array]::Clear($bodyBytes, 0, $bodyBytes.Length)
        }
    }

    $response = $null
    try {
        $response = [System.Net.HttpWebResponse]$request.GetResponse()
        $statusCode = [int]$response.StatusCode
        if ($statusCode -ge 300 -and $statusCode -lt 400) {
            throw (New-QwenException -Code "auth_expired" -Message "The QwenCloud session has expired.")
        }
        if ($statusCode -ne 200) {
            throw (New-QwenException -Code "server_error" -Message "QwenCloud returned an unexpected status.")
        }

        $text = Read-QwenResponseText -Response $response
        if ($text -match '(?i)ConsoleNeedLogin|NeedLogin|NotLogin') {
            throw (New-QwenException -Code "auth_expired" -Message "The QwenCloud session has expired.")
        }
        try { return ($text | ConvertFrom-Json -ErrorAction Stop) }
        catch {
            throw (New-QwenException -Code "parse_error" -Message "QwenCloud did not return valid JSON.")
        }
    }
    catch [System.Net.WebException] {
        $webResponse = $_.Exception.Response
        if ($null -ne $webResponse) {
            $statusCode = [int]$webResponse.StatusCode
            $webResponse.Dispose()
            if ($statusCode -in @(401, 403)) {
                throw (New-QwenException -Code "auth_expired" -Message "The QwenCloud session has expired.")
            }
            if ($statusCode -eq 429) {
                throw (New-QwenException -Code "rate_limited" -Message "QwenCloud asks you to try again later.")
            }
            if ($statusCode -ge 500) {
                throw (New-QwenException -Code "server_error" -Message "QwenCloud is temporarily unavailable.")
            }
        }
        throw (New-QwenException -Code "network_error" -Message "QwenCloud is unreachable.")
    }
    finally {
        if ($null -ne $response) { $response.Dispose() }
        $request.Abort()
    }
}

function Get-QwenSecToken {
    param([Parameter(Mandatory = $true)] [System.Net.CookieContainer]$CookieContainer)

    $response = Invoke-QwenJsonRequest -Url "$($script:QwenDashboardOrigin)/tool/user/info.json" -CookieContainer $CookieContainer
    $secToken = [string]$response.data.secToken
    if ([string]::IsNullOrWhiteSpace($secToken) -or $secToken.Length -gt 8192) {
        throw (New-QwenException -Code "auth_expired" -Message "QwenCloud rejected the stored session.")
    }
    return $secToken
}

function ConvertTo-QwenFormValue {
    param([string]$Value)
    return [Uri]::EscapeDataString([string]$Value)
}

function Invoke-QwenGatewayRequest {
    param(
        [Parameter(Mandatory = $true)] [string]$Endpoint,
        [Parameter(Mandatory = $true)] [string]$SecToken,
        [Parameter(Mandatory = $true)] [System.Net.CookieContainer]$CookieContainer
    )

    $allowedEndpoints = @(
        "/tokenplan/personal/api/v2/usage",
        "/tokenplan/personal/api/v2/subscription",
        "/tokenplan/personal/api/v2/quota-config"
    )
    if ($Endpoint -notin $allowedEndpoints) {
        throw (New-QwenException -Code "invalid_endpoint" -Message "UTP rejected an unknown QwenCloud function.")
    }

    $api = "zeldaHttp.apikeyMgr.$Endpoint"
    $params = [ordered]@{
        Api = $api
        Data = [ordered]@{
            cornerstoneParam = [ordered]@{
                domain = "home.qwencloud.com"
                consoleSite = "QWENCLOUD"
                console = "ONE_CONSOLE"
                xsp_lang = "en-US"
                protocol = "V2"
                productCode = "p_efm"
            }
        }
        V = "1.0"
    } | ConvertTo-Json -Depth 8 -Compress

    $product = "sfm_bailian"
    $action = "IntlBroadScopeAspnGateway"
    $query = "product=$(ConvertTo-QwenFormValue $product)&action=$(ConvertTo-QwenFormValue $action)&api=$(ConvertTo-QwenFormValue $api)"
    $form = @(
        "product=$(ConvertTo-QwenFormValue $product)",
        "action=$(ConvertTo-QwenFormValue $action)",
        "sec_token=$(ConvertTo-QwenFormValue $SecToken)",
        "region=$(ConvertTo-QwenFormValue 'ap-southeast-1')",
        "params=$(ConvertTo-QwenFormValue $params)"
    ) -join "&"

    return Invoke-QwenJsonRequest -Url "$($script:QwenGatewayOrigin)/data/api.json?$query" -CookieContainer $CookieContainer -Method "POST" -FormBody $form
}

function Get-QwenGatewayPayload {
    param([Parameter(Mandatory = $true)] [object]$Response)

    if ($Response.PSObject.Properties.Name -contains "per5HourPercentage" -or
        $Response.PSObject.Properties.Name -contains "per1WeekPercentage") {
        return $Response
    }

    $payload = $Response.data
    if ($null -ne $payload) { $payload = $payload.DataV2 }
    if ($null -ne $payload) { $payload = $payload.data }
    if ($null -ne $payload) { $payload = $payload.data }
    if ($null -eq $payload) {
        throw (New-QwenException -Code "parse_error" -Message "The QwenCloud usage payload is missing.")
    }
    return $payload
}

function ConvertTo-QwenFraction {
    param(
        [object]$Value,
        [Parameter(Mandatory = $true)] [string]$Field
    )

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $null }
    $number = 0.0
    if (-not [double]::TryParse(
        [string]$Value,
        [System.Globalization.NumberStyles]::Float,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [ref]$number
    )) {
        throw (New-QwenException -Code "parse_error" -Message "QwenCloud returned an invalid value for $Field.")
    }
    if ($number -lt 0 -or $number -gt 1.000001) {
        throw (New-QwenException -Code "parse_error" -Message "QwenCloud unexpectedly changed the percentage format.")
    }
    return $number
}

function ConvertFrom-QwenEpochMilliseconds {
    param([object]$Value)

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return "" }
    $milliseconds = 0L
    if (-not [long]::TryParse([string]$Value, [ref]$milliseconds) -or $milliseconds -lt 0) {
        throw (New-QwenException -Code "parse_error" -Message "QwenCloud returned an invalid reset time.")
    }
    try {
        return Format-DateForStorage ([DateTimeOffset]::FromUnixTimeMilliseconds($milliseconds).LocalDateTime)
    }
    catch {
        throw (New-QwenException -Code "parse_error" -Message "QwenCloud returned an invalid reset time.")
    }
}

function ConvertFrom-QwenUsageResponse {
    param([Parameter(Mandatory = $true)] [object]$Response)

    if ($Response -is [string]) {
        try { $Response = $Response | ConvertFrom-Json -ErrorAction Stop }
        catch { throw (New-QwenException -Code "parse_error" -Message "QwenCloud did not return valid JSON.") }
    }
    $payload = Get-QwenGatewayPayload $Response

    $definitions = @(
        [pscustomobject]@{ Key = "five_hour"; Label = "5h"; PercentField = "per5HourPercentage"; ResetField = "per5HourResetTime" },
        [pscustomobject]@{ Key = "seven_day"; Label = "weekly"; PercentField = "per1WeekPercentage"; ResetField = "per1WeekResetTime" }
    )
    $items = @()
    foreach ($definition in $definitions) {
        $fraction = ConvertTo-QwenFraction -Value $payload.($definition.PercentField) -Field $definition.PercentField
        if ($null -eq $fraction) { continue }

        $usedPercent = [Math]::Min(100.0, [Math]::Max(0.0, $fraction * 100.0))
        $remainingPercent = [int][Math]::Round(100.0 - $usedPercent, 0, [MidpointRounding]::AwayFromZero)
        $items += [pscustomobject]@{
            key = $definition.Key
            label = $definition.Label
            usedPercent = $usedPercent
            remainingPercent = $remainingPercent
            resetsAt = ConvertFrom-QwenEpochMilliseconds $payload.($definition.ResetField)
        }
    }

    if ($items.Count -eq 0) {
        throw (New-QwenException -Code "parse_error" -Message "The QwenCloud quotas could not be recognized.")
    }
    return @($items)
}

function Write-QwenUsageSnapshot {
    param([Parameter(Mandatory = $true)] [object]$Usage)

    Write-QwenJsonAtomically -Path $script:QwenUsagePath -Value $Usage -MutexName "UsageTrayPillQwenUsageWrite"
}

function Read-QwenUsageSnapshotRaw {
    if (-not (Test-Path -LiteralPath $script:QwenUsagePath)) { return $null }
    try {
        return Get-Content -LiteralPath $script:QwenUsagePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch { return $null }
}

function Get-QwenUsageSnapshot {
    $usage = Read-QwenUsageSnapshotRaw
    if ($null -eq $usage) { return $null }

    $copy = $usage | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $lastSuccess = Get-DateOrNull ([string]$copy.lastSuccessAt)
    if ($null -eq $lastSuccess -or ((Get-Date) - $lastSuccess).TotalHours -gt $script:QwenSnapshotMaxAgeHours) {
        $copy.available = $false
        foreach ($item in @($copy.items)) { $item.remainingPercent = $null }
    }
    return $copy
}

function Set-QwenFailureSnapshot {
    param(
        [Parameter(Mandatory = $true)] [string]$Code,
        [Parameter(Mandatory = $true)] [string]$Message
    )

    $previous = Read-QwenUsageSnapshotRaw
    $preserveCodes = @("network_error", "rate_limited", "server_error", "parse_error", "response_too_large")
    $items = @()
    $lastSuccessAt = ""
    if ($Code -in $preserveCodes -and $null -ne $previous) {
        $lastSuccess = Get-DateOrNull ([string]$previous.lastSuccessAt)
        if ($null -ne $lastSuccess -and ((Get-Date) - $lastSuccess).TotalHours -le $script:QwenSnapshotMaxAgeHours) {
            $items = @(As-Array $previous.items)
            $lastSuccessAt = [string]$previous.lastSuccessAt
        }
    }

    Write-QwenUsageSnapshot ([pscustomobject]@{
        version = 1
        source = "qwencloud-token-plan"
        available = ($items.Count -gt 0)
        stale = ($items.Count -gt 0)
        lastCheckedAt = Format-DateForStorage (Get-Date)
        lastSuccessAt = $lastSuccessAt
        lastError = $Code
        lastErrorMessage = $Message
        items = @($items)
    })
}

function Update-QwenUsage {
    if ($script:QwenUsagePollInProgress) { return $false }
    if ($null -eq $script:State -or -not [bool]$script:State.settings.qwenTokenPlanEnabled) { return $false }

    $pollMutex = New-Object System.Threading.Mutex($false, "UsageTrayPillQwenPoll")
    $hasPollLock = $false
    $script:QwenUsagePollInProgress = $true
    try {
        try { $hasPollLock = $pollMutex.WaitOne(0) }
        catch [System.Threading.AbandonedMutexException] { $hasPollLock = $true }
        if (-not $hasPollLock) { return $false }

        $credentials = Get-QwenCredentials
        if ($null -eq $credentials) {
            throw (New-QwenException -Code "setup_required" -Message "Qwen Token Plan has not been set up.")
        }

        $cookieContainer = New-QwenCookieContainer $credentials.cookieHeader
        $secToken = Get-QwenSecToken $cookieContainer
        try {
            $response = Invoke-QwenGatewayRequest -Endpoint "/tokenplan/personal/api/v2/usage" -SecToken $secToken -CookieContainer $cookieContainer
            $items = ConvertFrom-QwenUsageResponse $response
        }
        finally {
            $secToken = $null
        }

        $now = Format-DateForStorage (Get-Date)
        Write-QwenUsageSnapshot ([pscustomobject]@{
            version = 1
            source = "qwencloud-token-plan"
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
        $code = Get-QwenExceptionCode $_
        $message = if ($null -ne $_.Exception -and -not [string]::IsNullOrWhiteSpace([string]$_.Exception.Message)) {
            [string]$_.Exception.Message
        } else {
            "Qwen Token Plan could not be refreshed."
        }
        Set-QwenFailureSnapshot -Code $code -Message $message
        return $false
    }
    finally {
        $script:QwenUsagePollInProgress = $false
        if ($hasPollLock) {
            try { $pollMutex.ReleaseMutex() } catch {
            }
        }
        $pollMutex.Dispose()
    }
}

function Get-QwenStatusText {
    $usage = Get-QwenUsageSnapshot
    if ($null -eq $usage) { return "not configured" }
    if ([bool]$usage.stale -and [bool]$usage.available) { return "cache" }
    if ([bool]$usage.available) { return "QwenCloud" }
    switch ([string]$usage.lastError) {
        "setup_required" { return "set up" }
        "auth_expired" { return "session expired" }
        "rate_limited" { return "try again later" }
        default { return "error" }
    }
}

function Show-QwenSetupDialog {
    $existing = $null
    try { $existing = Get-QwenCredentials } catch {
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Set up Qwen Token Plan"
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ClientSize = New-Object System.Drawing.Size 620, 300

    $intro = New-Object System.Windows.Forms.Label
    $intro.Location = New-Object System.Drawing.Point 18, 16
    $intro.Size = New-Object System.Drawing.Size 580, 48
    $intro.Text = "Experimental: reads usage from QwenCloud dashboard interfaces every two minutes. These formats may change. The session is encrypted for your Windows account only."
    $form.Controls.Add($intro)

    $cookieLabel = New-Object System.Windows.Forms.Label
    $cookieLabel.Location = New-Object System.Drawing.Point 18, 76
    $cookieLabel.Size = New-Object System.Drawing.Size 300, 20
    $cookieLabel.Text = "Cookie request header from home.qwencloud.com"
    $form.Controls.Add($cookieLabel)

    $cookieBox = New-Object System.Windows.Forms.TextBox
    $cookieBox.Location = New-Object System.Drawing.Point 18, 98
    $cookieBox.Size = New-Object System.Drawing.Size 580, 24
    $cookieBox.UseSystemPasswordChar = $true
    $form.Controls.Add($cookieBox)

    $hint = New-Object System.Windows.Forms.Label
    $hint.Location = New-Object System.Drawing.Point 18, 132
    $hint.Size = New-Object System.Drawing.Size 580, 68
    $hint.Text = if ($null -ne $existing) {
        "Leave this field blank to keep the stored session. For a new session, open DevTools > Network, refresh the dashboard, open tool/user/info.json, and copy only the value of Request Headers > Cookie."
    } else {
        "Open DevTools > Network, refresh the dashboard, open tool/user/info.json, and copy only the value of Request Headers > Cookie. Never share this value in screenshots, issues, or logs."
    }
    $form.Controls.Add($hint)

    $dashboardButton = New-Object System.Windows.Forms.Button
    $dashboardButton.Location = New-Object System.Drawing.Point 18, 246
    $dashboardButton.Size = New-Object System.Drawing.Size 145, 30
    $dashboardButton.Text = "Open dashboard"
    $dashboardButton.Add_Click({ Start-Process "$($script:QwenDashboardOrigin)/billing/subscription/token-plan-individual" })
    $form.Controls.Add($dashboardButton)

    $removeButton = New-Object System.Windows.Forms.Button
    $removeButton.Location = New-Object System.Drawing.Point 173, 246
    $removeButton.Size = New-Object System.Drawing.Size 120, 30
    $removeButton.Text = "Disable"
    $removeButton.Enabled = ($null -ne $existing -or [bool]$script:State.settings.qwenTokenPlanEnabled)
    $removeButton.Add_Click({
        Remove-QwenCredentials
        Remove-Item -LiteralPath $script:QwenUsagePath -Force -ErrorAction SilentlyContinue
        $script:State.settings.qwenTokenPlanEnabled = $false
        if ([string]$script:State.settings.taskbarBadgeDefaultSource -eq "qwen") {
            $script:State.settings.taskbarBadgeDefaultSource = "codex"
        }
        Save-State
        $form.DialogResult = [System.Windows.Forms.DialogResult]::Abort
        $form.Close()
    })
    $form.Controls.Add($removeButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Location = New-Object System.Drawing.Point 424, 246
    $cancelButton.Size = New-Object System.Drawing.Size 80, 30
    $cancelButton.Text = "Cancel"
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($cancelButton)

    $saveButton = New-Object System.Windows.Forms.Button
    $saveButton.Location = New-Object System.Drawing.Point 514, 246
    $saveButton.Size = New-Object System.Drawing.Size 84, 30
    $saveButton.Text = "Save"
    $saveButton.Add_Click({
        try {
            $cookieHeader = $cookieBox.Text
            if ([string]::IsNullOrWhiteSpace($cookieHeader)) {
                if ($null -eq $existing) {
                    throw (New-QwenException -Code "invalid_cookie" -Message "Enter the Cookie request header.")
                }
                if ([string]$existing.source -eq "environment") {
                    $script:State.settings.qwenTokenPlanEnabled = $true
                    Save-State
                    $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
                    $form.Close()
                    return
                }
                $cookieHeader = [string]$existing.cookieHeader
            }

            Save-QwenCredentials -CookieHeader $cookieHeader
            $script:State.settings.qwenTokenPlanEnabled = $true
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
        Start-QwenUsageRefresh
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
