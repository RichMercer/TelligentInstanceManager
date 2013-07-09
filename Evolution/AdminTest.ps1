$currentPrincipal = [Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
if (!($currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))) {
	throw "This module requires administrative credentials"
}

#Undo SQLPs's forceing the SqlServer drive
if((get-location).Provider.Name -eq "SqlServer") {
    get-location -PSProvider "FileSystem" | Set-Location
}