Set-StrictMode -Version 2

#Undo SQLPs's forcing the SqlServer drive
if((get-location).Provider.Name -eq 'SqlServer') {
    get-location -PSProvider FileSystem | Set-Location
}

$currentPrincipal = [Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
if (!($currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator'))) {
    Write-Warning 'This module requires administrative credentials'
    Start-Process powershell.exe '-NoExit -Command "Write-Host "Loading..."; ipmo TelligentInstall"' -Verb runas
	throw 'Cannot continue in current unelevated prompt.  Please switch to the elvated prompt.'
}