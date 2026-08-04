Option Explicit

Dim shell, fileSystem, scriptDirectory, powerShellPath, trayScript, command

Set shell = CreateObject("WScript.Shell")
Set fileSystem = CreateObject("Scripting.FileSystemObject")

scriptDirectory = fileSystem.GetParentFolderName(WScript.ScriptFullName)
powerShellPath = shell.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\WindowsPowerShell\v1.0\powershell.exe"
trayScript = scriptDirectory & "\Start-UsageTrayPill.ps1"
command = Chr(34) & powerShellPath & Chr(34) & " -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " & Chr(34) & trayScript & Chr(34)

shell.Run command, 0, False
