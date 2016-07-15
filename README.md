# Telligent Instance Manager
Powershell Scripts to automate the installation of Telligent Community on a local machine.

## Requirements
* IIS 7.5 (or Higher)
* Powershell 5
* Java 8 (or higher)
* Tomcat 8 
* SQL Server 2012 (or higher)

## Installation
1. `Set-ExecutionPolicy RemoteSigned`
2. `Install-Module -Name TelligentInstanceManager`
3. `Initialize-TelligentLocalInstance -Path [Path to install]`

We recommend that the path you install to is high up on your file system (e.g. `c:\TelligentInstances`) - if you install to a deep directory, you may encounter issues within Telligent Community due to Window's MAX_PATH length.

### Packages

After installation, you will need to place a Telligent Community zip package in the TelligentPackages folder in the install location. You can add as many packages as versions you want to support. 

### Licenses

License files can be added to the Licenses folder to allow the installer to add the lincese during the install process. The files should be named Community[Version].xml with [Version] being the product major version number e.g. Community9.xml for Telligent Community 9.

## Usage

#### To install an instance

```Get-TelligentVersion [Version] | Install-TelligentInstance [Name]```

Installs a Telligent Instance on your local machine. Replace `[Version]` with the required version number of Telligent Community e.g. 9 (will use the latest build of Telligent Community available in TelligentPackages) or a specific point release or build  e.g 9.1 or 9.1.0.792 and `[Name]` with the name and URL of the site e.g. demo.local. This is the URL the site will be accessible at in IIS.

Example: `Get-TelligentVersion 9 | Install-TelligentInstance demo.local` 

#### To delete an instance
```Remove-TelligentInstance ```

Deletes an instance of Telligent Community currently installed. Accepts piped parameter from `Get-TelligentInstance -Name [Instance Name]`

Example: `Get-TelligentInstance example.local | Remove-TelligentInstance`
