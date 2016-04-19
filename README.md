# TelligentInstanceManager
Powershell Scripts to automate the installation of Telligent Community on a local machine.

## Dependencies
Coming soon.

##Usage
```Get-TelligentVersion -[VersionNumber]```
Gets a list of Telligent Packages available.

```Install-TelligentInstance -Name [Name]```
Installs a Telligent Instance on your local machine. Accepts the piped results from `Get-TelligentVersion` e.g. `Get-TelligentVersion 9 | Install-TelligentInstance demo.local` 
