# TelligentInstanceManager
Powershell Scripts to automate the installation of Telligent Community on a local machine.

## Dependencies
* IIS
* Powershell 5
* Java
* Tomcat
* SQL Server

## Installation
1. `Set-ExecutionPolicy RemoteSigned`
2. `Install-Module -Name TelligentLocalInstance`
3. `Initialize-TelligentLocalInstance -Path [Path to install]`

## Usage

#### To install an instance

```Install-TelligentInstance -Name [Name]```

Installs a Telligent Instance on your local machine. Accepts the piped results from `Get-TelligentVersion`.

Example: `Get-TelligentVersion 9 | Install-TelligentInstance demo.local` 

#### To delete an instance
```Remove-TelligentInstance ```

Deletes an instance of Telligent Community currently installed. Accepts piped parameter from `Get-TelligentInstance -Name [Instance Name`

Example: `Get-TelligentInstance example.local | Remove-TelligentInstance`
