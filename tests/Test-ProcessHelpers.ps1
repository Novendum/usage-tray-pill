function Start-UtpHiddenTestProcess {
    param([string]$FilePath, [string[]]$ArgumentList)
    $info=New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName=$FilePath
    # Call sites supply quoted paths, just as with Start-Process -ArgumentList.
    $info.Arguments=$ArgumentList -join ' '
    $info.UseShellExecute=$false
    $info.CreateNoWindow=$true
    $info.WindowStyle=[System.Diagnostics.ProcessWindowStyle]::Hidden
    $info.RedirectStandardOutput=$true
    $info.RedirectStandardError=$true
    $process=[System.Diagnostics.Process]::Start($info)
    $process|Add-Member -NotePropertyName UtpTestOutput -NotePropertyValue $process.StandardOutput.ReadToEndAsync()
    $process|Add-Member -NotePropertyName UtpTestError -NotePropertyValue $process.StandardError.ReadToEndAsync()
    return $process
}
