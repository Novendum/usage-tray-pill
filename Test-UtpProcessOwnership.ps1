$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'ExternalUsageAdapters.ps1')
. (Join-Path $PSScriptRoot 'Test-ProcessHelpers.ps1')
function Check([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
$root=Join-Path $env:TEMP ('UtpOwnershipTest-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $root)
$exe=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$bystander=$null
try {
    # A sibling outside the adapter's ownership must survive every cleanup.
    $bystander=Start-UtpHiddenTestProcess $exe @('-NoProfile','-Command','"Start-Sleep -Seconds 60"')
    foreach($mode in @('timeout','parent-exit','control-return')) {
        $recordPath=Join-Path $root ($mode+'.json')
        $childCode='Start-Sleep -Seconds 60'
        $encodedChild=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childCode))
        $finish=switch($mode){
            'timeout' {'Start-Sleep -Seconds 60'}
            'parent-exit' {'exit 0'}
            'control-return' {@'
[void][Console]::ReadLine()
[Console]::WriteLine('{"type":"control_response","response":{"request_id":"utp-init","subtype":"success","response":{}}}')
[void][Console]::ReadLine()
[Console]::WriteLine('{"type":"control_response","response":{"request_id":"utp-usage","subtype":"success","response":{"ok":true}}}')
Start-Sleep -Seconds 60
'@}
        }
        $parentCode=@"
`$info=New-Object Diagnostics.ProcessStartInfo
`$info.FileName='$exe'
`$info.Arguments='-NoProfile -EncodedCommand $encodedChild'
`$info.UseShellExecute=`$false
`$info.CreateNoWindow=`$true
`$child=[Diagnostics.Process]::Start(`$info)
@{pid=`$child.Id;ticks=`$child.StartTime.ToUniversalTime().Ticks}|ConvertTo-Json|Set-Content -LiteralPath '$recordPath'
$finish
"@
        $encodedParent=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($parentCode))
        $failure='';$result=$null
        try {$result=Invoke-UtpExternalUsageCommand $exe @('-NoProfile','-EncodedCommand',$encodedParent) -TimeoutMilliseconds 4000 -ClaudeUsageControl:($mode -eq 'control-return')}
        catch {$failure=$_.Exception.Message}
        Check (Test-Path $recordPath) "The $mode fixture must start its owned child"
        $record=Get-Content $recordPath -Raw|ConvertFrom-Json
        $child=Get-Process -Id $record.pid -ErrorAction SilentlyContinue
        if($null -ne $child){[void]$child.WaitForExit(2000);$child.Refresh()}
        $alive=$null -ne $child -and -not $child.HasExited -and $child.StartTime.ToUniversalTime().Ticks -eq $record.ticks
        Check (-not $alive) "Adapter cleanup must stop its descendant after $mode"
        if($mode -eq 'timeout'){Check ($failure -match 'timeout') 'Timeout must retain its existing error'}
        else {Check (-not $failure -and $result.ExitCode -eq 0) "$mode must complete successfully"}
        Check (-not $bystander.HasExited) 'Adapter cleanup must preserve unrelated sibling processes'
    }
    # Binary stdin ensures the JSONL protocol starts with {, never a UTF-8 BOM.
    $stdinCode=@'
$first=[Console]::OpenStandardInput().ReadByte()
if($first -ne 123){[Console]::WriteLine('{"type":"user"}');exit 17}
exit 0
'@
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($stdinCode))
    $failure=''
    try {Invoke-UtpExternalUsageCommand $exe @('-NoProfile','-EncodedCommand',$encoded) -TimeoutMilliseconds 4000 -ClaudeUsageControl|Out-Null} catch {$failure=$_.Exception.Message}
    Check ($failure -match 'missing_usage_response') 'Control stdin must have no BOM and reach the binary fixture'

    Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class UtpOwnershipHandleFixture {
 [DllImport("kernel32.dll",SetLastError=true)] public static extern bool SetHandleInformation(IntPtr h,uint mask,uint flags);
}
'@
    $unrelatedEvent=New-Object Threading.ManualResetEvent $false
    try {
        $handle=$unrelatedEvent.SafeWaitHandle.DangerousGetHandle()
        Check ([UtpOwnershipHandleFixture]::SetHandleInformation($handle,1,1)) 'Prepare an unrelated inheritable handle'
        $childCode=@"
Add-Type 'using System;using System.Runtime.InteropServices;public static class Probe {[DllImport("kernel32.dll")] public static extern bool SetEvent(IntPtr h);}'
[void][Probe]::SetEvent([IntPtr]$($handle.ToInt64()))
"@
        $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childCode))
        $result=Invoke-UtpExternalUsageCommand $exe @('-NoProfile','-EncodedCommand',$encoded) -TimeoutMilliseconds 5000
        Check ($result.ExitCode -eq 0) 'Handle fixture must execute successfully'
        Check (-not $unrelatedEvent.WaitOne(0)) 'Only the three standard pipes may cross the process boundary'
    } finally {$unrelatedEvent.Dispose()}

    # The outer adapter puts PowerShell in a job before it starts another adapter.
    $leaf=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes("[Console]::WriteLine('nested-job-ok')"))
    $nestedCode=@"
. '$PSScriptRoot\ExternalUsageAdapters.ps1'
`$result=Invoke-UtpExternalUsageCommand '$exe' @('-NoProfile','-EncodedCommand','$leaf') -TimeoutMilliseconds 4000
[Console]::WriteLine(`$result.Output.Trim())
"@
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($nestedCode))
    $result=Invoke-UtpExternalUsageCommand $exe @('-NoProfile','-EncodedCommand',$encoded) -TimeoutMilliseconds 10000
    Check ($result.ExitCode -eq 0 -and $result.Output.Trim() -eq 'nested-job-ok') 'An existing job must allow isolated nested ownership'
    $failed=$false
    try {Invoke-UtpExternalUsageCommand (Join-Path $root 'missing.exe') @() -TimeoutMilliseconds 1000|Out-Null} catch {$failed=$true}
    Check $failed 'An unavailable executable must fail closed'

    $savedSentinel=$env:UTP_OWNERSHIP_TEST_SENTINEL
    $savedOverride=$env:UTP_OWNERSHIP_TEST_OVERRIDE
    try {
        $env:UTP_OWNERSHIP_TEST_SENTINEL='inherited-'+[char]0x20AC
        $env:UTP_OWNERSHIP_TEST_OVERRIDE='original'
        $envCode=@'
[Console]::OutputEncoding=New-Object Text.UTF8Encoding $false
[Console]::WriteLine((@{sentinel=$env:UTP_OWNERSHIP_TEST_SENTINEL;value=$env:UTP_OWNERSHIP_TEST_OVERRIDE}|ConvertTo-Json -Compress))
'@
        $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($envCode))
        $argsText='-NoProfile -EncodedCommand '+$encoded
        $child=[UtpOwnedUsageProcess]::Start($exe,$argsText,$root,@{utp_ownership_test_override='true'})
        try {
            $child.StandardInput.Close()
            Check ($child.WaitForExit(4000)) 'Environment fixture must finish'
            $values=$child.StandardOutput.ReadToEnd()|ConvertFrom-Json
            Check ($values.sentinel -eq $env:UTP_OWNERSHIP_TEST_SENTINEL) 'Override must preserve inherited Unicode environment values'
            Check ($values.value -eq 'true') 'Override must replace the inherited name case-insensitively'
            Check ($env:UTP_OWNERSHIP_TEST_OVERRIDE -eq 'original') 'Override must not mutate the parent environment'
        } finally {$child.Dispose()}
        $child=[UtpOwnedUsageProcess]::Start($exe,$argsText,$root)
        try {
            $child.StandardInput.Close()
            Check ($child.WaitForExit(4000)) 'Second environment fixture must finish'
            $values=$child.StandardOutput.ReadToEnd()|ConvertFrom-Json
            Check ($values.value -eq 'original') 'An override must not leak into a later child without overrides'
            Check ($values.sentinel -eq $env:UTP_OWNERSHIP_TEST_SENTINEL) 'The original overload must retain inherited environment'
        } finally {$child.Dispose()}
        foreach($bad in @(@{''='invalid'},@{'BAD=NAME'='invalid'},@{("BAD"+[char]0)='invalid'},@{'BAD_VALUE'=("bad"+[char]0)},@{'BAD_VALUE'=$null})) {
            $rejected=$false;$child=$null
            try {$child=[UtpOwnedUsageProcess]::Start($exe,$argsText,$root,$bad)}
            catch {$rejected=$true}
            finally {if($null -ne $child){$child.Dispose()}}
            Check $rejected 'Malformed environment overrides must be rejected before execution'
        }
    } finally {
        $env:UTP_OWNERSHIP_TEST_SENTINEL=$savedSentinel
        $env:UTP_OWNERSHIP_TEST_OVERRIDE=$savedOverride
    }
    Write-Output 'External process ownership tests OK (cleanup, isolation, UTF-8, nested job, failed start, child-only Unicode environment overrides)'
} finally {
    foreach($path in @(Get-ChildItem -LiteralPath $root -Filter '*.json')) {
        $record=Get-Content -LiteralPath $path.FullName -Raw|ConvertFrom-Json
        $child=Get-Process -Id $record.pid -ErrorAction SilentlyContinue
        if($null -ne $child -and $child.StartTime.ToUniversalTime().Ticks -eq $record.ticks){$child.Kill();[void]$child.WaitForExit(2000);$child.Dispose()}
    }
    if($null -ne $bystander){if(-not $bystander.HasExited){$bystander.Kill();[void]$bystander.WaitForExit(2000)};$bystander.Dispose()}
    $resolved=[IO.Path]::GetFullPath($root)
    if($resolved.StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'UtpOwnershipTest-*'){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
